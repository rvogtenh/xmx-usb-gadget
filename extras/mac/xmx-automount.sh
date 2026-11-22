#!/bin/zsh
# XMX auto-mount (macOS LaunchAgent): mounts the XMX WebDAV share (BOOT partition)
# as volume "XMX" when the XMX is reachable over the USB network, and force-unmounts
# it when the XMX goes away (a dead WebDAV mount would hang Finder).
# If you eject XMX in Finder, it stays ejected until the XMX disconnects and comes back.
# Install: see extras/README.md
IP=10.77.0.1
URL=http://$IP:8080/              # reachability check (direct IP)
MURL=http://XMX.local:8080/       # mount URL: Finder shows the host name, so use XMX.local
MP="$HOME/Library/Application Support/XMX-Mount/XMX"
mkdir -p "$MP"
log() { print -r -- "$(date '+%F %T') $*"; }
mounted() { mount | grep -qF " on $MP (webdav" ; }
reachable() { curl -s -m 2 -o /dev/null -X OPTIONS "$URL"; }
# Advertise the host name XMX.local -> 10.77.0.1 from the Mac itself (mDNS proxy record),
# so Finder shows "XMX.local" instead of the IP. Nothing is needed on the XMX for this.
DNSSD=
proxy_on()  { [ -n "$DNSSD" ] && kill -0 $DNSSD 2>/dev/null && return
              dns-sd -P XMX _webdav._tcp local 8080 XMX.local $IP path=/ >/dev/null 2>&1 & DNSSD=$!; sleep 1; }
proxy_off() { [ -n "$DNSSD" ] && kill $DNSSD 2>/dev/null; DNSSD=; }
trap 'proxy_off; exit 0' TERM INT
ejected=0
log "start"
while true; do
	if reachable; then
		if ! mounted && [ "$was" = 1 ]; then
			log "ejected by user, not remounting until the XMX reconnects"; ejected=1; was=0
		elif ! mounted && [ $ejected = 0 ]; then
			proxy_on
			if mount_webdav -S -v XMX "$MURL" "$MP" 2>/dev/null || mount_webdav -S -v XMX "$URL" "$MP" 2>/dev/null; then
				log "mounted ($(mount | grep -F " on $MP (" | cut -d' ' -f1))"; was=1
			fi
		fi
	else
		if mounted; then umount -f "$MP" 2>/dev/null || diskutil unmount force "$MP" >/dev/null 2>&1; log "XMX gone, unmounted"; fi
		proxy_off; ejected=0; was=0
	fi
	sleep 5
done
