#!/bin/sh
# Build usb_f_midi.ko (plus reference modules) for the Percussa XMX kernel 5.10.198.
set -e
cd /k/src
make CC=gcc -s rk3308_linux_defconfig
S=scripts/config
$S --set-str LOCALVERSION "" --disable LOCALVERSION_AUTO
$S --module USB_CONFIGFS --module USB_LIBCOMPOSITE
$S --enable USB_CONFIGFS_UEVENT --enable USB_CONFIGFS_F_FS --enable USB_CONFIGFS_F_UAC1 --enable USB_CONFIGFS_F_UAC2 --enable USB_CONFIGFS_F_MIDI --enable USB_CONFIGFS_F_AUDIO_SRC
$S --module USB_AUDIO --module SND_USB_AUDIO --module USB_RTL8152 --module SND_RAWMIDI
$S --disable MODVERSIONS --enable DYNAMIC_DEBUG --enable STACKPROTECTOR --enable STACKPROTECTOR_STRONG
make CC=gcc -s olddefconfig
grep -E "^CONFIG_(USB_CONFIGFS|USB_LIBCOMPOSITE|USB_F_MIDI|USB_F_UAC2|USB_U_AUDIO|PREEMPT|SND_RAWMIDI|MODVERSIONS)=" .config || true
make CC=gcc -s -j$(nproc) modules_prepare
make CC=gcc -s -j$(nproc) KBUILD_MODPOST_WARN=1 M=drivers/usb/gadget modules 2>&1 | grep -vE "^WARNING: modpost|undefined!" | tail -5
mkdir -p /k/out && cp drivers/usb/gadget/function/*.ko drivers/usb/gadget/libcomposite.ko /k/out/
modinfo /k/out/usb_f_midi.ko | grep -E "vermagic|depends"
