// Print CoreAudio's measured (actual) sample rate of a device once per second.
import CoreAudio
import Foundation
let wanted = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "XMX Audio"
let secs = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 10
var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
var ids = [AudioDeviceID](repeating: 0, count: Int(size) / 4)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
var dev: AudioDeviceID = 0
for id in ids {
    var na = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var name: Unmanaged<CFString>?; var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    AudioObjectGetPropertyData(id, &na, 0, nil, &s, &name)
    if let n = name?.takeRetainedValue() as String?, n == wanted { dev = id }
}
var ra = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyActualSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
for _ in 0..<secs {
    var r: Float64 = 0; var s = UInt32(8)
    AudioObjectGetPropertyData(dev, &ra, 0, nil, &s, &r)
    print(String(format: "%.3f", r)); fflush(stdout)
    sleep(1)
}
