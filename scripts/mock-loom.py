#!/usr/bin/env python3
"""mock-loom.py - reverse proxy in front of a real Loom media server that also
synthesizes GET /api/v1/channels, an endpoint Loom does not implement yet.

Everything except GET /api/v1/channels is proxied verbatim to the real server
(including Range requests, so the tvOS client can stream video through here).
The channel lineup is built once at startup from the real catalog and served
from memory; the response shape below is the API contract.

Usage:
    scripts/mock-loom.py --loom http://10.100.90.20:8097 --port 8098 [--seed 1234]
"""

import argparse
import http.server
import json
import random
import socket
import socketserver
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# Constants that define the lineup. Order here fixes channel numbering, so do
# not reorder without accepting that every channel number changes.
# ---------------------------------------------------------------------------

TOP_SHOWS = 4            # rule 1: N shows with the most playable episodes
TOP_GENRES = 4           # rule 2: N movie genres with the most playable movies
POOL_CAP = 120           # max candidates kept per shuffled channel
HDR_RANGES = ("hdr", "dolby_vision")
PAGE_LIMIT = 200
CATALOG_WORKERS = 16
PLAYBACK_WORKERS = 16
DEFAULT_HOURS = 24
MIN_HOURS = 1
MAX_HOURS = 48
LOOKBACK_MS = 3600 * 1000                  # schedule starts one hour before startup
HORIZON_MS = MAX_HOURS * 3600 * 1000       # ... and runs far enough ahead to serve hours=48
PROXY_CHUNK = 256 * 1024
UPSTREAM_TIMEOUT = 120
CATALOG_TIMEOUT = 60

HOP_BY_HOP = frozenset([
    "host", "connection", "keep-alive", "transfer-encoding", "upgrade",
    "proxy-connection", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "trailers",
])

CHANNELS_PATH = "/api/v1/channels"


def log(msg):
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


def rfc3339(ms):
    """Whole-second RFC 3339 UTC. Truncates, so back-to-back programs share a boundary."""
    return datetime.fromtimestamp(ms // 1000, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def strip_headers(pairs, extra=()):
    out = []
    for key, value in pairs:
        low = key.lower()
        if low in HOP_BY_HOP or low.startswith("proxy-") or low in extra:
            continue
        out.append((key, value))
    return out


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Redirects belong to the client, not the proxy."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# ---------------------------------------------------------------------------
# Loom catalog client
# ---------------------------------------------------------------------------


class Loom:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.opener = urllib.request.build_opener()

    def get_json(self, path, timeout=CATALOG_TIMEOUT, attempts=3):
        last = None
        for attempt in range(attempts):
            try:
                with self.opener.open(self.base + path, timeout=timeout) as resp:
                    return json.loads(resp.read().decode("utf-8"))
            except Exception as exc:  # transient upstream hiccups are common on cold caches
                last = exc
                if attempt + 1 < attempts:
                    time.sleep(0.4 * (attempt + 1))
        raise RuntimeError("GET %s failed: %s" % (path, last))

    def list_items(self, library_kind):
        items = []
        offset = 0
        while True:
            data = self.get_json("/api/v1/items?library=%s&limit=%d&offset=%d"
                                 % (urllib.parse.quote(library_kind), PAGE_LIMIT, offset))
            page = data.get("items") or []
            items.extend(page)
            if len(page) < PAGE_LIMIT:
                return items
            offset += PAGE_LIMIT

    def children(self, item_id):
        data = self.get_json("/api/v1/items/%s/children?limit=%d" % (item_id, PAGE_LIMIT))
        return data.get("items") or []

    def playback(self, item_id):
        return self.get_json("/api/v1/items/%s/playback" % item_id)


# ---------------------------------------------------------------------------
# Lineup construction
# ---------------------------------------------------------------------------


def clean_item(item):
    out = dict(item)
    out.pop("credits", None)
    out.pop("progress", None)
    return out


def first_video(playback):
    media = playback.get("media") or {}
    for stream in media.get("streams") or []:
        if stream.get("kind") == "video":
            return stream
    return None


def video_block(stream):
    block = {}
    for key in ("codec", "width", "height", "resolution", "dynamic_range"):
        if stream.get(key) is not None:
            block[key] = stream[key]
    return block


def channel_rng(seed, key):
    # random.Random(str) hashes the string with sha512 internally, so this is
    # stable across processes regardless of PYTHONHASHSEED.
    return random.Random("%s:%s" % (seed, key))


class Program:
    __slots__ = ("pid", "start_ms", "end_ms", "entry")

    def __init__(self, pid, start_ms, end_ms, entry):
        self.pid = pid
        self.start_ms = start_ms
        self.end_ms = end_ms
        self.entry = entry

    def to_json(self):
        out = {
            "id": self.pid,
            "starts_at": rfc3339(self.start_ms),
            "ends_at": rfc3339(self.end_ms),
            "item": self.entry.item_json,
        }
        if self.entry.video is not None:
            out["video"] = self.entry.video
        out["stream_url"] = self.entry.stream_url
        return out


class Entry:
    """A playable catalog item plus everything the contract needs about it."""

    __slots__ = ("item_id", "item_json", "duration_ms", "stream_url", "video",
                 "dynamic_range", "kind", "show_id", "season_number", "episode_number",
                 "genre_ids", "title")

    def __init__(self, item, playback):
        self.item_id = item["id"]
        self.item_json = clean_item(item)
        self.title = item.get("title") or ""
        self.kind = item.get("kind")
        media = playback.get("media") or {}
        self.duration_ms = media.get("duration_ms") or item.get("duration_ms") or 0
        self.stream_url = playback.get("stream_url")
        stream = first_video(playback)
        self.video = video_block(stream) if stream else None
        self.dynamic_range = (stream or {}).get("dynamic_range")
        self.genre_ids = [(g.get("id"), g.get("name")) for g in (item.get("genres") or [])]
        self.show_id = None
        self.season_number = None
        self.episode_number = item.get("episode_number")

    @property
    def usable(self):
        return bool(self.stream_url) and self.duration_ms and self.duration_ms > 0


class Channel:
    def __init__(self, number, key, name, programs):
        self.number = number
        self.key = key
        self.name = name
        self.programs = programs

    def to_json(self, win_start, win_end):
        progs = [p.to_json() for p in self.programs
                 if p.end_ms > win_start and p.start_ms < win_end]
        return {
            "id": self.number,
            "number": self.number,
            "key": self.key,
            "name": self.name,
            "programs": progs,
        }


def lay_out(pick_next, start_ms, end_ms, counter):
    """Lay programs back to back at their real durations, no rounding, no gaps."""
    programs = []
    cursor = start_ms
    while cursor < end_ms:
        entry = pick_next()
        if entry is None:
            break
        stop = cursor + entry.duration_ms
        programs.append(Program(next(counter), cursor, stop, entry))
        cursor = stop
    return programs


def sequential_picker(entries):
    state = {"i": 0}

    def pick():
        if not entries:
            return None
        entry = entries[state["i"] % len(entries)]
        state["i"] += 1
        return entry

    return pick


def shuffled_picker(entries, rng):
    """Random order without repeats; reshuffle only once the pool is exhausted."""
    order = list(entries)
    state = {"i": len(order)}

    def pick():
        if not order:
            return None
        if state["i"] >= len(order):
            rng.shuffle(order)
            state["i"] = 0
        entry = order[state["i"]]
        state["i"] += 1
        return entry

    return pick


def build_lineup(loom, seed):
    t0 = time.time()

    libraries = (loom.get_json("/api/v1/libraries").get("items") or [])
    kinds = [lib.get("kind") for lib in libraries if lib.get("kind")]
    movie_kinds = [k for k in kinds if k in ("movies", "shorts")]
    tv_kinds = [k for k in kinds if k == "tv"]

    raw_movies = []
    for kind in movie_kinds:
        raw_movies.extend(loom.list_items(kind))
    shows = []
    for kind in tv_kinds:
        shows.extend(loom.list_items(kind))

    # Seasons then episodes, two concurrent fan-out waves.
    episodes = []
    season_owner = {}
    with ThreadPoolExecutor(CATALOG_WORKERS) as pool:
        seasons = []
        for show, kids in zip(shows, pool.map(loom.children, [s["id"] for s in shows])):
            for season in kids:
                season_owner[season["id"]] = (show["id"], season.get("season_number"))
                seasons.append(season)
        for season, kids in zip(seasons, pool.map(loom.children, [s["id"] for s in seasons])):
            episodes.extend(kids)

    candidates = [i for i in raw_movies if i.get("media_tag")]
    candidates += [e for e in episodes if e.get("media_tag")]
    log("catalog: %d movies, %d shows, %d seasons, %d episodes, %d playable candidates (%.1fs)"
        % (len(raw_movies), len(shows), len(seasons), len(episodes), len(candidates),
           time.time() - t0))

    # Membership in the HDR channel is only knowable after probing, so the probe
    # covers the whole candidate set rather than a per-channel slice. Results are
    # cached by item id, so an item on several channels is fetched once.
    playback_by_id = {}
    done = [0]
    lock = threading.Lock()
    total = len(candidates)

    def probe(item):
        try:
            data = loom.playback(item["id"])
        except Exception:
            data = None
        with lock:
            done[0] += 1
            if done[0] % 100 == 0 or done[0] == total:
                sys.stderr.write("\rplayback: %d/%d" % (done[0], total))
                sys.stderr.flush()
        return data

    t1 = time.time()
    with ThreadPoolExecutor(PLAYBACK_WORKERS) as pool:
        for item, data in zip(candidates, pool.map(probe, candidates)):
            if data is not None:
                playback_by_id[item["id"]] = data
    sys.stderr.write("\rplayback: %d/%d in %.1fs\n" % (done[0], total, time.time() - t1))
    sys.stderr.flush()

    entries = []
    for item in candidates:
        data = playback_by_id.get(item["id"])
        if not data:
            continue
        entry = Entry(item, data)
        if not entry.usable:
            continue
        if item.get("kind") == "episode":
            owner = season_owner.get(item.get("parent_id"))
            if not owner:
                continue
            entry.show_id = owner[0]
            season_number = item.get("season_number")
            if season_number is None:
                season_number = owner[1]
            entry.season_number = season_number if season_number is not None else 0
        entries.append(entry)

    movie_entries = [e for e in entries if e.show_id is None]
    episode_entries = [e for e in entries if e.show_id is not None]

    show_title = {s["id"]: (s.get("title") or "") for s in shows}
    eps_by_show = {}
    for entry in episode_entries:
        # Loom names the show on every channel episode (series_title), since
        # the lineup hands episodes out outside their show hierarchy.
        if show_title.get(entry.show_id):
            entry.item_json["series_title"] = show_title[entry.show_id]
        eps_by_show.setdefault(entry.show_id, []).append(entry)

    genre_name = {}
    movies_by_genre = {}
    for entry in movie_entries:
        for gid, gname in entry.genre_ids:
            if gid is None:
                continue
            genre_name.setdefault(gid, gname or str(gid))
            movies_by_genre.setdefault(gid, []).append(entry)

    startup_ms = int(time.time() * 1000)
    start_ms = startup_ms - LOOKBACK_MS
    end_ms = startup_ms + HORIZON_MS
    counter = iter(range(1, 1 << 30))

    channels = []

    def add(key, name, picker):
        programs = lay_out(picker, start_ms, end_ms, counter)
        if not programs:
            return
        channels.append(Channel(len(channels) + 1, key, name, programs))

    # Rule 1: the shows with the most playable episodes, aired in order and looping.
    ranked_shows = sorted(eps_by_show.items(),
                          key=lambda kv: (-len(kv[1]), show_title.get(kv[0], ""), kv[0]))
    for show_id, eps in ranked_shows[:TOP_SHOWS]:
        ordered = sorted(eps, key=lambda e: (e.season_number or 0, e.episode_number or 0, e.item_id))
        add("show:%s" % show_id, show_title.get(show_id, "Show %s" % show_id),
            sequential_picker(ordered))

    # Rule 2: the movie genres with the most playable movies.
    ranked_genres = sorted(movies_by_genre.items(),
                           key=lambda kv: (-len(kv[1]), genre_name.get(kv[0], ""), kv[0]))
    for gid, movies in ranked_genres[:TOP_GENRES]:
        key = "genre:%s" % gid
        rng = channel_rng(seed, key)
        pool = cap_pool(movies, rng)
        add(key, genre_name.get(gid, str(gid)), shuffled_picker(pool, rng))

    # Rule 3: everything whose first video stream is HDR or Dolby Vision.
    hdr = [e for e in entries if e.dynamic_range in HDR_RANGES]
    if hdr:
        rng = channel_rng(seed, "hdr")
        add("hdr", "HDR", shuffled_picker(cap_pool(hdr, rng), rng))

    # Rule 4: everything playable.
    if entries:
        rng = channel_rng(seed, "mix")
        add("mix", "Mix", shuffled_picker(cap_pool(entries, rng), rng))

    elapsed = time.time() - t0
    log("")
    log("lineup built in %.1fs (seed %s), window %s .. %s"
        % (elapsed, seed, rfc3339(start_ms), rfc3339(end_ms)))
    for ch in channels:
        log("  %2d  %-14s %-28s %4d programs  %s .. %s"
            % (ch.number, ch.key, ch.name[:28], len(ch.programs),
               rfc3339(ch.programs[0].start_ms), rfc3339(ch.programs[-1].end_ms)))
    log("")
    return channels


def cap_pool(entries, rng):
    """Deterministic bounded candidate pool: stable base order, shuffle, truncate."""
    base = sorted(entries, key=lambda e: e.item_id)
    if len(base) <= POOL_CAP:
        return base
    order = list(base)
    rng.shuffle(order)
    return order[:POOL_CAP]


def render_channels(channels, hours):
    now_ms = int(time.time() * 1000)
    win_start = now_ms - LOOKBACK_MS
    win_end = now_ms + hours * 3600 * 1000
    return {
        "now": rfc3339(now_ms),
        "items": [ch.to_json(win_start, win_end) for ch in channels],
    }


# ---------------------------------------------------------------------------
# HTTP front end
# ---------------------------------------------------------------------------


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "mock-loom"
    sys_version = ""

    channels = []
    loom_base = ""
    opener = None

    def log_message(self, fmt, *args):
        pass  # access logs would drown the startup summary during media streaming

    def _dead(self, exc):
        self.close_connection = True
        _ = exc  # client hung up mid-stream; nothing to report

    def do_GET(self):
        self._dispatch(body=True)

    def do_HEAD(self):
        self._dispatch(body=False)

    def do_POST(self):
        self._dispatch(body=True)

    def do_PUT(self):
        self._dispatch(body=True)

    def do_PATCH(self):
        self._dispatch(body=True)

    def do_DELETE(self):
        self._dispatch(body=True)

    def do_OPTIONS(self):
        self._dispatch(body=True)

    def _dispatch(self, body):
        try:
            path = urllib.parse.urlsplit(self.path).path
            if self.command in ("GET", "HEAD") and path == CHANNELS_PATH:
                self._channels(body)
            else:
                self._proxy(body)
        except (BrokenPipeError, ConnectionResetError, TimeoutError, socket.timeout) as exc:
            self._dead(exc)

    def _channels(self, body):
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        hours = DEFAULT_HOURS
        raw = (query.get("hours") or [None])[0]
        if raw is not None:
            try:
                hours = int(raw)
            except ValueError:
                hours = DEFAULT_HOURS
        hours = max(MIN_HOURS, min(MAX_HOURS, hours))
        payload = json.dumps(render_channels(self.channels, hours)).encode("utf-8")
        self.send_response_only(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(payload)

    def _proxy(self, body):
        url = self.loom_base + self.path
        payload = None
        length = self.headers.get("Content-Length")
        if length:
            try:
                count = int(length)
            except ValueError:
                count = 0
            if count > 0:
                payload = self.rfile.read(count)
        req = urllib.request.Request(url, data=payload, method=self.command)
        for key, value in strip_headers(self.headers.items()):
            req.add_header(key, value)
        try:
            resp = self.opener.open(req, timeout=UPSTREAM_TIMEOUT)
        except urllib.error.HTTPError as exc:
            resp = exc  # pass upstream 4xx/5xx/3xx straight through
        except Exception as exc:
            self._bad_gateway(exc)
            return
        try:
            status = resp.getcode()
            headers = strip_headers(resp.headers.items())
            has_length = any(k.lower() == "content-length" for k, _ in headers)
            self.send_response_only(status)
            for key, value in headers:
                self.send_header(key, value)
            if not has_length:
                # No framing from upstream, so close to delimit the body.
                self.send_header("Connection", "close")
                self.close_connection = True
            self.end_headers()
            if not body or self.command == "HEAD":
                return
            while True:
                chunk = resp.read(PROXY_CHUNK)
                if not chunk:
                    break
                self.wfile.write(chunk)
        finally:
            try:
                resp.close()
            except Exception:
                pass

    def _bad_gateway(self, exc):
        payload = json.dumps({"error": "upstream unreachable", "detail": str(exc)}).encode("utf-8")
        self.send_response_only(502)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        self.wfile.write(payload)


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    parser = argparse.ArgumentParser(description="Loom reverse proxy with synthesized channels")
    parser.add_argument("--loom", default="http://10.100.90.20:8097")
    parser.add_argument("--port", type=int, default=8098)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--seed", type=int, default=1234)
    args = parser.parse_args()

    base = args.loom.rstrip("/")
    log("mock-loom: upstream %s, listening on %s:%d, seed %d" % (base, args.host, args.port, args.seed))
    channels = build_lineup(Loom(base), args.seed)

    Handler.channels = channels
    Handler.loom_base = base
    Handler.opener = urllib.request.build_opener(NoRedirect)

    httpd = Server((args.host, args.port), Handler)
    log("ready: GET http://%s:%d%s?hours=24" % (args.host, args.port, CHANNELS_PATH))
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
