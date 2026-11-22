// halrec: record channel 1 of a CoreAudio device straight from its HAL IOProc
// (no AVFoundation/ffmpeg in between) and write a 16-bit mono WAV.
// Also reports IOProc timestamp gaps (sample-time discontinuities).
// Build: swiftc -O halrec.swift -o halrec
// Use:   ./halrec "XMX Audio" 8 out.wav
import CoreAudio
import Foundation

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: halrec <device name> <seconds> <out.wav>"); exit(1) }
let wanted = args[1]; let seconds = Double(args[2]) ?? 8; let outPath = args[3]

func prop<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ v: inout T) -> OSStatus {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v)
}

var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
var dev: AudioObjectID = 0
for id in ids {
    var name: CFString = "" as CFString
    _ = prop(id, kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, &name)
    if (name as String) == wanted { dev = id }
}
guard dev != 0 else { print("device not found: \(wanted)"); exit(1) }
var rate: Float64 = 0; _ = prop(dev, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, &rate)
var bufFrames: UInt32 = 0; _ = prop(dev, kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal, &bufFrames)
print("device \(dev) rate \(rate) buffer \(bufFrames) frames")

final class State { var samples = [Float](); var lastEnd: Float64 = -1; var gaps = 0; var gapLog = [String](); var calls = 0 }
let st = State()
let total = Int(seconds * rate)
st.samples.reserveCapacity(total + 4096)

var procID: AudioDeviceIOProcID?
let status = AudioDeviceCreateIOProcIDWithBlock(&procID, dev, nil) { _, inData, inTime, _, _ in
    let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
    guard let b = abl.first, let p = b.mData else { return }
    let nch = Int(b.mNumberChannels); let frames = Int(b.mDataByteSize) / 4 / max(nch, 1)
    let t = inTime.pointee.mSampleTime
    st.calls += 1
    if st.lastEnd >= 0 && abs(t - st.lastEnd) > 0.5 {
        st.gaps += 1
        if st.gapLog.count < 10 { st.gapLog.append(String(format: "t=%.0f expected %.0f (diff %.0f)", t, st.lastEnd, t - st.lastEnd)) }
    }
    st.lastEnd = t + Float64(frames)
    let f = p.assumingMemoryBound(to: Float.self)
    if st.samples.count < total { for i in 0..<frames { st.samples.append(f[i * nch]) } }
}
guard status == noErr, let pid = procID else { print("IOProc error \(status)"); exit(1) }
AudioDeviceStart(dev, pid)
while st.samples.count < total { usleep(20000) }
AudioDeviceStop(dev, pid)
AudioDeviceDestroyIOProcID(dev, pid)
print("ioproc calls \(st.calls), timestamp gaps \(st.gaps)"); st.gapLog.forEach { print("  " + $0) }

// WAV 16-bit mono
var d = Data()
func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
let n = st.samples.count
d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
d.append("data".data(using: .ascii)!); u32(UInt32(n * 2))
for s in st.samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))) }
try! d.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath), \(n) frames")
