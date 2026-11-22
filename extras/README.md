# Extras

## webdav.py — XMX files in the Finder

Off by default. Copy `webdav.py` to `BOOT/` and set `DAV=1` in `BOOT/gadget.conf`; `gadget.sh` then starts it
after the USB network is up, bound to
`10.77.0.1:8080` only (no password, reachable only over the USB cable). macOS metadata files (`._*`,
`.DS_Store`) are discarded, so they never end up in `plugins/`.

Finder → Go → Connect to Server → `http://10.77.0.1:8080/`

> **Handle with care.** WebDAV gives write access to the live BOOT partition while the XMX is running.
> - Don't change, rename or delete presets, plugins or system files (`perccmd.sh`, `gadget.sh`, the DTB, `modules/`)
>   while Synthor or Trax is running. Reboot after copying plugins.
> - Back up the card before larger changes.
> - Copying samples to an unused folder is fine.
> - If in doubt, use `DAV_RO=1` (read-only).

Settings in `gadget.conf`: `DAV=1` on, `DAV_RO=1` read-only.

## mac/xmx-automount.sh — mount automatically

Mounts the XMX as a Finder volume ("XMX.local") whenever it is connected, unmounts it when it goes away.

```bash
mkdir -p ~/bin && cp xmx-automount.sh ~/bin/
```

Create `~/Library/LaunchAgents/local.xmx-automount.plist` running `/bin/zsh ~/bin/xmx-automount.sh`
(RunAtLoad, KeepAlive), then:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.xmx-automount.plist
```

Stop: `launchctl bootout gui/$(id -u)/local.xmx-automount`

## mac/halplay.swift, halrec.swift — audio test tools

Play / record a sine straight through CoreAudio (device clock, no ffmpeg — ffmpeg's AVFoundation capture
drops buffers and fakes glitches). `swiftc -O halplay.swift -o halplay`, then
`./halplay "XMX Audio" 10 440 0.1` and `./halrec "XMX Audio" 10 out.wav`.
