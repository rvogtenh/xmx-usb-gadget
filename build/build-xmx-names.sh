#!/bin/sh
# Rebuild usb_f_uac2.ko and usb_f_midi.ko with XMX patches:
#  - uac2: one shared clock source for both directions -> macOS shows ONE device;
#          streaming interface names "XMX Playback"/"XMX Capture"
#  - midi: interface and jack names "XMX Midi"
# Needs a configured tree from build-midi.sh.
set -e
F=/k/src/drivers/usb/gadget/function
cd $F
for s in f_uac2.c f_midi.c; do [ -f $s.orig ] || cp $s $s.orig; cp $s.orig $s; done
sed -i \
 -e 's/"Playback Inactive"/"XMX Playback"/' -e 's/"Playback Active"/"XMX Playback"/' \
 -e 's/"Capture Inactive"/"XMX Capture"/'   -e 's/"Capture Active"/"XMX Capture"/' \
 -e 's/"Topology Control"/"XMX Audio"/'  -e 's/"Input Clock"/"XMX Clock"/'          -e 's/"Output Clock"/"XMX Clock"/' \
 -e 's/usb_in_ot_desc.bCSourceID = in_clk_src_desc.bClockID;/usb_in_ot_desc.bCSourceID = out_clk_src_desc.bClockID; \/* XMX: shared clock *\//' \
 -e 's/io_in_it_desc.bCSourceID = in_clk_src_desc.bClockID;/io_in_it_desc.bCSourceID = out_clk_src_desc.bClockID; \/* XMX: shared clock *\//' \
 f_uac2.c
sed -i \
 -e 's/\[STRING_FUNC_IDX\].s = "MIDI function",/[STRING_FUNC_IDX].s = "XMX Midi",/' \
 -e 's/^\(\t*\)\(in_ext\|out_emb\|in_emb\)->iJack\(\t*\)= 0;/\1\2->iJack = us[STRING_FUNC_IDX].id; \/* XMX *\//' \
 -e 's/^\(\t*\)out_ext->iJack =\(\t*\)0;/\1out_ext->iJack = us[STRING_FUNC_IDX].id; \/* XMX *\//' \
 -e 's/^\(\t*\)ac_interface_desc.iInterface = us\[STRING_FUNC_IDX\].id;/&\n\1ms_interface_desc.iInterface = us[STRING_FUNC_IDX].id; \/* XMX *\//' \
 f_midi.c
echo "--- uac2"; diff f_uac2.c.orig f_uac2.c | grep '^>' ; echo "--- midi"; diff f_midi.c.orig f_midi.c | grep '^>'
cd /k/src
make CC=gcc -s -j$(nproc) KBUILD_MODPOST_WARN=1 M=drivers/usb/gadget modules 2>&1 | grep -vE "modpost|undefined!|Module.symvers|dependencies" | tail -3
cp $F/usb_f_uac2.ko $F/usb_f_midi.ko /k/out/
