# AGENTS.md

## Rules

- Do not create branches or commit unless explicitly instructed.
- Warp is tvOS-only. Do not add iOS code or `#if os(iOS)` branches.
- Prefer simple, maintainable solutions for this single-developer hobby project.
- Loom and Warp are deployed together for one user. Make coordinated API changes; do not add compatibility shims.
- `docs/proposal.md` is the approved specification and explains non-obvious design decisions.
- Do not modify `~/projects/takeup-ios`; Warp contains its own copies of the relevant code.

## Architecture invariants

Warp depends on MPVKit because the library contains formats AVPlayer cannot play. Preserve these properties:

1. `MPVPlayerController` renders everything into one PQ/BT.2020 surface. SDR uses 100-nit reference white and per-file gamma 2.2 retagging; HDR10 passes through unchanged.
2. `DisplayModePinner` pins HDR10 4K 60 Hz at launch and on foreground. Do not switch display modes at SDR/HDR or frame-rate boundaries.
3. `Tuner` flips channels without a network round trip: the lineup stays in memory and a long-lived mpv core receives one `loadfile` command.

Captions are one persisted global switch (`sid=auto/no`, preferred language English), not a per-program track picker. AV1 above 1080p is gated based on live hardware decode support, not hidden from the lineup.

The app icon and top-shelf artwork are generated. Edit `scripts/make-icon.swift`, not generated PNGs.

## Build and test

Use the selected Xcode toolchain (Xcode 27); both the simulator and physical Apple TV run tvOS 27.

```bash
xcodebuild -project Warp.xcodeproj -scheme Warp \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -derivedDataPath DerivedDataTV build

xcodebuild -project Warp.xcodeproj -scheme Warp \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -derivedDataPath DerivedDataTV test
```

The Xcode project is generated and gitignored. Run `xcodegen generate` after adding, removing, or renaming files, or after changing `project.yml`.

`Vendor/MPVKit/Frameworks/` is gitignored. After a fresh clone, copy the patched `Libmpv` and rebuilt `Libavfilter` xcframeworks from a Takeup checkout or run `scripts/build-libmpv.sh`.

## Loom

Use the configured Loom server unless a deterministic simulator lineup or an undeployed channels-API change requires `scripts/mock-loom.py`. The mock independently encodes the channels contract; update it whenever that contract changes.

## Simulator and device validation

- The simulator can play H.264/HEVC, but AV1 crashes its Metal driver during frame upload. With the mock lineup, use a show channel (1–4) for simulator checks.
- Simulator remote input must go through `scripts/tv-driver.sh`; do not invoke the `WarpTVDriver` scheme directly.
- App logs use `info` level, so `log show` requires `--info`.
- Use `scripts/device-surf.sh` for physical-device latency and display-mode runs. The Apple TV must be awake before launch.
- A successful build or simulator run cannot validate HDR appearance, SDR appearance in the PQ container, HDMI resync behavior, perceived tuning latency, or long-session memory behavior. Do not claim those checks passed without testing on the television.
