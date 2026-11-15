import AVFoundation

/// `FakeOS --render-audio out.wav`: 2 s of each layer/effect in order, printed as a timeline.
func renderAudioTest(to path: String) {
    let sr: Double = 48000
    let synth = Synth(sampleRate: Float(sr))
    let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
    guard let file = try? AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: fmt.settings) else { print("cannot write"); return }
    let block = 512
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(block))!
    var t: Double = 0
    var renderTime: Double = 0
    func run(_ seconds: Double) {
        var left = Int(seconds * sr)
        while left > 0 {
            let n = min(block, left)
            buf.frameLength = AVAudioFrameCount(n)
            let start = CFAbsoluteTimeGetCurrent()
            synth.render(frames: n, left: buf.floatChannelData![0], right: buf.floatChannelData![1])
            renderTime += CFAbsoluteTimeGetCurrent() - start
            try? file.write(from: buf)
            left -= n
        }
        t += seconds
    }
    func seg(_ name: String, _ seconds: Double, _ f: () -> Void) {
        print(String(format: "SEG %6.2f %6.2f %@", t, seconds, name))
        f()
        run(seconds)
    }
    synth.master = 0.8
    // ambience only, everything else off
    synth.wind = 0; synth.rain = 0; synth.fanTarget = 0; synth.fridgeOn = false; synth.room = 0
    seg("silence", 1.5) {}
    seg("room", 2) { synth.room = 1 }
    seg("wind", 2) { synth.room = 0; synth.wind = 1 }
    seg("rain", 3) { synth.wind = 0; synth.rain = 1 }
    seg("fan", 4) { synth.rain = 0; synth.fanTarget = 0.8 }
    seg("fridge", 3) { synth.fanTarget = 0; synth.fridgeOn = true }
    seg("heart", 3) { synth.fridgeOn = false; synth.heart = 0.8 }
    seg("drone", 2) { synth.heart = 0; synth.drone = 0.8 }
    seg("clock", 3) { synth.drone = 0; synth.clockRunning = true }
    synth.clockRunning = false
    let fx: [(SFX, Double)] = [(.creak, 2), (.footsteps, 3.5), (.knock, 1.2), (.car, 7.5), (.thunder, 6.5), (.meow, 1.5), (.whisper, 2.5),
                               (.glitchZap, 1), (.keyClick, 0.5), (.ghostKey, 0.5), (.thud, 1), (.chime, 3), (.chapterChord, 5),
                               (.clunk, 0.6), (.breath, 2.5), (.tick, 0.5), (.bird, 1), (.bootChime, 4), (.flatline, 7.5)]
    for (k, d) in fx { seg("\(k)", d) { synth.trigger(k, pan: 0) } }
    // full mix at high haunt for 6 s
    seg("fullmix", 6) {
        synth.room = 1; synth.wind = 0.6; synth.rain = 0.8; synth.fanTarget = 0.8; synth.fridgeOn = true; synth.heart = 0.7; synth.drone = 0.7
        synth.trigger(.creak); synth.trigger(.whisper); synth.trigger(.thunder); synth.trigger(.knock); synth.trigger(.footsteps)
    }
    print(String(format: "RENDER %.2f s audio in %.3f s CPU (%.1f%% of real time)", t, renderTime, renderTime / t * 100))
}
