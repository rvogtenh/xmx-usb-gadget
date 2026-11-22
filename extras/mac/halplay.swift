// halplay: play a phase-continuous sine on all output channels of a CoreAudio
// device straight from its HAL IOProc (paced by the device clock, no ffmpeg).
// Reports IOProc timestamp gaps.
// Build: swiftc -O halplay.swift -o halplay
// Use:   ./halplay "XMX Audio" 10 440 0.5
import CoreAudio
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: halplay <device name> <seconds> [freq] [amp]"); exit(1) }
let wanted = args[1]; let seconds = Double(args[2]) ?? 10
let freq = args.count > 3 ? Double(args[3])! : 440; let amp = args.count > 4 ? Float(args[4])! : 0.5

var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
var dev: AudioObjectID = 0
for id in ids {
    var na = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var name: CFString = "" as CFString; var s = UInt32(MemoryLayout<CFString>.size)
    AudioObjectGetPropertyData(id, &na, 0, nil, &s, &name)
    if (name as String) == wanted { dev = id }
}
guard dev != 0 else { print("device not found: \(wanted)"); exit(1) }
var ra = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var rate: Float64 = 0; var rs = UInt32(8); AudioObjectGetPropertyData(dev, &ra, 0, nil, &rs, &rate)

final class State { var phase = 0.0; var frames = 0; var lastEnd: Float64 = -1; var gaps = 0 }
let st = State(); let total = Int(seconds * rate); let inc = 2 * Double.pi * freq / rate
var procID: AudioDeviceIOProcID?
AudioDeviceCreateIOProcIDWithBlock(&procID, dev, nil) { _, _, _, outData, outTime in
    let t = outTime.pointee.mSampleTime
    let abl = UnsafeMutableAudioBufferListPointer(outData)
    guard let b = abl.first, let p = b.mData else { return }
    let nch = Int(b.mNumberChannels); let frames = Int(b.mDataByteSize) / 4 / max(nch, 1)
    if st.lastEnd >= 0 && abs(t - st.lastEnd) > 0.5 { st.gaps += 1 }
    st.lastEnd = t + Float64(frames)
    let f = p.assumingMemoryBound(to: Float.self)
    for i in 0..<frames {
        let v = st.frames < total ? amp * Float(sin(st.phase)) : 0
        st.phase += inc; if st.phase > 2 * Double.pi { st.phase -= 2 * Double.pi }
        for c in 0..<nch { f[i * nch + c] = v }
        st.frames += 1
    }
}
AudioDeviceStart(dev, procID)
while st.frames < total { usleep(20000) }
usleep(100000)
AudioDeviceStop(dev, procID); AudioDeviceDestroyIOProcID(dev, procID!)
print("played \(total) frames at \(rate) Hz, timestamp gaps \(st.gaps)")
