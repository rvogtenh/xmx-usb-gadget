# Building the modules

Native arm64 build in Docker on an Apple Silicon Mac (no cross compiler).

1. Kernel source: rockchip-linux/kernel, branch `develop-5.10`, commit `955e34ae` (Linux 5.10.198).
   Unpack into a Docker volume (macOS filesystems are case-insensitive): `/k/src`.
2. `docker build -t xmx-kbuild .`
3. In the container (`docker run --rm -v xmx-k:/k -v "$PWD":/w xmx-kbuild sh /w/<script>`), in this order:
   - `build-midi.sh` — config matched to the XMX kernel, builds `usb_f_midi.ko`
   - `build-xmx-names.sh` — f_uac2 (one clock, names) and f_midi patches
   - `build-net-midiname.sh` — NCM/ECM network modules, ALSA name "XMX Midi", **disables WIRELESS_EXT**
     (the XMX kernel has none; with it `struct net_device` differs and the network module oopses)

Check: `modinfo -F vermagic *.ko` must print `5.10.198 SMP preempt mod_unload aarch64`.
Rockchip's `gcc-wrapper.py` fails in this setup, hence `make CC=gcc`.
