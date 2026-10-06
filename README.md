# AWDLess — Steady Call

A macOS menu bar app that keeps **AWDL** (Apple Wireless Direct Link, the peer-to-peer Wi-Fi behind
AirDrop, Handoff, Continuity Camera, Universal Control and Sidecar) switched off **exactly while a camera is
in use**, and switches it back on afterwards.

## Why

AWDL makes the Mac's Wi-Fi radio leave its channel on a shared schedule. During a video call that shows up as
freezes of one to three seconds every 10–20 s, on the Mac in the call *and on every Mac nearby* (they hop in sync).
Measured on a FRITZ!Box 6660 / Vodafone cable line, same call, only AWDL toggled:

| | Router pings (0.5 s) |
|---|---|
| Call, AWDL on, 2.4 min | 3 lost, max 1822 ms, 13 samples over 500 ms |
| Call, AWDL off, 3.6 min | 0 lost, max 102 ms, 0 over 500 ms |

The ISP, the cable modem and the router were ruled out first. Full write-up: see the investigation notes.

## What it does

- **Triggers:** camera in use (default), microphone in use, chosen apps running, or a manual override (off / on, timed).
- **Wi-Fi only:** on Ethernet AWDL is harmless, so nothing happens.
- **Grace period:** AWDL stays off a configurable number of seconds after the camera stops, so brief toggles do not flap AirDrop.
- **Link health:** pings the router once a second while AWDL is off (or always), shows a 60 s sparkline and stall count,
  and badges the menu bar icon when the link stalls. This is how you see the fix working.
- **Notifications** on state changes, **launch at login**.
- **Safety:** the root helper restores AWDL whenever the app quits, crashes or disconnects.

## How it works

Two parts, like Apple's own privileged-helper pattern:

1. **AWDLess.app** (SwiftUI, menu bar). Detects camera use via CoreMediaIO's `DeviceIsRunningSomewhere` (no camera
   permission needed), microphone use via CoreAudio, apps via NSWorkspace. Decides the desired state and tells the helper.
2. **AWDLessHelper** (LaunchDaemon, root, registered with `SMAppService`). Flips `IFF_UP` on `awdl0` with an ioctl and
   watches the kernel routing socket: when macOS brings `awdl0` back up by itself (it does, within seconds), the helper
   takes it down again immediately. No polling. It accepts XPC only from AWDLess signed by the same Team ID.

The helper mechanism is inspired by [AWDLControl](https://github.com/james-howard/AWDLControl) by James Howard
(which targets games). Thank you.

## Build

Requires Xcode 16+, macOS 14+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

    xcodegen generate
    open AWDLess.xcodeproj        # or: scripts/build.sh

Set `DEVELOPMENT_TEAM` in `project.yml` to your Team ID. For distribution outside your own Macs you need a
"Developer ID Application" certificate and notarization (`scripts/notarize.sh`). This app cannot be sandboxed,
so it cannot go on the Mac App Store.

## First run

1. Launch AWDLess. The menu bar icon shows a warning triangle until the helper is installed.
2. Click **Install Helper…**. macOS asks you to allow it under System Settings › General › Login Items & Extensions.
3. Start a video call. The icon switches to the slashed antenna; the menu shows which camera triggered it and the live
   link-health sparkline.

## License

MIT. See LICENSE.
