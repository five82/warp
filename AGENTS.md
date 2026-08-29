# AGENTS.md

This file provides guidance when working with code in this repository.

## TL;DR

- Do not create git branches or commit unless explicitly instructed.
- The `.xcodeproj` is generated and gitignored. Run `xcodegen generate` after adding, removing, or renaming files, or after editing `project.yml`.
- One app target, tvOS only. There is no iOS code and no `#if os(iOS)` anywhere; keep it that way.
- Build with the Xcode beta toolchain (`DEVELOPER_DIR=/Applications/Xcode-beta.app`) - the physical Apple TV and the simulator both run the tvOS 27 beta.
- The real Loom (`http://10.100.90.20:8097`) serves `GET /api/v1/channels` and is the default for everything. `scripts/mock-loom.py` is kept only for developing against a channels-API change that is not deployed yet, and for a deterministic lineup in simulator screenshot checks (see Mock Loom).
- Debug launch arguments: `-server <address>`, `-channel <number>`, `-guide` (open the guide on launch), `-freeze` (stop the displayed clock for screenshots), `-surf <n>` (auto-flip channels every 8 s, n times, logging each - the unattended latency run on the physical box).
- Video playback works in the tvOS simulator for H.264/HEVC only. AV1 crashes the simulator's Metal driver during frame upload. The mock's HDR and Mix channels land on AV1 titles, so simulator checks must use `-channel` to pick a show channel (1-4 are H.264/HEVC).

## Project

Warp is a tvOS-only "fake linear TV" client for Loom. Loom owns a lineup of channels and a rolling 24-hour schedule; Warp plays whatever is on the chosen channel right now, from the right offset, and lets you flip channels with the remote. Nothing streams in the background; the illusion is the schedule plus mid-file seeks.

`docs/proposal.md` is the approved spec and the reason for every non-obvious decision here.

Single-developer hobby project - prefer simple, maintainable solutions over clever abstractions. Loom and its clients are developed and deployed together for one user; do not add compatibility shims, make coordinated changes instead.

Loom serves original files directly with no transcoding and no authentication over trusted-LAN HTTP. AVPlayer cannot play this library (Matroska/Opus/PGS); MPVKit is a hard requirement.

The code under `Warp/Sources/` is copied from `~/projects/takeup-ios` (`Shared/` and `TakeupTV/`), not shared by package or symlink - `docs/proposal.md` 4.1 lists what came across. Do not modify the Takeup repo from here. Warp has no subtitles, no progress reporting, no downloads, and no library browsing; those were dropped on the way over.

### The three things Warp exists to prove

1. **Everything renders into one pinned PQ/BT.2020 surface** (`MPVPlayerController`). SDR sits in the HDR container at 203-nit reference white rather than being stretched; HDR10 passes through untouched because `target-peak=auto` on a PQ target is 10,000 nits, which collapses libplacebo's tone curve to identity.
2. **The display mode is pinned once at launch and never touched again** (`DisplayModePinner`). That is what stops the 1-8 second HDMI resync on every HDR/SDR boundary, which would otherwise fire on almost every channel flip.
3. **A channel flip is one mpv command and no network round trip** (`Tuner`). The whole lineup is in memory; a flip is `loadfile <url> replace -1 start=<offset>` into a long-lived mpv core with `force-window=immediate` keeping the VO, Vulkan device, and swapchain alive.

## Layout

```
Warp/Sources/
  WarpApp.swift            @main; pins the display mode at launch and on foreground
  AppEnvironment.swift     the configured Loom server and the client built from it
  Api/                     LoomClient (health, libraries, channels), LoomModels + channel DTOs
  Data/                    LoomDiscovery (Bonjour), PlaybackGate (4K AV1), Tuner
  Player/                  MPVPlayerController, MetalLayer, PlayerModel, DisplayModePinner, DisplayAwake
  UI/                      RootView, OnboardingView, TunerView, ChannelBanner, GuideView, Format
  UI/Theme/                Palette, Typography, Components, Backgrounds, CachedImage, TVTheme
WarpTests/                 Swift Testing, pure logic only
WarpTVDriver/              the XCUIRemote driver "test" (see scripts/tv-driver.sh)
Vendor/MPVKit/             vendored MPVKit; Frameworks/ is gitignored
```

`Tuner` keeps its decisions in `TunerLogic`, a plain enum of pure functions, so the tests drive block boundaries, channel wrap, and the gate without mpv, a network, or a clock.

## Build

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app

xcodegen generate   # after file additions/removals or project.yml edits

xcodebuild -project Warp.xcodeproj -scheme Warp \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -derivedDataPath DerivedDataTV build
```

Unit tests (Swift Testing, `WarpTests/`) cover the pure logic: lineup decoding, the server clock, program lookup and offsets, channel wrap, block-boundary decisions, the playback gate, banner labels, and address normalization.

```bash
xcodebuild -project Warp.xcodeproj -scheme Warp \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -derivedDataPath DerivedDataTV test
```

Never commit `DerivedData*` output (gitignored).

`Vendor/MPVKit/Frameworks/` holds two locally built xcframeworks (a patched `Libmpv` and a rebuilt `Libavfilter`) and is gitignored. After a fresh clone, copy them from a Takeup checkout or rebuild with `scripts/build-libmpv.sh` (30-60 minutes).

## Mock Loom

The real Loom is the default and normally all you need. `scripts/mock-loom.py` (Python 3 stdlib only) reverse-proxies every request to the real Loom and synthesizes `GET /api/v1/channels` from the real catalog, exactly per `docs/proposal.md` 3.3. Keep it for exactly two situations:

1. Developing the client half of a channels-API change before it is deployed to Loom (Loom and Warp change together with no compatibility shims, so this is how the Warp side gets built first). Teach the mock the new shape, build against it, then deploy Loom.
2. A deterministic lineup for simulator screenshot checks: the mock's schedule is fixed for a given `--seed`, while the real server's moves with the clock.

The trap: the mock encodes the contract independently. When the real response shape changes, update the mock in the same change or it will silently disagree.

```bash
python3 scripts/mock-loom.py --loom http://10.100.90.20:8097 --port 8098
# then point the app at this Mac's LAN address:
#   -server http://10.100.90.134:8098
```

It builds the lineup once at startup (about 8 seconds: it fetches playback for every playable item through a thread pool) and serves it from memory, filtering each response to `[now - 1h, now + hours]`. The schedule is deterministic for a given `--seed`. Media streams pass through it with `Range` support, so the app streams video through the mock too.

The POC lineup is 10 channels: the 4 shows with the most episodes, the 4 movie genres with the most movies, `hdr`, and `mix`. Channels 1-4 are H.264/HEVC and safe in the simulator; 5-10 can land on AV1.

## Simulator

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app
UDID=$(xcrun simctl list devices | grep "Apple TV 4K (3rd generation) (" | head -1 | grep -o '[0-9A-F-]\{36\}')
xcrun simctl boot "$UDID"
```

`simctl` has no remote input and idb's HID key events are dropped (dtuhidd owns the boot's keyboard service). Use `scripts/tv-driver.sh`: it runs the `WarpTVDriver` XCUIRemote "test", which launches the app and forwards presses read from `/tmp/warp-tv-driver/cmd`. Injection goes through testmanagerd, so it needs no window focus and exercises the real focus engine.

```bash
./scripts/tv-driver.sh start -server http://10.100.90.134:8098 -channel 3
./scripts/tv-driver.sh send select        # up down left right select menu playpause
xcrun simctl io "$UDID" screenshot /tmp/check.png
./scripts/tv-driver.sh stop               # self-terminates after 30 min regardless
```

The driver owns the app's lifecycle: `start` relaunches the app, `stop` terminates it. `xcodebuild test` on the `WarpTVDriver` scheme runs only this driver, so always go through the script.

`./stop-simulator.sh` shuts down every booted simulator, which also stops whatever is playing on them.

The app's own log lines are `info` level, so `log show` needs `--info`:

```bash
xcrun simctl spawn "$UDID" log show --last 10m --info \
  --predicate 'subsystem == "xyz.five82.warp"' --style compact
```

## Physical Apple TV

"Living Room Apple TV" is an Apple TV 4K 2nd generation (A12), udid `35085BEA-A61D-54EA-A44D-EABC64DC0EDF`. It must be paired once before `devicectl` can install to it.

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app
xcodebuild -project Warp.xcodeproj -scheme Warp \
  -destination 'platform=tvOS,name=Living Room Apple TV' \
  -derivedDataPath DerivedDataTVDevice -allowProvisioningUpdates build

xcrun devicectl device install app --device 35085BEA-A61D-54EA-A44D-EABC64DC0EDF \
  DerivedDataTVDevice/Build/Products/Debug-appletvos/Warp.app

# note the '--': devicectl otherwise parses '-server' as one of its own options.
xcrun devicectl device process launch --terminate-existing --console \
  --device 35085BEA-A61D-54EA-A44D-EABC64DC0EDF -- \
  xyz.five82.warp -server http://10.100.90.20:8097 -channel 1 -surf 12
```

Use a timeout around the launch - `--console` blocks until the app exits. If the run is against the mock instead, keep `mock-loom.py` running and pass this Mac's address (`WARP_SERVER=http://10.100.90.134:8098` for `device-surf.sh`).

**The box must be awake.** A sleeping Apple TV refuses foreground app launches ("System is asleep - foreground app launch forbidden") and there is no way to wake it over the network from here (Wake-on-LAN does not); press a button on the remote first. Installs work while it sleeps; launches do not.

`scripts/device-surf.sh [flips] [start-channel]` wraps the whole build/install/launch/grep cycle for a measurement run.

The XCUIRemote driver only reaches the simulator, so `-surf <n>` is how an unattended latency run happens on the box: it flips channels every 8 seconds, n times, logging each flip. Read the measurements from the `--console` stream or from the device log:

```bash
xcrun devicectl device process launch --console --device <udid> -- xyz.five82.warp ... \
  | grep -E 'warp\.(tune|surface|display|surf)'
```

The three instrumented lines:

- `warp.tune <ms> <url>` - milliseconds from `tune` to MPV_EVENT_PLAYBACK_RESTART (the first frame). This is the press-to-picture number.
- `warp.surface colorspace=... pixelFormat=...` - logged once after the first frame. `kCGColorSpaceITUR_2100_PQ` proves the PQ negotiation took; `rgb10a2Unorm` (raw value 90) is the 10-bit surface.
- `warp.display ...` - `isDisplayCriteriaMatchingEnabled` at launch, the pin itself, and every `AVDisplayManagerModeSwitchStart`/`End` notification with a timestamp. Any mode switch during a surf run means the pin is not holding.

Baseline measured 2026-08-29 on the Living Room Apple TV (A12, mock Loom on the Mac, `device-surf.sh 12 4`): matching enabled, pinned HDR10 4K @60 Hz, exactly one modeSwitchStart/End at launch and none across 12 flips that crossed SDR -> 4K HDR HEVC -> SDR twice. `warp.tune` 449-782 ms for warm HEVC/H.264 flips (4K HDR HEVC 647-657 ms), 965 ms after the gated AV1 channels, 732 ms cold at launch; 1080p AV1 (dav1d software) 596-634 ms. Surface `kCGColorSpaceITUR_2100_PQ` / `rgb10a2Unorm` on the box.

Same day against the live Loom (`device-surf.sh 10 4`, after the channels deploy): one mode switch at launch, none across 10 flips spanning three SDR/4K-HDR crossings; `warp.tune` 212-389 ms on the show channels and 469-720 ms on 4K HDR HEVC movies, median about 400 ms.

## tvOS quirks that apply here

- **A full-screen invisible Button must use a custom ButtonStyle.** The system styles (`.plain` included) paint their white focus/press highlight over the button's label; the tuner's remote catcher label is the whole screen, so the video washes out to near-white under it. `TVInvisibleButtonStyle` returns the bare label: it draws nothing and stays focusable. Do not "simplify" it to `.plain`.
- **`UIWindow.avDisplayManager` does not exist in the tvOS simulator.** Reading it there raises `unrecognized selector` and takes the app down. `DisplayModePinner` guards with `responds(to:)`; there is no display to pin in a simulator anyway.
- **AVKit must be linked explicitly.** `avDisplayManager` is an AVKit category reached through `objc_msgSend`, so nothing in the app references an AVKit symbol and the linker drops the framework; the category then never loads and the `responds(to:)` guard silently skips the pin on the box too (observed 2026-08-29: the first device run logged "unavailable (simulator)" on real hardware). `project.yml` links `AVKit.framework` and `AVFoundation.framework` as sdk dependencies and the pinner touches `AVDisplayManager.self`; keep both.
- `CAMetalLayer.wantsExtendedDynamicRangeContent` and `edrMetadata` do not exist on tvOS. The display mode determines the wire format; the layer's `colorspace`, which mpv sets from `target-colorspace-hint`, tells CoreAnimation how to read our pixels.
- AV1 above 1080p is gated, not hidden (`PlaybackGate`, a live `VTIsHardwareDecodeSupported` query, so it lifts itself on AV1-capable hardware). A gated program shows the unplayable card and the channel resumes at the next block. 1080p AV1 plays on the A12.
- os_log `info` messages need `--info` on `log show`, on the simulator and the device both.

## What only the television can answer

These are the point of the project and none of them can be checked from a terminal:

- **HDR looks unchanged versus Takeup.** Same titles, same TV, side by side.
- **SDR looks right in the PQ container.** 203-nit diffuse white is brighter than a 100-nit calibrated SDR mode, and libplacebo decodes BT.709 with BT.1886 (gamma ~2.4), which reads slightly punchier than TVs running SDR near 2.2. If SDR channels are too bright, `hdr-reference-white=100` in `MPVPlayerController` is a one-line change; `--gamma-factor` is the knob for the gamma.
- **No HDMI resync while surfing.** Flip repeatedly across an SDR/HDR boundary (channel 4 to channel 9, say) and watch for the black drop-out, especially through the AVR. `warp.display modeSwitch*` lines corroborate what the eye sees.
- **Press-to-picture feels instant.** `warp.tune` gives the number; only the couch says whether it feels like a television.
- **Memory over a long surf.** Nothing here watches for a leak in the long-lived mpv core.
