# Extras

## webdav.py — XMX files in the Finder

Copy `webdav.py` to `BOOT/`. `gadget.sh` starts it after the USB network is up (`DAV=1`), bound to
`10.77.0.1:8080` only (no password, reachable only over the USB cable). macOS metadata files (`._*`,
`.DS_Store`) are discarded, so they never end up in `plugins/`.

Finder → Go → Connect to Server → `http://10.77.0.1:8080/`

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
