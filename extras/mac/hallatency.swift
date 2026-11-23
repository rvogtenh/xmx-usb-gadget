// hallatency: round-trip latency of a CoreAudio device with a loopback on the other side.
// One duplex IOProc on the device sends a short click on channel 1 every 0.5 s and
// looks for it in input channel 1. Latency = input sample time of the click minus
// output sample time, both on the device's own timeline (includes the device's
// safety offsets and USB, not the app's own buffer).
// Build: swiftc -O hallatency.swift -o hallatency
// Use:   ./hallatency "XMX Audio" 10 [bufferFrames]
import CoreAudio
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: hallatency <device> <seconds> [bufferFrames]"); exit(1) }
let wanted = args[1]; let seconds = Double(args[2]) ?? 10
let wantBuf: UInt32? = args.count > 3 ? UInt32(args[3]) : nil

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

func u32(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32 {
    var ad = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var v: UInt32 = 0; var s = UInt32(4); AudioObjectGetPropertyData(dev, &ad, 0, nil, &s, &v); return v
}
if var b = wantBuf {
    var ad = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    AudioObjectSetPropertyData(dev, &ad, 0, nil, 4, &b)
}
let buf = u32(kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal)
let latOut = u32(kAudioDevicePropertyLatency, kAudioObjectPropertyScopeOutput)
let latIn = u32(kAudioDevicePropertyLatency, kAudioObjectPropertyScopeInput)
let safOut = u32(kAudioDevicePropertySafetyOffset, kAudioObjectPropertyScopeOutput)
let safIn = u32(kAudioDevicePropertySafetyOffset, kAudioObjectPropertyScopeInput)
print("buffer \(buf) · reported latency out \(latOut) in \(latIn) · safety out \(safOut) in \(safIn) frames")

final class State {
    var nextClick: Float64 = -1; var sent: [Float64] = []; var lat: [Float64] = []; var armed = true; var lost = 0
}
let st = State(); let rate = 48000.0; let interval = rate / 2
var procID: AudioDeviceIOProcID?
AudioDeviceCreateIOProcIDWithBlock(&procID, dev, nil) { _, inData, inTime, outData, outTime in
    // output: click
    let ot = outTime.pointee.mSampleTime
    if st.nextClick < 0 { st.nextClick = ot + rate }   // first click after 1 s
    let ob = UnsafeMutableAudioBufferListPointer(outData)
    for b in ob {
        guard let p = b.mData else { continue }
        let nch = Int(b.mNumberChannels); let n = Int(b.mDataByteSize) / 4 / max(nch, 1)
        let f = p.assumingMemoryBound(to: Float.self)
        for i in 0..<n * nch { f[i] = 0 }
        for i in 0..<n {
            let t = ot + Float64(i)
            if t >= st.nextClick && t < st.nextClick + 4 { f[i * nch] = 0.5 }
            if t == st.nextClick + 3 { st.sent.append(st.nextClick); st.nextClick += interval }
        }
        break
    }
    // input: detect
    let it = inTime.pointee.mSampleTime
    let ib = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
    for b in ib {
        guard let p = b.mData else { continue }
        let nch = Int(b.mNumberChannels); let n = Int(b.mDataByteSize) / 4 / max(nch, 1)
        let f = p.assumingMemoryBound(to: Float.self)
        for i in 0..<n {
            let v = abs(f[i * nch])
            if st.armed && v > 0.2 {
                // match the newest click sent before this sample; older unmatched ones count as lost
                let t = it + Float64(i)
                if let s = st.sent.last(where: { $0 <= t }), t - s < rate / 4 {
                    st.lat.append(t - s); st.lost += st.sent.filter { $0 < s }.count
                    st.sent.removeAll { $0 <= s }
                }
                st.armed = false
            } else if !st.armed && v < 0.01 { st.armed = true }
        }
        break
    }
}
AudioDeviceStart(dev, procID)
usleep(UInt32(seconds * 1_000_000))
AudioDeviceStop(dev, procID); AudioDeviceDestroyIOProcID(dev, procID!)
guard !st.lat.isEmpty else { print("no click came back"); exit(2) }
let l = st.lat.sorted()
let ms = { (x: Float64) in String(format: "%.2f ms", x / rate * 1000) }
print("clicks back \(l.count), lost \(st.lost) · round trip min \(Int(l.first!)) (\(ms(l.first!))) median \(Int(l[l.count / 2])) (\(ms(l[l.count / 2]))) max \(Int(l.last!)) (\(ms(l.last!))) frames")
