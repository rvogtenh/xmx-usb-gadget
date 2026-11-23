#!/usr/bin/env python3
"""Loop the USB audio back to the host: UAC2Gadget capture -> UAC2Gadget playback.

For round-trip latency tests (host -> XMX -> host). No alsaloop on the XMX, so this
talks to libasound through ctypes. Run it pinned to an isolated CPU with RT priority
(done by the script itself, the XMX has no taskset):

  python3 usbloop.py [period] [periods] [seconds]

period  = frames per read/write (default 128), periods = buffer size in periods (default 3).
The playback buffer is pre-filled with one period of silence, so the loop itself adds
about one period on top of the gadget/USB latency.
"""
import ctypes, os, sys, time

try:  # isolated CPU 2 (isolcpus=1,2,3; the USB IRQ is on CPU 1), SCHED_FIFO 70
    os.sched_setaffinity(0, {2})
    os.sched_setscheduler(0, os.SCHED_FIFO, os.sched_param(70))
except (AttributeError, OSError) as e:
    print("no cpu/rt setting:", e)

PERIOD = int(sys.argv[1]) if len(sys.argv) > 1 else 128
PERIODS = int(sys.argv[2]) if len(sys.argv) > 2 else 3
SECS = float(sys.argv[3]) if len(sys.argv) > 3 else 60
CH, RATE, DEV = 8, 48000, b"hw:UAC2Gadget"

a = ctypes.CDLL("libasound.so.2")
SND_PCM_STREAM_PLAYBACK, SND_PCM_STREAM_CAPTURE = 0, 1
FMT_S16_LE, ACCESS_RW_INTERLEAVED = 2, 3
a.snd_pcm_readi.restype = ctypes.c_long
a.snd_pcm_writei.restype = ctypes.c_long
a.snd_strerror.restype = ctypes.c_char_p


def check(r, what):
    if r < 0:
        raise SystemExit(f"{what}: {a.snd_strerror(r).decode()}")
    return r


def open_pcm(stream):
    h = ctypes.c_void_p()
    check(a.snd_pcm_open(ctypes.byref(h), DEV, stream, 0), "open")
    hw = ctypes.c_void_p()
    check(a.snd_pcm_hw_params_malloc(ctypes.byref(hw)), "hw malloc")
    check(a.snd_pcm_hw_params_any(h, hw), "hw any")
    check(a.snd_pcm_hw_params_set_access(h, hw, ACCESS_RW_INTERLEAVED), "access")
    check(a.snd_pcm_hw_params_set_format(h, hw, FMT_S16_LE), "format")
    check(a.snd_pcm_hw_params_set_channels(h, hw, CH), "channels")
    check(a.snd_pcm_hw_params_set_rate(h, hw, RATE, 0), "rate")
    ps = ctypes.c_ulong(PERIOD)
    check(a.snd_pcm_hw_params_set_period_size_near(h, hw, ctypes.byref(ps), None), "period")
    bs = ctypes.c_ulong(PERIOD * PERIODS)
    check(a.snd_pcm_hw_params_set_buffer_size_near(h, hw, ctypes.byref(bs)), "buffer")
    check(a.snd_pcm_hw_params(h, hw), "hw params")
    a.snd_pcm_hw_params_free(hw)
    return h, ps.value, bs.value


cap, cps, cbs = open_pcm(SND_PCM_STREAM_CAPTURE)
pb, pps, pbs = open_pcm(SND_PCM_STREAM_PLAYBACK)
print(f"capture period {cps} buffer {cbs} | playback period {pps} buffer {pbs}", flush=True)

buf = ctypes.create_string_buffer(PERIOD * CH * 2)
a.snd_pcm_writei(pb, buf, PERIOD)          # one period of silence as cushion
a.snd_pcm_start(cap)
xruns, t0 = 0, time.monotonic()
while time.monotonic() - t0 < SECS:
    n = a.snd_pcm_readi(cap, buf, PERIOD)
    if n < 0:
        xruns += 1; a.snd_pcm_recover(cap, int(n), 1); continue
    w = a.snd_pcm_writei(pb, buf, n)
    if w < 0:
        xruns += 1; a.snd_pcm_recover(pb, int(w), 1)
        a.snd_pcm_writei(pb, buf, n)
print(f"done, xruns {xruns}", flush=True)
a.snd_pcm_close(cap); a.snd_pcm_close(pb)
