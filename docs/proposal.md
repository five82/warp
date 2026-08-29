# Warp — proposal

Warp is a tvOS-only "fake linear TV" app for Loom. Loom owns a lineup of
channels and a rolling schedule; Warp plays whatever is on the chosen channel
right now, from the right offset, and lets you flip channels with the remote.
Nothing streams in the background; the illusion is built from Loom's schedule
plus mid-file seeks.

Status: approved 2026-08-29 (section 7) and implemented as a proof of
concept in both repos; see `AGENTS.md` for the measured on-device baseline
(no mode switches while surfing, ~450-800 ms per flip).

## 1. What the research established

### Library (live Loom, 2026-08-29)

- 2,204 playable items (281 movies, 13 shorts, 1,910 episodes across 30
  shows), 1,590 hours total.
- Video: ~95% SDR. HDR is 64 HEVC 4K + 44 AV1 4K (+2 AV1 4K Dolby Vision).
  46 titles are 4K AV1 and cannot play on the current A12 box.
- 207 titles are 1080p AV1 (software dav1d, plays today in Takeup).
- Loom already stores per-stream `codec`, `width`/`height`, derived
  `resolution`, and `dynamic_range` (`sdr|hdr|dolby_vision`), plus
  `duration_ms`, `container`, chapters. It does **not** store frame rate.
- Server latency from this Mac: ~18 ms TTFB on any Range request,
  including a tail range (where MKV cues live). The network is not the
  channel-change bottleneck; demuxer open and decoder spin-up are.

### What Takeup gives us

- A working tvOS libmpv player: `vo=gpu-next`, `gpu-api=vulkan`,
  `gpu-context=moltenvk`, `hwdec=videotoolbox`, `target-colorspace-hint=yes`,
  rendering into a `CAMetalLayer` handed to mpv via `wid`. HDR10 passthrough
  verified on the box. No cache/demuxer/seek tuning at all.
- One mpv instance per playback, no preloading, no measurement of
  loadfile-to-first-frame. `loadfile url replace -1 start=<s>` is already
  the mechanism for landing mid-program.
- `PlaybackGate` (live `VTIsHardwareDecodeSupported(AV1)` check, unit tested).
- Loom client + models, Bonjour discovery, server onboarding/settings, the
  whole design-token layer, `CachedImage`, the XCUIRemote driver script for
  the headless tvOS simulator, and Swift Testing unit tests for pure logic.
- Zero `AVDisplayManager` usage. HDR/SDR switching is left entirely to the
  box's Match Content setting, which renegotiates HDMI on every HDR<->SDR
  boundary (1-8 s of black, worse through an AVR).

### tvOS facts (verified against the tvOS 27 SDK headers on this Mac)

- `AVDisplayCriteria(refreshRate:formatDescription:)` exists (tvOS 17+).
  It takes a `CMFormatDescription`, so an HDR10 HEVC 4K format description
  at 60 Hz expresses "HDR10 at 60 Hz".
- `AVDisplayManager.preferredDisplayCriteria` is honored only when the
  user's Match Content setting allows it (it does on this box). Set once
  and left alone, no further switches happen. Whether the box drops the
  criteria on background/screensaver is undocumented; re-apply on
  foreground and verify on device.
- `CAMetalLayer.wantsExtendedDynamicRangeContent` and `edrMetadata` do not
  exist on tvOS; MoltenVK's `setHDRMetadataEXT` is a macOS-only no-op. So
  per-title HDR10 static metadata (MaxCLL/MaxFALL) is never sent from this
  stack anyway. The display mode determines the wire format; the layer's
  `colorspace` (`kCGColorSpaceITUR_2100_PQ`) tells CoreAnimation how to
  interpret our pixels.

## 2. Core technical decisions

### 2.1 HDR: everything is rendered into a PQ/BT.2020 surface, always

Answer to "can we play everything in HDR10 colorspace with SDR looking like
SDR": yes, and mpv/libplacebo does it correctly by design.

mpv options (in addition to Takeup's):

```
target-trc=pq
target-prim=bt.2020
target-peak=auto            # = 10000 nits for PQ. Do NOT set the TV's real peak.
target-contrast=auto
tone-mapping=auto           # identity for every real source; see below
inverse-tone-mapping=no
hdr-compute-peak=no
hdr-reference-white=203     # SDR white in the PQ container (BT.2408)
target-colorspace-hint=yes  # already in Takeup; must be set before init
force-window=immediate      # keeps the VO/swapchain alive across loadfile
```

Why this meets "no tone mapping":

- With `target-trc` and `target-prim` set explicitly, mpv's swapchain hint
  is always `{BT.2020, PQ}` regardless of the source, so the swapchain and
  the layer colorspace never change on a channel flip.
- HDR10 sources: `target-peak=auto` on a PQ target is 10,000 nits, which
  exceeds any mastering peak, so libplacebo's tone-mapping curve collapses
  to identity. PQ in, PQ out, unchanged.
- SDR sources: libplacebo places SDR reference white at 203 nits absolute
  (`MP_REF_WHITE`, BT.2408) and, with inverse tone mapping off, never
  raises the input ceiling above the source's. BT.709 -> BT.2020 is an
  exact matrix. Nothing is stretched; it is the same "SDR in an HDR
  container" that consoles and set-top boxes do.

Known, honest deltas from a TV's native SDR mode:

- libplacebo decodes BT.709 with BT.1886 (gamma ~2.4), which is standard
  but reads slightly punchier than TVs that run SDR near 2.2.
  `--gamma-factor` is the knob if it bothers us.
- Slight black-point compensation runs for SDR (source min 0.2 nits vs PQ
  target min ~0). Leave it; the alternative lifts HDR blacks.
- The TV is in its HDR picture mode, with that mode's processing. 203-nit
  diffuse white is brighter than a 100-nit calibrated SDR mode. If the
  wife finds SDR channels too bright, `hdr-reference-white=100` is a
  one-line change.

`force-window=immediate` matters: without it mpv tears down the VO on every
`loadfile`, which rebuilds the Vulkan device and swapchain (hundreds of ms)
and would drop the pinned PQ layer at exactly the moment we care about.

### 2.2 Display mode: pin once at launch, never touch it again

Two ways to stop the HDMI resync; I recommend doing the first and keeping
the second as the zero-code fallback.

1. **In-app pin (recommended).** On launch, set
   `AVDisplayManager.preferredDisplayCriteria` to an HDR10 4K HEVC format
   description at 60 Hz, and re-apply on foreground. With Match Content
   on, the box switches once (SDR home screen -> HDR10) when Warp opens and
   once when it exits, never in between. Takeup and every other app keep
   behaving as they do today.
2. **Box setting fallback.** Format = 4K Dolby Vision, Match Dynamic Range
   off. The box never leaves HDR; tvOS composites our PQ layer into it.
   No code, but it changes the behavior of every other app.

Warp reads `isDisplayCriteriaMatchingEnabled` at launch. If matching is
off, the criteria is ignored and the box stays in whatever Format is set;
Warp then keeps its PQ output only if that format is HDR (it is, on this
box) and would otherwise fall back to an SDR target. Once per launch, never
per channel.

Frame rate: pin 60 Hz. The grid UI wants 60, the library mixes 23.976/24/
25/29.97/30/60, and any frame-rate switch is an HDMI resync just like a
range switch. 24p content gets 3:2 pulldown, which is what Takeup does
today (it never requests a mode). Loom therefore does not need to learn
frame rates for this project.

### 2.3 Channel change: one warm mpv, keyframe seek, no API calls on the path

Target: press-to-picture well under one second. Plan:

- **Zero network round trips to Loom on a flip.** The client holds the
  whole lineup (every channel's programs through the horizon, each with
  its `stream_url`) and computes the offset locally from the synced clock.
  A flip is exactly one mpv command.
- `loadfile <url> replace -1 start=<offset>,hr-seek=no`. Keyframe seek
  lands a few seconds before "live", which is invisible on a fake channel
  and avoids decoding a whole GOP before the first frame.
- Low-latency mpv settings: `cache-pause=no`, `cache-pause-initial=no`
  (default), `video-latency-hacks=yes`, `interpolation=no`,
  `stream-buffer-size=4k`, `stream-lavf-o=multiple_requests=1`
  (keep-alive), `demuxer-mkv-probe-video-duration=no` (default). Note
  mpv's built-in `[low-latency]` profile's `demuxer-lavf-*` lines do
  nothing for Matroska (mpv uses its own MKV demuxer).
- Within a channel, program-to-program transitions use mpv's playlist:
  the next program is appended and `prefetch-playlist=yes` opens it as the
  current file drains, so the boundary is seamless with no client work.
- **Measure first.** Phase 0 below instruments loadfile -> first frame on
  the physical box before we build anything else. If it is ~300-600 ms we
  are done. If it is not, phase 3 adds a second hidden mpv instance
  pre-tuned to the channel above (surfing is mostly one direction) and
  swaps layers on press; that doubles GPU/decoder cost and needs a memory
  check, so it is a fallback rather than the plan.

Library-side optimization (optional, not part of the app): mpv defers
reading MKV cues only when cues are the *only* trailing element. Files with
Tags/Attachments/Chapters at the end cost one extra Range round trip each
at open. On this LAN that is ~20 ms per element, so it is probably noise,
but if measurements show open time dominated by round trips, a remux pass
(`mkvmerge --no-attachments --no-global-tags`, or cues-to-front) is the
fix and needs no app change.

### 2.4 Unplayable programs (4K AV1 today)

Loom schedules them like anything else. Warp runs `PlaybackGate` against
the program's stream summary before `loadfile`; if blocked, it shows a
"This Apple TV can't play this program" card with the program info and
the channel's next program, stays tuned, and resumes normally at the next
block boundary (or when you flip away). The gate is a live capability
query, so the new Apple TV lifts it with no code change. The two Dolby
Vision titles are AV1 4K and fall under the same gate; if/when they become
playable, mpv/libplacebo renders their HDR10 base layer, which is fine.

## 3. Loom: channels and schedule

Loom owns the lineup and schedule. I agree with putting it there: it has
the catalog, the probe data, a durable store, a wall-clock job precedent
(`runFeaturedPicks`) and a post-scan hook (`FinishScan`), and it keeps the
client dumb, which is what makes flips cheap.

### 3.1 Channels (POC lineup)

Generated from metadata so nothing is hand-curated, but deliberately small
for the proof of concept: about 10 channels mixing TV, movies, SDR and HDR.
Rules (constants in code, not config):

1. The 4 shows with the most available episodes, one channel each
   (`show:<item_id>`). Episodes air in season/episode order, looping.
2. The 4 movie genres with the most available movies, one channel each
   (`genre:<genre_id>`). Random order without repeats while an item is
   still in the channel's stored window.
3. `hdr`: every playable item whose video stream is `hdr` or
   `dolby_vision` (movies and episodes), shuffled the same way.
4. `mix`: every playable item, shuffled the same way.

Channels are rows in a `channels` table with a stable `number` assigned
when a key first appears (numbers are never reused or reshuffled), so the
lineup can grow later without renumbering. Approved: "content later".

### 3.2 Schedule

- Table `channel_programs(id, channel_id, item_id, starts_at, ends_at)`.
  Programs are back-to-back at their real `duration_ms`, no rounding
  (approved: exact back to back).
- Horizon 24 hours. A generator goroutine (third worker in
  `daemonrun.Run`, same shape as `runFeaturedPicks`) runs at startup,
  every 15 minutes, and after every scan: it reconciles the channel list,
  prunes programs that ended more than 6 hours ago, and appends programs
  to each channel until its last `ends_at >= now + 24h`. A channel whose
  schedule has a gap (Loom was down) restarts from `now`.
- 4K AV1 and any other playable item is scheduled; the client gates.
  1080p AV1 plays on this box (approved).
- Items that go unavailable are left in place; the client treats a media
  404 like the unplayable card.
- Schema 14 -> 15 with a migration test.

### 3.3 API contract

One endpoint. Both sides build against exactly this.

```
GET /api/v1/channels?hours=24        (hours: 1..48, default 24)

{
  "now": "2026-08-29T20:15:03Z",          // server clock, RFC 3339 UTC
  "items": [
    {
      "id": 3,
      "number": 3,                          // stable channel number, 1-based
      "key": "show:2316",                   // show:<item_id> | genre:<genre_id> | hdr | mix
      "name": "The Office",                 // show title, genre name, "HDR", "Mix"
      "kind": "show",                       // show | genre | hdr | mix
      "programs": [                         // ascending starts_at, covering now-1h .. now+hours
        {
          "id": 9812,
          "starts_at": "2026-08-29T19:58:10Z",
          "ends_at":   "2026-08-29T20:20:40Z",
          "item": { ...the Item shape /items returns (no credits)... },
          "video": { "codec": "hevc", "width": 1920, "height": 1080,
                     "resolution": "1080p", "dynamic_range": "sdr" },
          "stream_url": "/api/v1/media/812?tag=<tag>"
        }
      ]
    }
  ]
}
```

- `item` is the same JSON the `/items` listing produces for that item
  (title, kind, year, season/episode numbers, `series_title`,
  `season_title`, overview, artwork id/tag pairs, `duration_ms`, ...),
  without `credits` and without `progress`.
- `video` is the first video stream of the file; omitted if the file has
  no probed video stream.
- `stream_url` is computed exactly like `/items/{id}/playback` (stat at
  request time) so the media endpoint always accepts it; omitted when the
  file is missing on disk.
- Empty lists are `[]`, not null, as elsewhere the client tolerates null.
- Warp never reports progress or watched state.

## 4. Warp: the app

### 4.1 Structure

Standalone repo, same toolchain as Takeup:

- `project.yml`: one tvOS app target `Warp` (bundle `xyz.five82.warp`,
  team G539654RSK, family 3, scheme with `metalAPIValidation: false`), a
  `WarpTVDriver` UI-test target (the XCUIRemote driver), and a `WarpTests`
  tvOS unit-test bundle (Swift Testing; Takeup has no tvOS test bundle, so
  this is new).
- `Vendor/MPVKit/` copied from Takeup (Package.swift + dummy shims);
  `Frameworks/` gitignored and copied from Takeup's already-built
  xcframeworks so we skip the 30-60 minute build. `patches/` and
  `scripts/build-libmpv.sh` come along for rebuilds.
- Code copied (not shared by package or symlink) from `Shared/`:
  `LoomClient`/`LoomModels` (trimmed to what Warp uses, plus the channels
  DTOs), `LoomDiscovery`, `AppEnvironment`, `PlaybackGate`,
  `MPVPlayerController`/`MetalLayer`/`PlayerModel` (extended for channel
  use), `DisplayAwake`, `Format`, and the theme layer (`Palette`,
  `Typography` tvOS branch, `Components`, `Backgrounds`, `Woven`,
  `CachedImage`, `BiasCut`). `scripts/tv-driver.sh` and the driver test.
  Copying matches the "no compatibility shims, coordinated changes" rule
  in both repos; a shared package can come later if the two apps stop
  diverging.
- Launch arguments for headless checks: `-server`, `-channel <number>`,
  `-guide` (open the guide on launch), `-freeze` (stop the clock for
  screenshots).

### 4.2 Screens (prototype, unstyled beyond tokens)

1. **Onboarding/Settings**: Bonjour list + manual address, commit after
   `health()` succeeds. Straight from Takeup.
2. **Tuner** (the app's home): full-screen video. On launch it tunes the
   last channel (UserDefaults) immediately. No transport controls.
3. **Channel banner**: appears on every flip and on Left/Right for a few
   seconds: channel number + name, program title and episode line,
   progress bar of the current block, "Next: ..." line, resolution/HDR
   badge, and a CC badge lit when captions are on. Auto-hides. Play/Pause
   toggles captions (one global CC on/off, persisted; mpv picks the English
   track per program, so it survives flips) and shows the banner so the CC
   badge confirms the change. A "player panel" mode - the banner held open
   with a focused captions pill - was tried and dropped: it cost three
   presses for one bit, and the Menu press that closed it was one press
   away from leaving the app. There is no other transport.
4. **Guide**: overlay over the still-playing video. Rows = channels
   (current channel focused), columns = time from now, cells = programs.
   Select tunes, Menu closes. Horizontal scroll through the 24 h window.
5. **Unplayable card** (section 2.4).
6. **Error state**: one Loom-unreachable screen with retry, like Takeup.

### 4.3 Remote grammar

- Up/Down (swipe or click on the ring): channel +/-, wrapping.
- Select: toggle the guide.
  Left/Right: show the banner (later: peek at adjacent channels' banners
  without tuning).
- Play/Pause: toggle captions; the banner shows the result.
- Menu: close the guide if open, otherwise leave the app (standard
  tvOS). Menu never opens anything: a "Menu opens the guide, Menu again
  exits" scheme was considered and rejected, since the second press would
  also have to mean "close the guide", so every peek at the guide would
  eject you from the app. Long-press Menu already goes Home.
- No number entry (Siri remote has no keypad).

### 4.4 Clock and drift

Offset into a program = `serverNow - starts_at`, with `serverNow` derived
from the `now` in the last lineup fetch plus local monotonic elapsed time.
The lineup is refreshed every 10 minutes and on foreground; a refresh
never interrupts playback. When the current block ends, the already-queued
next program takes over in mpv; if the schedule refresh disagrees (a
regenerated tail), the client re-tunes at the boundary.

## 5. Testing

- **Loom**: generator tests with a fake clock (horizon filled, pruning,
  episode order, no-repeat rotation, new items enter at the tail,
  restart-stable numbering), endpoint tests in the `httpapi_test.go`
  style, migration test. `./check-ci.sh`.
- **Warp unit tests** (Swift Testing, tvOS bundle): lineup decoding,
  clock offset math, channel wrap, "what's on at t" lookup, gate, banner
  labels.
- **Simulator**: UI/guide/focus via `tv-driver.sh` and screenshots, with
  H.264/HEVC titles only (AV1 crashes the simulator's Metal driver).
- **Physical Apple TV**: the things that only the box can answer, and
  they are the whole point: switch latency (instrumented and logged
  per flip), no HDMI resync across HDR<->SDR flips, SDR looks right in
  the PQ container, HDR unchanged versus Takeup, memory over a long surf.

## 6. Phases

0. **Spike (before any Loom work).** Warp skeleton with only the player:
   two hardcoded Loom URLs (one HDR10, one SDR), Up/Down toggles between
   them at a fixed offset. Pinned PQ output, `force-window`, display
   criteria pin, timing log. Runs on the box. This settles the two
   biggest risks (mode switching and flip latency) with a day of work.
1. **Loom channels**: schema, generator, endpoint, tests. Deploy to test
   Loom.
2. **Warp prototype**: onboarding, tuner, banner, guide, unplayable card,
   driver script, unit tests.
3. **Only if phase 0 says so**: second warm mpv instance for the adjacent
   channel (standby on `ao=null`, own `CAMetalLayer`, skipped for AV1
   where software decode makes it too expensive); library remux for cue
   placement. A belt-and-braces alternative if pinning ever proves flaky
   on some hardware: keep each channel homogeneous in dynamic range so a
   mode switch can only happen on a channel change, never mid-channel.
4. Later, out of scope now: visual design pass, interstitials/half-hour
   alignment, Top Shelf, channel logos, "peek" at adjacent channels.

## 7. Decisions (approved 2026-08-29)

1. In-app display pin at HDR10/60 Hz; no 24p matching inside Warp.
2. POC lineup of ~10 channels mixing TV, movies, SDR and HDR (section
   3.1); real content design later.
3. Exact back-to-back programs.
4. SDR white at 203 nits, adjust by eye on the box. (Adjusted the same
   day: 203 was too bright on the house TV, now 100.)
5. Standalone repo; shared code is copied from Takeup, not packaged.
6. 1080p AV1 is scheduled and plays (software decode is smooth on this
   box); only the 4K AV1 gate applies.
