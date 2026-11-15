import AppKit
import AVFoundation

/// Procedural sound: a low drone that grows with the haunting, static bursts for glitches,
/// and little key clicks when wren types. Real system alert sounds for UI realism.
final class Audio {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    // parameters read by the render thread (benign races are fine for audio params)
    var drone: Float = 0
    var staticLevel: Float = 0
    var glitchStatic: Float = 0
    var master: Float = 0.8
    private var clickEnergy: Float = 0
    private var phase1: Float = 0
    private var phase2: Float = 0
    private var phase3: Float = 0
    private var lp: Float = 0
    private var rng: UInt32 = 0x1234_5678

    init() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sr = Float(format.sampleRate > 0 ? format.sampleRate : 48000)
        let mono = AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: 1)!
        source = AVAudioSourceNode(format: mono) { [unowned self] _, _, frameCount, abl -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let d = self.drone * self.master
            let st = min(1, self.staticLevel + self.glitchStatic) * self.master
            for f in 0..<Int(frameCount) {
                self.rng = self.rng &* 1_664_525 &+ 1_013_904_223
                let noise = Float(Int32(bitPattern: self.rng)) / Float(Int32.max)
                self.phase1 += 55 / sr
                self.phase2 += 55.7 / sr
                self.phase3 += 0.13 / sr
                if self.phase1 > 1 { self.phase1 -= 1 }
                if self.phase2 > 1 { self.phase2 -= 1 }
                if self.phase3 > 1 { self.phase3 -= 1 }
                self.lp += (noise - self.lp) * 0.02
                let swell = 0.6 + 0.4 * sin(self.phase3 * 2 * .pi)
                var s = (sin(self.phase1 * 2 * .pi) + sin(self.phase2 * 2 * .pi) * 0.8 + self.lp * 3) * 0.12 * d * swell
                s += noise * 0.35 * st
                if self.clickEnergy > 0.0001 {
                    s += noise * self.clickEnergy * 0.5 * self.master
                    self.clickEnergy *= 0.985
                }
                for b in buffers {
                    b.mData?.assumingMemoryBound(to: Float.self)[f] = max(-1, min(1, s))
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: mono)
        engine.mainMixerNode.outputVolume = 0.9
        do { try engine.start() } catch { NSLog("Audio engine failed: \(error)") }
    }

    func tick() { clickEnergy = max(clickEnergy, 0.18) }

    func beep() { NSSound.beep() }

    func systemSound(_ name: String) {
        guard master > 0.02, let s = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        s.volume = master
        s.play()
    }
}
