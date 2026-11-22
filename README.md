# xmx-usb-gadget

USB audio, USB MIDI and a USB network link between a **Percussa XMX** and a computer, over the XMX
**device port**. Stock XMX image (Linux 5.10.198), only files on the BOOT partition are added or changed.
Unofficial, not supported by Percussa or TheTechnobear.

| Function | Result |
|---|---|
| USB audio | class-compliant device "XMX Audio", 8 in / 8 out, 48 kHz, 16 bit (macOS, Linux) |
| USB MIDI | 1 port each way, "XMX Midi" (works with Synthor and TraxHost/TB plugins) |
| USB network | `ssh root@10.77.0.1`, optional WebDAV file access from the Finder |

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

`NET=0` no network · `MIDI=0` no MIDI · `WATCH=0` no link watchdog · `DAV=0` no WebDAV · `DAV_RO=1` WebDAV read-only.

## Known issues

- After the Mac wakes from a longer sleep, the link can hang. A watchdog in `gadget.sh` re-binds the gadget
  (TraxHost from v260403 reconnects MIDI by itself; older versions may not).
- Occasionally after boot the computer → XMX audio had gaps until the gadget was re-bound. Cause not found yet.
- Don't overwrite plugins or presets via WebDAV while Trax/Synthor uses them.

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
