# Changelog

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html). A release
tag must match a section heading exactly (for example `v1.0.0`): CI reads
the matching section and uses it as the GitHub Release notes, and refuses
to release without one.

## [v0.0.3] - 2026-09-09

### Changed

- The manifest's `kind` is now `core`, not `emulator`. A core that emulates
  nothing -- Doom -- showed that the old word named a subset rather than the
  set, so the spec took the general term and the SDK and the spec now agree.
  The previous release publishes the old value and no longer validates.

## [v0.0.2] - 2026-09-08

### Added

- Published under the [GWRG distribution
  spec](https://github.com/slash-proc/gwrg-dist-spec): a `manifest.json`
  describing this core and the systems it provides, an offline bundle, and a
  GitHub Pages mirror of `dist/` that a web installer can read without a human
  in the loop.
- `symbols[]` publishes the linked ELF so a crash address from a device can be
  resolved back to a function. It is named by the manifest and mirrored, but is
  not part of the install set and never reaches the card.
- `gwrg.json`, the hand-written half of the manifest: the short console name,
  whether compressed ROMs work, and any BIOS this core needs. Everything else —
  the systems, their folders, extensions and browse mode, the firmware ABI,
  sizes and hashes — is derived from the packed binary at release time.
- The optional Game Boy Advance BIOS is declared with its hash and exact
  size; without it the core falls back to a bundled free replacement.
- `gba.xip` is declared as a second artifact. The core aborts without it,
  so it now travels through the generic sidecar path (`RO_BIN`) rather
  than a gba-only flag in the release script.

### Changed

- `scripts/make_manifest.py`, `build_dist.py`, `make_bundle.py` and
  `stage_release.py` are now the shared copies, byte-identical across every
  project. A script that has to be edited on the way in is a script that drifts.
- The launcher tab is now "Game Boy Advance" rather than "Nintendo Gameboy
  Advance". Nobody says the manufacturer, and the name is what a user reads
  on the device.


## [v0.0.1]

Initial core release: gpSP as a standalone dynamic core.
