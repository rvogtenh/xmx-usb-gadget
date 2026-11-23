#!/bin/sh
# XMX: create a USB audio gadget on the device port (dwc2 ff400000.usb) via configfs.
# Copied to /media/BOOT/gadget.sh, started in the background from perccmd.sh.
# Mode from /media/BOOT/gadget.mode: "uac2" (default), "uac1" or "off".
# Optional overrides in /media/BOOT/gadget.conf (shell syntax), e.g.
#   SRATE=48000 CHMASK=3 SSIZE=2 SYNC=async
#   EXTRA="c_mute_present=0 c_volume_present=0"   (any attribute of the function)
# Log: /media/BOOT/diag/gadget.txt (UDC state is sampled for 90 s).

LOG=/media/BOOT/diag/gadget.txt
mkdir -p /media/BOOT/diag
exec > "$LOG" 2>&1
echo "### $(date) gadget.sh"

MODE=uac2
[ -f /media/BOOT/gadget.mode ] && MODE=$(tr -d ' \r\n' < /media/BOOT/gadget.mode)
SRATE=48000
CHMASK=3
SSIZE=2
SYNC=
MIDI=1          # 1 = add USB MIDI (needs /media/BOOT/modules/usb_f_midi.ko)
NET=ncm         # ncm | ecm | 0 = USB network (needs u_ether.ko + usb_f_$NET.ko in modules/)
NET_IP=10.77.0.1
WATCH=1         # 1 = re-bind the gadget when the link hangs (e.g. after the Mac wakes from sleep)
DAV=0           # 1 = WebDAV file server on the USB link (Finder: http://10.77.0.1:8080/), needs NET + webdav.py
DAV_RO=0        # 1 = WebDAV read-only
IRQ_CPU=1       # CPU for the dwc2 USB interrupt (0 = leave on CPU 0). See below.
[ -f /media/BOOT/gadget.conf ] && . /media/BOOT/gadget.conf
echo "mode=$MODE srate=$SRATE chmask=$CHMASK ssize=$SSIZE sync=$SYNC midi=$MIDI net=$NET"
# Debug: KEEP_OOPS=1 in gadget.conf -> a kernel oops no longer reboots the XMX
# (stock: panic_on_oops=1, panic=1), so the oops can be read via ssh/dmesg.
# Each oops is also copied to /media/BOOT/diag/oops.txt (synced).
if [ "$KEEP_OOPS" = 1 ]; then
	echo 0 > /proc/sys/kernel/panic_on_oops && echo "panic_on_oops=0 (debug)"
	# Poll the cheap taint flag (bit 7 = 128, set by an oops/die) instead of
	# running dmesg every 2 s: reading the whole kernel log every 2 s made the
	# USB audio OUT stream (Mac -> XMX) lose 2 iso packets (96 samples) each
	# time (found 22.11.2026).
	( while true; do
		t=$(cat /proc/sys/kernel/tainted)
		if [ $((t & 128)) -ne 0 ]; then
			dmesg > /media/BOOT/diag/oops.txt; sync; break
		fi
		sleep 2
	done ) &
fi
[ "$MODE" = off ] && { echo "off"; exit 0; }

UDC=ff400000.usb
CFS=/sys/kernel/config
G=$CFS/usb_gadget/xmx

sleep 5   # let the app start first

modprobe libcomposite && echo "libcomposite ok"
# Self-built usb_f_uac2.ko with XMX names ("XMX Playback"/"XMX Capture" on the
# Mac) is preferred when present; otherwise the stock module is used.
OWN=/media/BOOT/modules/usb_f_$MODE.ko
if [ -f $OWN ]; then
	modprobe u_audio
	insmod $OWN && echo "usb_f_$MODE ok (own module $OWN)"
else
	modprobe usb_f_$MODE && echo "usb_f_$MODE ok (stock)"
fi
grep -q " $CFS configfs" /proc/mounts || mount -t configfs none $CFS
echo "configfs: $(grep configfs /proc/mounts)"

if [ -d $G ]; then echo "gadget exists, leaving it"; else
	mkdir -p $G
	cd $G || exit 1
	echo 0x1d6b > idVendor          # Linux Foundation
	echo 0x0101 > idProduct         # Audio Gadget
	echo 0x0100 > bcdDevice
	echo 0x0200 > bcdUSB
	# Composite device with IADs. Without this macOS does not configure the
	# device once a network function is added (22.11.2026).
	echo 0xEF > bDeviceClass
	echo 0x02 > bDeviceSubClass
	echo 0x01 > bDeviceProtocol
	mkdir -p strings/0x409
	echo "Percussa"  > strings/0x409/manufacturer
	echo "XMX Audio" > strings/0x409/product
	echo "xmx0001"   > strings/0x409/serialnumber

	mkdir -p configs/c.1/strings/0x409
	echo "$MODE" > configs/c.1/strings/0x409/configuration
	echo 0xc0 > configs/c.1/bmAttributes   # self-powered (Eurorack)
	echo 2 > configs/c.1/MaxPower

	F=functions/$MODE.usb0
	mkdir -p $F
	echo "attributes in $F:"; ls $F
	for p in c p; do
		[ -f $F/${p}_chmask ] && echo $CHMASK > $F/${p}_chmask
		[ -f $F/${p}_srate ]  && echo $SRATE  > $F/${p}_srate
		[ -f $F/${p}_ssize ]  && echo $SSIZE  > $F/${p}_ssize
	done
	[ -n "$SYNC" ] && [ -f $F/c_sync ] && echo $SYNC > $F/c_sync
	# EXTRA="name=value ..." from gadget.conf, written only if the attribute exists
	for kv in $EXTRA; do
		k=${kv%%=*}; v=${kv#*=}
		if [ -f $F/$k ]; then echo "$v" > $F/$k && echo "set $k=$v"; else echo "no attribute $k"; fi
	done
	for a in $F/*; do echo "  $(basename $a) = $(cat $a 2>/dev/null)"; done

	ln -s $F configs/c.1/

	# USB MIDI: usb_f_midi is not part of the stock XMX kernel. Self-built module
	# (Rockchip 5.10.198, see README) lives on the BOOT partition.
	MK=/media/BOOT/modules/usb_f_midi.ko
	if [ "$MIDI" = 1 ] && [ -f $MK ]; then
		modprobe snd-rawmidi
		lsmod | grep -q '^usb_f_midi' || insmod $MK
		mkdir -p functions/midi.usb0
		echo XMX > functions/midi.usb0/id
		echo 1 > functions/midi.usb0/in_ports
		echo 1 > functions/midi.usb0/out_ports
		ln -s functions/midi.usb0 configs/c.1/ && echo "midi added"
		modprobe snd-seq-midi
	else
		echo "midi off (MIDI=$MIDI, module $( [ -f $MK ] && echo found || echo missing))"
	fi

	# USB network (CDC NCM/ECM). Modules are self-built (XMX kernel has no
	# usb_f_ncm/ecm); fixed MAC addresses keep the Mac interface stable.
	NK=/media/BOOT/modules/usb_f_$NET.ko
	if [ "$NET" != 0 ] && [ -f /media/BOOT/modules/u_ether.ko ] && [ -f $NK ]; then
		lsmod | grep -q '^u_ether' || insmod /media/BOOT/modules/u_ether.ko
		lsmod | grep -q "^usb_f_$NET" || insmod $NK
		mkdir -p functions/$NET.usb0
		echo 02:58:4d:58:00:01 > functions/$NET.usb0/dev_addr
		echo 02:58:4d:58:00:02 > functions/$NET.usb0/host_addr
		ln -s functions/$NET.usb0 configs/c.1/ && echo "net $NET added"
	else
		echo "net off (NET=$NET)"
		NET=0
	fi

	echo $UDC > UDC && echo "bound to $UDC"

	# USB interrupt off CPU 0 (23.11.2026). The XMX kernel runs with isolcpus=1,2,3,
	# so CPU 0 carries every IRQ and every unpinned thread (most TraxHost threads too).
	# With the dwc2 IRQ there, host -> XMX audio lost 0.5-1 % of the packets (clicks);
	# on CPU 1 the stream is clean (measured: 0 discontinuities, -37 ppm = real drift).
	if [ "$IRQ_CPU" != 0 ]; then
		IRQ=$(grep -m1 "ff400000.usb" /proc/interrupts | cut -d: -f1 | tr -d ' ')
		if [ -n "$IRQ" ] && printf '%x' $((1 << IRQ_CPU)) > /proc/irq/$IRQ/smp_affinity; then
			echo "usb irq $IRQ -> cpu $(cat /proc/irq/$IRQ/smp_affinity_list)"
		else
			echo "usb irq: could not move (irq=$IRQ)"
		fi
	fi

	if [ "$NET" != 0 ]; then
		IF=$(cat functions/$NET.usb0/ifname)
		ip link set $IF up
		ip addr add $NET_IP/24 dev $IF
		echo "$IF: $(ip -4 addr show $IF | grep inet)"
		# DHCP for the computer only on the USB link: no gateway, no DNS
		DC=/media/BOOT/dnsmasq-usb.conf
		if [ -f $DC ]; then
			dnsmasq -C $DC && echo "dnsmasq started ($DC)"
		else
			echo "no $DC, no DHCP (set the Mac address by hand)"
		fi
		# WebDAV (webdav.py, Python stdlib only), bound to the USB link only, nice 19
		if [ "$DAV" = 1 ] && [ -f /media/BOOT/webdav.py ]; then
			RO=; [ "$DAV_RO" = 1 ] && RO=--readonly
			( nice -n 19 python3 /media/BOOT/webdav.py --root /media/BOOT --bind $NET_IP --port 8080 $RO \
				> /media/BOOT/diag/webdav.txt 2>&1 & )
			echo "webdav started on http://$NET_IP:8080/ $RO"
		fi
	fi
fi

# Link watchdog (22.11.2026). After the Mac wakes from sleep, dwc2 reports a
# disconnect and leaves EP0 disarmed: the host keeps sending SOFs but gets no
# answers, audio/MIDI/net are dead until the gadget is re-bound.
# Every 3 s: read the UDC state (cheap sysfs read). Only if it is not
# "configured"/"suspended", look at the SOF frame number in DSTS (0xff400808,
# bits 21:8) twice: if it moves, a live host is on the bus. Two hits in a row
# -> re-bind. No cable or sleeping Mac -> no SOFs -> nothing happens.
if [ "$WATCH" = 1 ] && [ -d $G ] && command -v devmem >/dev/null; then
	( WL=/media/BOOT/diag/watch.txt
	  echo "### $(cut -d' ' -f1 /proc/uptime)s watchdog started" >> $WL
	  hits=0
	  while true; do
		sleep 3
		st=$(cat /sys/class/udc/$UDC/state)
		case "$st" in configured|suspended) hits=0; continue ;; esac
		f1=$(( ($(devmem 0xff400808 32) >> 8) & 0x3fff )); usleep 20000
		f2=$(( ($(devmem 0xff400808 32) >> 8) & 0x3fff ))
		if [ "$f1" != "$f2" ]; then hits=$((hits+1)); else hits=0; fi
		if [ $hits -ge 2 ]; then
			echo "$(cut -d' ' -f1 /proc/uptime)s state=$st with SOFs -> re-bind" >> $WL
			echo "" > $G/UDC; sleep 1; echo $UDC > $G/UDC
			echo "$(cut -d' ' -f1 /proc/uptime)s re-bound, state=$(cat /sys/class/udc/$UDC/state)" >> $WL
			sync; hits=0; sleep 20
		fi
	  done ) &
	echo "watchdog started"
fi

echo "### alsa:"
cat /proc/asound/cards

echo "### UDC state (every 2 s for 90 s):"
last=
i=0
while [ $i -lt 45 ]; do
	s="$(cat /sys/class/udc/$UDC/state) $(cat /sys/class/udc/$UDC/current_speed)"
	[ "$s" != "$last" ] && echo "t=$((i*2))s $s"
	last=$s
	sleep 2; i=$((i+1))
done

echo "### dmesg (gadget/dwc2/uac):"
dmesg | grep -iE 'gadget|dwc2|uac|u_audio|configfs|composite' | grep -v 'Mode Mismatch' | tail -60
sync
