#!/bin/sh
# Build USB network gadget modules (CDC NCM + ECM) for the XMX kernel 5.10.198
# and rename the ALSA side of f_midi ("f_midi"/"MIDI Gadget" -> "XMX Midi").
# Needs a configured tree from build-midi.sh and the patches of build-xmx-names.sh.
# Output: /k/out-net/{u_ether,usb_f_ncm,usb_f_ecm,usb_f_midi}.ko
set -e
cd /k/src
S=scripts/config
$S --enable USB_CONFIGFS_NCM --enable USB_CONFIGFS_ECM
# The XMX kernel has NO wireless extensions (no wireless_send_event in kallsyms).
# rk3308_linux_defconfig pulls WIRELESS_EXT in via WLAN drivers, which adds two
# pointers to struct net_device -> dev_addr at 744 instead of 728 -> oops in
# gether_register_netdev (22.11.2026). Check: stock r8152.ko uses [net,#728].
$S --disable WLAN --disable CFG80211_WEXT --disable WIRELESS_EXT --disable WEXT_CORE --disable WEXT_PROC --disable WEXT_SPY --disable WEXT_PRIV
make CC=gcc -s olddefconfig
grep -E "^CONFIG_(USB_U_ETHER|USB_F_NCM|USB_F_ECM|USB_CONFIGFS_NCM|USB_CONFIGFS_ECM|WIRELESS_EXT)=" .config
! grep -q "^CONFIG_WIRELESS_EXT=y" .config || { echo "WIRELESS_EXT still on"; exit 1; }

F=drivers/usb/gadget/function
# ALSA card/seq/rawmidi name of f_midi (what Trax/JUCE and Synthor see)
sed -i -e 's/f_midi_shortname\[\] = "f_midi";/f_midi_shortname[] = "XMX Midi"; \/* XMX *\//' \
       -e 's/f_midi_longname\[\] = "MIDI Gadget";/f_midi_longname[] = "XMX Midi"; \/* XMX *\//' $F/f_midi.c
grep -n "f_midi_shortname\[\]\|f_midi_longname\[\]" $F/f_midi.c

make CC=gcc -s -j$(nproc) modules_prepare
make CC=gcc -s -j$(nproc) KBUILD_MODPOST_WARN=1 M=drivers/usb/gadget modules 2>&1 | grep -vE "modpost|undefined!|Module.symvers|dependencies" | tail -5
mkdir -p /k/out-net
cp $F/u_ether.ko $F/usb_f_ncm.ko $F/usb_f_ecm.ko $F/usb_f_midi.ko /k/out-net/
cd /k/out-net
for m in *.ko; do echo "$m: $(modinfo -F vermagic $m) | depends: $(modinfo -F depends $m)"; done
objdump -d --no-show-raw-insn u_ether.ko | awk '/<gether_register_netdev>:/,/^$/' | grep -q '#728\]' && echo "dev_addr offset 728 ok" || echo "WARNING: dev_addr offset != 728"
sha256sum *.ko > SHA256SUMS
