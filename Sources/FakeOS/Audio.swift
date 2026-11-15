import AppKit
import AVFoundation
import os

/// One-shot sound effects, all synthesized.
enum SFX {
    case creak, footsteps, knock, car, thunder, meow, whisper, glitchZap, keyClick, ghostKey, thud
    case chime, chapterChord, clunk, breath, tick, bird, bootChime, flatline
}

/// Chamberlin state-variable filter. `f` = 2·sin(π·fc/sr), `q` = damping (low = resonant).
struct SVF {
    var low: Float = 0
    var band: Float = 0
    @inline(__always) mutating func bp(_ x: Float, _ f: Float, _ q: Float) -> Float {
        low += f * band
        let high = x - low - q * band
        band += f * high
        return band
    }
    @inline(__always) mutating func lp(_ x: Float, _ f: Float, _ q: Float) -> Float {
        _ = bp(x, f, q)
        return low
    }
}

struct Voice {
    var kind: SFX
    var t = 0
    var len: Int
    var gain: Float
    var pan: Float
    var a: Float = 0, b: Float = 0, c: Float = 0
    var f1 = SVF(), f2 = SVF(), f3 = SVF()
    var phase: Float = 0
    var next = 0
    var count = 0
    var bypassMaster = false
}

/// The whole soundscape, rendered sample by sample. Parameters are plain floats written by the
/// main thread and read by the audio thread (benign races); one-shots come in through a lock.
final class Synth {
    let sr: Float
    // ambience parameters (0…1)
    var master: Float = 0.8
    var room: Float = 1
    var wind: Float = 0.3
    var rain: Float = 0.4
    var fanTarget: Float = 0.3
    var fridgeOn = true
    var heart: Float = 0
    var clockRunning = false
    var drone: Float = 0
    var staticLevel: Float = 0
    var ambienceMute: Float = 1   // 0 silences ambience (boot, panic)

    private let pending = OSAllocatedUnfairLock<[Voice]>(initialState: [])
    private var voices: [Voice] = []
    private var rng: UInt32 = 0x9E37_79B9

    // continuous state
    private var brownL: Float = 0, brownR: Float = 0
    private var windF = SVF(), windF2 = SVF()
    private var windPhase: Float = 0
    private var rainHP = SVF()
    private var fan: Float = 0.3, fanF = SVF(), fanPhase: Float = 0, fanWob: Float = 0
    private var fridgeEnv: Float = 1, fridgePhase: Float = 0
    private var droneP1: Float = 0, droneP2: Float = 0, droneP3: Float = 0, droneLP: Float = 0
    private var heartT: Float = 10
    private var clockCounter = 0
    private var tockFlip = false
    private struct Drop { var t: Float; var f: Float; var pan: Float; var g: Float }
    private var drops: [Drop] = []

    init(sampleRate: Float) {
        sr = sampleRate
        voices.reserveCapacity(64)
        drops.reserveCapacity(16)
    }

    @inline(__always) private func white() -> Float {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        return Float(Int32(bitPattern: rng)) / Float(Int32.max)
    }
    @inline(__always) private func rand01() -> Float { white() * 0.5 + 0.5 }
    @inline(__always) private func fc(_ hz: Float) -> Float { min(1.6, 2 * sin(.pi * hz / sr)) }

    // MARK: - Triggers (any thread)

    func trigger(_ kind: SFX, gain: Float = 1, pan: Float? = nil, bypassMaster: Bool = false) {
        var v = makeVoice(kind, gain: gain, pan: pan ?? Float.random(in: -0.7...0.7))
        v.bypassMaster = bypassMaster
        pending.withLock { $0.append(v) }
    }

    private func makeVoice(_ k: SFX, gain: Float, pan: Float) -> Voice {
        func secs(_ s: Float) -> Int { Int(s * sr) }
        var v: Voice
        switch k {
        case .creak:       v = Voice(kind: k, len: secs(Float.random(in: 0.9...1.8)), gain: 0.5 * gain, pan: pan); v.a = Float.random(in: 0.5...1)
        case .footsteps:   v = Voice(kind: k, len: secs(3.2), gain: 0.55 * gain, pan: Float.random(in: -1...(-0.3))); v.a = Float.random(in: 0.3...1)
        case .knock:       v = Voice(kind: k, len: secs(0.7), gain: 1.5 * gain, pan: pan)
        case .car:         v = Voice(kind: k, len: secs(7), gain: 0.35 * gain, pan: 0); v.a = Bool.random() ? 1 : -1
        case .thunder:     v = Voice(kind: k, len: secs(6), gain: 0.45 * gain, pan: Float.random(in: -0.4...0.4))
        case .meow:        v = Voice(kind: k, len: secs(0.95), gain: 0.07 * gain, pan: pan)
        case .whisper:     v = Voice(kind: k, len: secs(Float.random(in: 1.3...2.0)), gain: 0.32 * gain, pan: Bool.random() ? 0.85 : -0.85)
        case .glitchZap:   v = Voice(kind: k, len: secs(0.32), gain: 0.16 * gain, pan: Float.random(in: -0.5...0.5))
        case .keyClick:    v = Voice(kind: k, len: secs(0.035), gain: 0.16 * gain, pan: Float.random(in: -0.15...0.15))
        case .ghostKey:    v = Voice(kind: k, len: secs(0.04), gain: 0.2 * gain, pan: Float.random(in: -0.3...0.3))
        case .thud:        v = Voice(kind: k, len: secs(0.7), gain: 0.8 * gain, pan: 0)
        case .chime:       v = Voice(kind: k, len: secs(2.6), gain: 0.16 * gain, pan: 0)
        case .chapterChord: v = Voice(kind: k, len: secs(4.5), gain: 0.3 * gain, pan: 0)
        case .clunk:       v = Voice(kind: k, len: secs(0.3), gain: 0.35 * gain, pan: 0.6)
        case .breath:      v = Voice(kind: k, len: secs(2.0), gain: 0.22 * gain, pan: Float.random(in: -0.2...0.2))
        case .tick:        v = Voice(kind: k, len: secs(0.05), gain: 0.22 * gain, pan: -0.35)
        case .bird:        v = Voice(kind: k, len: secs(0.6), gain: 0.1 * gain, pan: pan); v.a = Float.random(in: 3200...4600); v.count = Int.random(in: 2...4)
        case .bootChime:   v = Voice(kind: k, len: secs(3.5), gain: 0.22 * gain, pan: 0)
        case .flatline:    v = Voice(kind: k, len: secs(7), gain: 0.06 * gain, pan: 0)
        }
        return v
    }

    // MARK: - Render (audio thread)

    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        if let new = pending.withLockIfAvailable({ q -> [Voice] in let x = q; q.removeAll(keepingCapacity: true); return x }), !new.isEmpty {
            voices.append(contentsOf: new)
            if voices.count > 48 { voices.removeFirst(voices.count - 48) }
        }
        let m = master
        let amb = ambienceMute
        let windG = wind * 0.2 * amb, rainG = rain * amb, roomG = room * 0.05 * amb
        let heartG = heart * 0.38 * amb
        let droneG = drone * 0.12
        let st = staticLevel * 0.35
        let fridgeT: Float = fridgeOn ? 1 : 0
        let fanSlew = 1 / (sr * 3)
        let ft = fanTarget

        for i in 0..<frames {
            var l: Float = 0, r: Float = 0
            let w = white(), w2 = white()

            // room tone: two decorrelated brown noises
            brownL = (brownL + w * 0.02) * 0.997
            brownR = (brownR + w2 * 0.02) * 0.997
            l += brownL * roomG * 3
            r += brownR * roomG * 3

            // wind: slow-moving band of noise
            windPhase += 0.07 / sr
            if windPhase > 1 { windPhase -= 1 }
            let gust = 0.55 + 0.45 * sin(windPhase * 2 * .pi) * sin(windPhase * 5.3 * .pi)
            let wl = windF.bp(w, fc(320 + 240 * gust), 0.6) * windG * gust
            let wr = windF2.bp(w2, fc(380 + 200 * gust), 0.6) * windG * gust
            l += wl; r += wr

            // rain: hiss + droplets on the glass
            if rainG > 0.001 {
                let hiss = w - rainHP.lp(w, fc(1800), 1.0)
                l += hiss * rainG * 0.025
                r += (w2 - rainHP.low * 0.9) * rainG * 0.025
                if rand01() < rainG * 0.0009 && drops.count < 14 {
                    drops.append(Drop(t: 0, f: Float.random(in: 1800...5200), pan: Float.random(in: -1...1), g: Float.random(in: 0.02...0.07)))
                }
            }
            if !drops.isEmpty {
                var k = 0
                while k < drops.count {
                    drops[k].t += 1 / sr
                    let d = drops[k]
                    let s = sin(2 * .pi * d.f * d.t * (1 - d.t * 6)) * exp(-d.t * 120) * d.g * rainG
                    l += s * (1 - d.pan) * 0.5; r += s * (1 + d.pan) * 0.5
                    if d.t > 0.05 { drops.remove(at: k) } else { k += 1 }
                }
            }

            // laptop fan: band noise + whine, spins toward its target
            fan += (ft - fan) * fanSlew * 3
            fanWob += 0.31 / sr
            if fanWob > 1 { fanWob -= 1 }
            let rpm = fan * (1 + 0.03 * sin(fanWob * 2 * .pi))
            let fanNoise = fanF.bp(w, fc(350 + 1100 * rpm), 1.2) * 0.1 * rpm
            fanPhase += (140 + 520 * rpm) / sr
            if fanPhase > 1 { fanPhase -= 1 }
            let whine = sin(fanPhase * 2 * .pi) * 0.008 * rpm * rpm
            l += (fanNoise + whine) * amb * 0.9
            r += (fanNoise + whine) * amb * 1.1

            // fridge in the next room: mains hum with harmonics
            fridgeEnv += (fridgeT - fridgeEnv) * (1 / (sr * 0.6))
            if fridgeEnv > 0.001 {
                fridgePhase += 50 / sr
                if fridgePhase > 1 { fridgePhase -= 1 }
                let p = fridgePhase * 2 * .pi
                let hum = (sin(p) * 0.6 + sin(2 * p) * 0.35 + sin(3 * p) * 0.18 + sin(6 * p) * 0.05) * 0.017 * fridgeEnv * amb
                l += hum * 1.2; r += hum * 0.8
            }

            // heartbeat
            if heartG > 0.001 {
                heartT += 1 / sr
                let bpm = 58 + 50 * heart
                if heartT > 60 / bpm { heartT = 0 }
                let lub = sin(2 * .pi * 52 * heartT) * exp(-heartT * 16)
                let dt = heartT - 0.24
                let dub = dt > 0 ? sin(2 * .pi * 44 * dt) * exp(-dt * 20) * 0.75 : 0
                let hb = (lub + dub) * heartG
                l += hb; r += hb
            }

            // drone (the haunting)
            if droneG > 0.0005 {
                droneP1 += 55 / sr; droneP2 += 55.7 / sr; droneP3 += 0.13 / sr
                if droneP1 > 1 { droneP1 -= 1 }
                if droneP2 > 1 { droneP2 -= 1 }
                if droneP3 > 1 { droneP3 -= 1 }
                droneLP += (w - droneLP) * 0.02
                let swell = 0.6 + 0.4 * sin(droneP3 * 2 * .pi)
                let d = (sin(droneP1 * 2 * .pi) + sin(droneP2 * 2 * .pi) * 0.8 + droneLP * 3) * droneG * swell
                l += d; r += d
            }

            // static
            if st > 0.0005 { l += w * st; r += w2 * st }

            // the clock, once it moves again
            if clockRunning {
                clockCounter += 1
                if clockCounter >= Int(sr) {
                    clockCounter = 0
                    tockFlip.toggle()
                    var v = makeVoice(.tick, gain: tockFlip ? 1 : 0.8, pan: -0.35)
                    v.a = tockFlip ? 1 : 0.82
                    voices.append(v)
                }
            }

            l *= m; r *= m

            // one-shots
            var vi = 0
            while vi < voices.count {
                let (s, done) = renderVoice(&voices[vi])
                let g = voices[vi].bypassMaster ? 1 : m
                let p = voices[vi].pan
                l += s * g * (1 - p) * 0.5 * 1.4
                r += s * g * (1 + p) * 0.5 * 1.4
                if done { voices.remove(at: vi) } else { vi += 1 }
            }

            left[i] = tanh(l * 1.2) * 0.9
            right[i] = tanh(r * 1.2) * 0.9
        }
    }

    @inline(__always) private func renderVoice(_ v: inout Voice) -> (Float, Bool) {
        let t = Float(v.t) / sr
        let dur = Float(v.len) / sr
        let x = t / dur
        v.t += 1
        let done = v.t >= v.len
        let w = white()
        var s: Float = 0
        switch v.kind {
        case .creak:
            // irregular stick-slip impulses through a resonant wooden body
            v.next -= 1
            var exc = w * 0.01
            if v.next <= 0 { exc += 1; v.next = Int(sr / (18 + 40 * rand01())) }
            let f0 = 420 + 520 * sin(.pi * x) * v.a
            s = (v.f1.bp(exc, fc(f0), 0.035) + v.f2.bp(exc, fc(f0 * 2.3), 0.06) * 0.4) * pow(sin(.pi * x), 0.7)
        case .footsteps:
            let step: Float = 0.6
            let tt = t.truncatingRemainder(dividingBy: step)
            let env = exp(-tt * 38)
            let thump = v.f1.lp(w, fc(140), 0.7) * env * 2.2 + sin(2 * .pi * 62 * tt) * env * 0.7
            s = v.f2.lp(thump, fc(300), 0.9)
            v.pan = -1 + 2 * x * v.a
        case .knock:
            let gap: Float = 0.19
            let n = Int(t / gap)
            if n < 3 {
                let tt = t - Float(n) * gap
                let exc = w * exp(-tt * 700)
                s = v.f1.bp(exc, fc(185), 0.03) * 1.4 + v.f2.bp(exc, fc(430), 0.05) * 0.6
            } else {
                s = v.f1.bp(0, fc(185), 0.03) * 1.4 + v.f2.bp(0, fc(430), 0.05) * 0.6
            }
        case .car:
            let near = exp(-pow((x - 0.5) * 5, 2))
            let tyre = v.f1.lp(w, fc(250 + 1300 * near), 0.8) * near
            v.phase += 68 * (1 + 0.1 * (0.5 - x) * 2) / sr
            if v.phase > 1 { v.phase -= 1 }
            let engine = (v.phase * 2 - 1) * 0.15 * near
            s = v.f2.lp(tyre + engine, fc(900), 0.8)
            v.pan = (-0.9 + 1.8 * x) * v.a
        case .thunder:
            v.b = (v.b + w * 0.03) * 0.996
            let crack = t < 0.25 ? w * exp(-t * 14) * 0.5 : 0
            let env = min(1, t * 8) * exp(-t * 0.6) * (0.7 + 0.3 * sin(t * 9 + sin(t * 3.1) * 2))
            s = v.f1.lp(v.b * 6 + crack, fc(140), 0.7) * env
        case .meow:
            let f0 = 520 + 300 * sin(.pi * x) - 140 * x + 12 * sin(t * 2 * .pi * 6)
            v.phase += f0 / sr
            if v.phase > 1 { v.phase -= 1 }
            let saw = v.phase * 2 - 1
            let voiced = v.f1.bp(saw, fc(950), 0.2) + v.f2.bp(saw, fc(1750 + 300 * sin(.pi * x)), 0.25) * 0.6
            s = v.f3.lp(voiced, fc(1300), 0.9) * pow(sin(.pi * x), 0.6)
        case .whisper:
            let syl: Float = 0.14
            let n = Int(t / syl)
            if n != v.count || v.t == 1 {
                v.count = n
                let vowels: [(Float, Float)] = [(320, 870), (400, 2050), (620, 1050), (270, 2300), (500, 1500), (700, 1200)]
                let p = vowels[Int(rand01() * Float(vowels.count - 1) + 0.5)]
                v.a = p.0; v.b = p.1
            }
            let u = (t - Float(n) * syl) / syl
            let sylEnv = pow(sin(.pi * u), 2) * (0.6 + 0.4 * rand01())
            let breath = v.f1.bp(w, fc(v.a), 0.18) + v.f2.bp(w, fc(v.b), 0.14) * 0.8 + v.f3.bp(w, fc(5200), 0.6) * 0.25
            s = breath * sylEnv * pow(sin(.pi * x), 0.5) * 0.8
        case .glitchZap:
            v.next -= 1
            if v.next <= 0 { v.a = Float.random(in: 60...1800); v.next = Int(sr * 0.012) }
            v.phase += v.a / sr
            if v.phase > 1 { v.phase -= 1 }
            let sq: Float = v.phase < 0.5 ? 1 : -1
            s = (sq * 0.6 + w * 0.4).rounded(.toNearestOrEven) * 0.5 * (1 - x)
        case .keyClick, .ghostKey:
            let heavy: Float = v.kind == .ghostKey ? 1.6 : 1
            let hp = w - v.f1.lp(w, fc(2500), 1)
            s = (hp * exp(-t * 320) + sin(2 * .pi * 2400 / heavy * t) * exp(-t * 520) * 0.35 + sin(2 * .pi * 180 * t) * exp(-t * 90) * 0.25 * heavy)
        case .thud:
            s = sin(2 * .pi * (46 - 10 * x) * t) * exp(-t * 5.5) + v.f1.lp(w, fc(160), 0.8) * exp(-t * 18) * 1.5
        case .chime:
            func bell(_ f: Float, _ tt: Float) -> Float {
                guard tt > 0 else { return 0 }
                return sin(2 * .pi * f * tt) * exp(-tt * 2.1) + sin(2 * .pi * f * 2.76 * tt) * exp(-tt * 5.5) * 0.28 + sin(2 * .pi * f * 5.4 * tt) * exp(-tt * 9) * 0.1
            }
            s = bell(659.25, t) + bell(987.77, t - 0.13) * 0.85 + bell(1318.5, t - 0.26) * 0.5
            s *= min(1, t * 400)
        case .chapterChord:
            let env = min(1, t / 0.9) * exp(-max(0, t - 0.9) * 0.9)
            var c: Float = 0
            for (k, f) in [110.0, 130.81, 164.81, 220.0, 155.56].enumerated() {
                let ff = Float(f)
                c += sin(2 * .pi * ff * t) + sin(2 * .pi * ff * 1.004 * t) * 0.6 * Float(k % 2 == 0 ? 1 : -1)
            }
            s = c * env * 0.22
        case .clunk:
            s = sin(2 * .pi * 92 * t) * exp(-t * 24) + v.f1.lp(w, fc(400), 0.8) * exp(-t * 45) * 1.2
        case .breath:
            let inEnv = pow(max(0, sin(.pi * x)), 1.6)
            s = v.f2.lp(v.f1.bp(w, fc(650 + 400 * x), 1.1), fc(1500), 0.9) * inEnv * 1.6
        case .tick:
            let pitch = v.a == 0 ? 1 : v.a
            s = v.f1.bp(w * exp(-t * 450), fc(3300 * pitch), 0.2) * 1.4 + sin(2 * .pi * 1850 * pitch * t) * exp(-t * 160) * 0.35
        case .bird:
            let chirp: Float = 0.14
            let n = Int(t / chirp)
            let u = (t - Float(n) * chirp) / 0.08
            if n < v.count && u < 1 {
                let f = v.a * (1 + 0.45 * u) * (n % 2 == 0 ? 1 : 1.12)
                v.phase += f / sr
                if v.phase > 1 { v.phase -= 1 }
                s = sin(v.phase * 2 * .pi) * sin(.pi * u)
            }
        case .bootChime:
            let env = min(1, t / 0.04) * exp(-t * 1.0)
            var c: Float = 0
            for f in [174.61, 220.0, 261.63, 349.23, 523.25] as [Float] {
                c += sin(2 * .pi * f * t) + sin(2 * .pi * f * 2 * t) * 0.2 * exp(-t * 2)
            }
            s = c * env * 0.3
        case .flatline:
            s = sin(2 * .pi * 1000 * t) * min(1, t * 50) * (x > 0.9 ? (1 - x) * 10 : 1)
        }
        return (s * v.gain, done)
    }
}

/// Owns the audio engine and exposes the game-facing API.
final class Audio {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    let synth: Synth
    private var lastZap: CFTimeInterval = 0

    // game-facing parameters
    var drone: Float = 0 { didSet { synth.drone = drone } }
    var staticLevel: Float = 0 { didSet { synth.staticLevel = min(1, staticLevel + glitchStatic) } }
    var glitchStatic: Float = 0 { didSet { synth.staticLevel = min(1, staticLevel + glitchStatic) } }
    var master: Float = 0.8 { didSet { synth.master = master } }

    init() {
        let out = engine.outputNode.inputFormat(forBus: 0)
        let sr = out.sampleRate > 0 ? out.sampleRate : 48000
        synth = Synth(sampleRate: Float(sr))
        let stereo = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        source = AVAudioSourceNode(format: stereo) { [synth] _, _, frameCount, abl -> OSStatus in
            let b = UnsafeMutableAudioBufferListPointer(abl)
            guard b.count >= 2, let l = b[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = b[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(frames: Int(frameCount), left: l, right: r)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: stereo)
        engine.mainMixerNode.outputVolume = 0.9
        do { try engine.start() } catch { NSLog("Audio engine failed: \(error)") }
    }

    func play(_ s: SFX, gain: Float = 1, pan: Float? = nil, bypassMaster: Bool = false) {
        synth.trigger(s, gain: gain, pan: pan, bypassMaster: bypassMaster)
    }

    /// Rate-limited glitch zap.
    func zap(_ amount: Float) {
        let now = CACurrentMediaTime()
        guard now - lastZap > 0.25 else { return }
        lastZap = now
        play(.glitchZap, gain: min(1.2, amount))
    }

    func tick() { play(.ghostKey) }
    func keyClick() { play(.keyClick) }

    func beep() { NSSound.beep() }

    func systemSound(_ name: String) {
        guard master > 0.02, let s = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        s.volume = master
        s.play()
    }
}
