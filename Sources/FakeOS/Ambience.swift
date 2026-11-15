import Foundation

/// The room around the computer: decides what the synth plays from the state of the haunting.
/// 3:17 AM, light rain, a fridge next door, a laptop fan that never rests (until wren is killed),
/// and a house that gets less and less quiet.
final class Ambience {
    unowned let world: World
    private var next: [SFX: Float] = [:]
    private var fridgeTimer: Float = 70
    private var rain: Float = 0.45
    private var wind: Float = 0.3
    private var heart: Float = 0
    private var frozenTick: Float = 30

    init(world: World) {
        self.world = world
        for k in [SFX.creak, .footsteps, .car, .thunder, .meow, .knock, .breath, .whisper, .bird] {
            next[k] = Float.random(in: 8...30)
        }
    }

    private func due(_ k: SFX, _ dt: Float, every range: ClosedRange<Float>) -> Bool {
        let t = (next[k] ?? 10) - dt
        if t <= 0 {
            next[k] = Float.random(in: range)
            return true
        }
        next[k] = t
        return false
    }

    func update(_ dt: Float, onDesktop: Bool, panic: Bool) {
        let synth = world.audio.synth
        let story = world.story!
        let h = world.haunt
        let calm = world.calmLevel
        let blood = world.bloodLevel

        // silence while booting / after the crash
        let mute: Float = (onDesktop && !panic) ? 1 : 0
        synth.ambienceMute += (mute - synth.ambienceMute) * min(1, dt * 1.5)

        // continuous layers
        let rainTarget = max(0, (0.4 + 0.45 * h) * (1 - calm))
        rain += (rainTarget - rain) * min(1, dt * 0.2)
        synth.rain = rain
        let windTarget = max(0.05, 0.22 + 0.55 * h + 0.5 * blood - 0.15 * calm)
        wind += (windTarget - wind) * min(1, dt * 0.3)
        synth.wind = wind
        synth.room = 1
        if story.ended && story.goodEnding {
            synth.fanTarget = 0.04
        } else if blood > 0.1 {
            synth.fanTarget = 1
        } else {
            synth.fanTarget = story.wrenRunning ? 0.22 + 0.6 * h : 0.05
        }
        let typingPassword = world.windows.contains { ($0 as? AlertWindow)?.hasField == true && !$0.closing }
        var heartTarget = max(0, min(1, (h - 0.5) / 0.4)) + (typingPassword ? 0.35 : 0) + blood * 0.6
        if calm > 0.3 || panic { heartTarget = 0 }
        heart += (heartTarget - heart) * min(1, dt * 0.8)
        synth.heart = heart
        synth.clockRunning = story.clockRunning && onDesktop

        guard onDesktop, !panic else { return }

        // the fridge cycles on and off
        fridgeTimer -= dt
        if fridgeTimer <= 0 {
            synth.fridgeOn.toggle()
            fridgeTimer = synth.fridgeOn ? Float.random(in: 70...140) : Float.random(in: 40...80)
            if !synth.fridgeOn { world.audio.play(.clunk) }
        }

        let a = world.audio
        if story.ended && story.goodEnding {
            // dawn: birds, a cat, nothing else
            if calm > 0.5, due(.bird, dt, every: 1.5...5) { a.play(.bird, pan: Float.random(in: -0.9...0.9)) }
            if calm > 0.5, due(.meow, dt, every: 25...50) { a.play(.meow, gain: 1.4, pan: Float.random(in: -0.4...0.4)) }
            return
        }

        if due(.creak, dt, every: (18 / (1 + h))...(42 / (1 + h))) { a.play(.creak, gain: 0.7 + 0.5 * h) }
        if h > 0.25, due(.footsteps, dt, every: 45...100) { a.play(.footsteps, gain: 0.6 + 0.6 * h) }
        if due(.car, dt, every: (40 * (1 + h))...(90 * (1 + h))) { a.play(.car) }
        if rain > 0.6, due(.thunder, dt, every: 45...100) { a.play(.thunder, gain: 0.6 + 0.4 * h) }
        if due(.meow, dt, every: 100...200) { a.play(.meow, gain: 0.6, pan: Float.random(in: -1...(-0.5))) }
        if h > 0.55, due(.knock, dt, every: 55...120) { a.play(.knock, gain: 0.6 + 0.4 * h, pan: Float.random(in: -0.8...0.8)) }
        if h > 0.65, due(.breath, dt, every: 35...80) { a.play(.breath, gain: 0.7) }
        if h > 0.45, due(.whisper, dt, every: 30...70) { a.play(.whisper, gain: 0.5) }

        // the frozen clock tries to move, once in a while
        if !story.clockRunning {
            frozenTick -= dt
            if frozenTick <= 0 {
                frozenTick = Float.random(in: 20...55)
                a.play(.tick, gain: 0.8, pan: -0.35)
            }
        }
    }
}
