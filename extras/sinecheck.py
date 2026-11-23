#!/usr/bin/env python3
"""Check a recording of a 440 Hz sine for discontinuities (lost or repeated packets).

usage: sinecheck.py file.raw   (S16_LE, 8 channels, 48 kHz; channel 1 is checked)
For a clean sine x[n+1] + x[n-1] = 2 cos(w) x[n]; every jump leaves a large residual.
Record on the XMX while the host plays a sine into "XMX Audio", e.g.
  arecord -D hw:UAC2Gadget -f S16_LE -c 8 -r 48000 -t raw -d 8 \
          --period-size=256 --buffer-size=768 /tmp/g.raw
"""
import struct, math, sys
d=open(sys.argv[1],"rb").read(); n=len(d)//16
x=[struct.unpack_from("<h",d,i*16)[0] for i in range(n)]
zc=[i for i in range(1,n) if x[i-1]<0<=x[i]]
f=(len(zc)-1)/((zc[-1]-zc[0])/48000)
k=2*math.cos(2*math.pi*440/48000)
res=[abs(x[i+1]+x[i-1]-k*x[i]) for i in range(1,n-1)]
g=[];
for i,r in enumerate(res):
    if r>40 and (not g or i-g[-1]>20): g.append(i)
z=sum(1 for v in x if v==0)
print("frames",n,"freq %.3f Hz"%f,"jumps",len(g),"zeros",z, "first", g[:6])
