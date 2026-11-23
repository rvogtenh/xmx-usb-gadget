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

## clockdrift.py, sinecheck.py, mac/actualrate.swift — clock and glitch measurement

Run on the XMX (copy to `/tmp`, Python 3 is on the stock image). The host plays a sine into "XMX Audio"
(`halplay`), and a reader keeps the gadget capture stream open:

```sh
arecord -q -D hw:UAC2Gadget -f S16_LE -c 8 -r 48000 -t raw -d 90 \
        --period-size=256 --buffer-size=768 /dev/null &
python3 /tmp/clockdrift.py 60     # codec vs. gadget rate, drift in ppm, matching "Capture Pitch"
```

`clockdrift.py` reads `hw_ptr` from `/proc/asound/card*/pcm0c/sub0/status`, so TraxHost/Synthor can keep the
codec. Adjust the card numbers at the top if they differ. `sinecheck.py` finds discontinuities in a recorded
sine. `mac/actualrate.swift` prints the rate CoreAudio reports for a device (`swiftc -O actualrate.swift`).
Try a pitch: `amixer -c UAC2Gadget cset numid=1 1000037` (1000000 = nominal).

## usbloop.py, mac/hallatency.swift — round-trip latency

`usbloop.py` runs on the XMX and sends the USB audio straight back (capture → playback, via libasound/ctypes,
pinned to CPU 2 with SCHED_FIFO): `python3 /tmp/usbloop.py 64 4 30` (period, periods, seconds).
`hallatency.swift` on the Mac clicks on output 1 every 0.5 s and times the click on input 1:
`swiftc -O hallatency.swift -o hallatency`, then `./hallatency "XMX Audio" 10 64` (last value = Mac buffer).
Result 23.11.2026: 192 frames (4.0 ms) with 64-frame periods, 256 (5.3 ms) with 128; i.e. 128 frames for USB
both ways plus one XMX period. 32-frame periods lose clicks (too tight for Python).
