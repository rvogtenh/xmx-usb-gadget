#!/usr/bin/env python3
"""Measure the clock drift between the XMX codec and the UAC2 gadget.

Both streams are sampled through /proc/asound/.../status (hw_ptr) against
CLOCK_MONOTONIC, so the running app (TraxHost/Synthor) keeps the codec.
A reader (e.g. arecord on hw:UAC2Gadget) must keep the gadget stream open,
and the host must be playing into "XMX Audio".

usage: clockdrift.py [seconds] [interval]
prints: rate of each stream (frames/s in XMX system time), drift in ppm,
and the "Capture Pitch" value that would match the gadget to the codec.
"""
import sys, time

CODEC = "/proc/asound/card1/pcm0c/sub0/status"
GADGET = "/proc/asound/card2/pcm0c/sub0/status"


def hw_ptr(path):
    with open(path) as f:
        for line in f:
            if line.startswith("hw_ptr"):
                return int(line.split(":")[1])
    raise RuntimeError(f"{path}: stream not running")


def fit(ts, ys):
    """least-squares slope"""
    n = len(ts)
    mt, my = sum(ts) / n, sum(ys) / n
    num = sum((t - mt) * (y - my) for t, y in zip(ts, ys))
    den = sum((t - mt) ** 2 for t in ts)
    return num / den


def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 120
    step = float(sys.argv[2]) if len(sys.argv) > 2 else 0.05
    t0 = time.monotonic()
    tc, yc, tg, yg = [], [], [], []
    while time.monotonic() - t0 < secs:
        # read each pointer right next to its own timestamp
        a = time.monotonic(); c = hw_ptr(CODEC); b = time.monotonic()
        tc.append((a + b) / 2 - t0); yc.append(c)
        a = time.monotonic(); g = hw_ptr(GADGET); b = time.monotonic()
        tg.append((a + b) / 2 - t0); yg.append(g)
        time.sleep(step)
    rc, rg = fit(tc, yc), fit(tg, yg)
    drift = (rg / rc - 1) * 1e6
    print(f"samples   {len(tc)} over {tc[-1]:.1f} s")
    print(f"codec     {rc:.3f} frames/s")
    print(f"gadget    {rg:.3f} frames/s")
    print(f"drift     {drift:+.1f} ppm (gadget vs codec)")
    print(f"pitch     {round(1e6 * rc / rg)} would match the gadget to the codec (if pitch was 1000000)")


if __name__ == "__main__":
    main()
