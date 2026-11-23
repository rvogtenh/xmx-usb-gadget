# xmx-usb-gadget

USB audio, USB MIDI and a USB network link between a **Percussa XMX** and a computer, over the XMX
**device port**. Stock XMX image (Linux 5.10.198), only files on the BOOT partition are added or changed.
Unofficial, not supported by Percussa or TheTechnobear.

| Function | Result |
|---|---|
| USB audio | class-compliant device "XMX Audio", 8 in / 8 out, 48 kHz, 16 bit (macOS, Linux) |
| USB MIDI | 1 port each way, "XMX Midi" (works with Synthor and TraxHost/TB plugins) |
| USB network | `ssh root@10.77.0.1`; optional Finder access via WebDAV (`extras/`) |

What is **not** there yet: the USB audio channels are not routed into Synthor or Trax. On the XMX they appear
as a separate ALSA card (`UAC2Gadget`) that no app uses so far.

## Why it did not work before

The OTG port of the RK3308 USB PHY never sees VBUS on the XMX, so the PHY driver suspends the port about a
second after the computer has enumerated it. One device-tree property fixes this:
`rockchip,vbus-always-on;` in the `otg-port` node (`patches/0001-…`). The stock kernel also lacks the MIDI
gadget function, so `usb_f_midi.ko` is built from the matching Rockchip kernel source (GPL), together with
`usb_f_ncm.ko`/`u_ether.ko` for the network. No Percussa software was reverse engineered.

## Install (about 5 minutes)

**Back up your SD card (or at least the BOOT partition) first.** Then copy to the card (`/media/BOOT` on the XMX):

1. `prebuilt/rk3308-roc-cc.dtb` → `BOOT/rk3308-roc-cc.dtb` (rename the original to `rk3308-roc-cc.dtb.orig` first)
2. `prebuilt/*.ko` → `BOOT/modules/` (create the folder)
3. `boot/gadget.sh`, `boot/gadget.conf`, `boot/dnsmasq-usb.conf` → `BOOT/`
4. Start it at boot: add this line **before** the app starts, in `BOOT/perccmd.sh` (PercCmd/Trax installed)
   or `BOOT/synthor.sh` (stock):
   ```sh
   [ -f /media/BOOT/gadget.sh ] && ( sh /media/BOOT/gadget.sh >/dev/null 2>&1 & )
   ```
5. Reboot and connect the XMX device port to the computer. Log: `BOOT/diag/gadget.txt`.

Note: a TB Apps update may replace `perccmd.sh` — add the line again afterwards.

**Undo:** put `rk3308-roc-cc.dtb.orig` back and remove the line from step 4.

## Settings (`BOOT/gadget.conf`)

`NET=0` no network · `MIDI=0` no MIDI · `WATCH=0` no link watchdog ·
`IRQ_CPU=0` keep the USB interrupt on CPU 0 (default 1, see below).
Optional WebDAV server from `extras/` (off by default, handle with care — see `extras/README.md`): `DAV=1` on · `DAV_RO=1` read-only.

## Clean audio: USB interrupt on CPU 1

The XMX kernel runs with `isolcpus=1,2,3`, so CPU 0 carries every interrupt and every unpinned thread. With the
USB (dwc2) interrupt there, computer → XMX audio lost 0.5–1 % of the packets (clicks). `gadget.sh` therefore moves
it to CPU 1 at boot; measured afterwards: no discontinuities, only crystal drift (about 25–37 ppm).
Tools: `extras/clockdrift.py` (codec vs. gadget rate), `extras/sinecheck.py` (finds discontinuities in a sine).

Clock drift: a Linux host follows the feedback endpoint ("Capture Pitch" control on the XMX), so the host can be
locked to the codec without resampling. macOS ignores the feedback, so with a Mac the XMX side has to absorb the drift.
Small buffers are fine once the IRQ is off CPU 0: reading `UAC2Gadget` with 128-frame periods (2.7 ms) was clean.
(Before the fix, small periods glitched heavily; that was the same CPU 0 overload, not a gadget limit.)

Round-trip latency computer → XMX → computer (Mac, XMX looping the audio back with `extras/usbloop.py`, measured
with `extras/mac/hallatency.swift` on the device timeline): **128 frames (2.7 ms) for USB both ways, plus the loop
period on the XMX** — 4.0 ms with 64-frame periods, 5.3 ms with 128. The computer's own I/O buffer and CoreAudio's
safety offsets (here 50 out + 74 in frames) come on top.

## Known issues

- After the Mac wakes from a longer sleep, the link can hang. A watchdog in `gadget.sh` re-binds the gadget
  (TraxHost from v260403 reconnects MIDI by itself; older versions may not).
- Occasionally after boot the computer → XMX audio had gaps until the gadget was re-bound. Cause not found yet.

## Contents

```
patches/   device tree, f_uac2 (one clock -> one device on macOS, names), f_midi (names), kconfig.fragment
boot/      gadget.sh (configfs gadget + watchdog), gadget.conf, dnsmasq-usb.conf
prebuilt/  rk3308-roc-cc.dtb, usb_f_uac2.ko, usb_f_midi.ko, u_ether.ko, usb_f_ncm.ko, SHA256SUMS
build/     Docker build of the modules on an Apple Silicon Mac (see build/README.md)
extras/    webdav.py (Finder access), macOS auto-mount helper, CoreAudio test tools
```

## License

Kernel patches and modules: GPL-2.0 (Linux). Scripts: GPL-2.0 as well.
Developed with AI assistance (Claude Code); every result was tested on a real XMX.
