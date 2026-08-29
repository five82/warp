# Warp

Warp is a tvOS-only "fake linear TV" client for [Loom](https://github.com/five82/loom).
Loom owns a lineup of channels and a rolling 24-hour schedule; Warp plays
whatever is on the chosen channel right now, from the right offset, and lets you
flip channels with the Siri Remote. Nothing streams in the background - the
illusion is Loom's schedule plus mid-file seeks.

It is a proof of concept for three things a normal media client does not do:

- every source, SDR or HDR, is rendered into one pinned PQ/BT.2020 surface, so
  the picture never changes container mid-surf;
- the Apple TV's display mode is pinned once at launch, so flipping between SDR
  and HDR programs never triggers an HDMI resync;
- the whole lineup lives in memory, so a channel change is a single mpv command
  with no network round trip.

Playback is libmpv (MPVKit) rendering into a `CAMetalLayer` through MoltenVK.
The design tokens, Loom client, Bonjour discovery, and player core are copied
from the [Takeup](https://github.com/five82/takeup-ios) Apple TV app.

`docs/proposal.md` is the approved design. `AGENTS.md` has the build, simulator,
and device workflow, plus the mock Loom server that stands in for the
`/api/v1/channels` endpoint while it is being built.
