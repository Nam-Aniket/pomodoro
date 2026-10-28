import AVFoundation
import CoreAudio

/// Tomo's sounds, synthesized from physical models so nothing is downloaded or licensed (DESIGN.md section 6b).
/// Every play draws fresh randomness (pitch about ±4%, timing, which droplets), because a sound that repeats
/// identically is what makes a creature feel mechanical.
enum Sound {
    enum Cue: String, CaseIterable { case splash, ripe, start, nudge, hmmph, simmer, boil, siren, celebrate, park, inhale, exhale, tick }
    enum Presence: String, CaseIterable { case hum, pop, rustle }

    static let rate = 44_100.0
    nonisolated(unsafe) static var players: [AVAudioPlayer] = []

    static func play(_ cue: Cue) {
        if cue == .tick && (micInUse || systemMuted) { return }   // the tick has no model to ask, so it guards itself
        let seed = UInt64.random(in: 1...UInt64.max)
        play(palette.map { render(cue, palette: $0, seed: seed) } ?? render(cue, seed: seed), gain: 1)
    }
    static func play(_ p: Presence) { play(render(p, seed: .random(in: 1...UInt64.max)), gain: 0.65) }

    // MARK: the siren: one continuous wail, looped seamlessly for as long as the siren stage lasts

    nonisolated(unsafe) static var sirenPlayer: AVAudioPlayer?

    /// A real siren's wail (the pitch sliding smoothly up and down, never stopping), made cute: a round tone
    /// instead of a harsh square wave, a little vibrato, and Tomo's "ooo" an octave below. Exactly two
    /// sweeps long, with the phase closed at the end, so the loop has no seam.
    static func sirenLoop() -> [Float] {
        let cycle = 2.4, n = Int(rate * cycle * 2), warm = Int(rate * cycle)
        var out = [Float](repeating: 0, count: n + warm)   // one extra sweep warms the filter, then is dropped
        var phase = 0.0, phase2 = 0.0
        var oo = Biquad(bandpass: 420, q: 4)
        for j in 0..<(n + warm) {
            let t = Double(j) / rate
            let sweep = 0.5 - 0.5 * cos(2 * .pi * t / cycle)                 // 0 → 1 → 0, smooth at both ends
            let f = (640 + 520 * sweep) * (1 + 0.006 * sin(2 * .pi * 6.25 * t))   // 6.25 Hz: whole wobbles per loop
            phase += 2 * .pi * f / rate; phase2 += 2 * .pi * f / 2 / rate
            let tone = sin(phase) + 0.22 * sin(2 * phase) + 0.06 * sin(3 * phase)
            var buzz = 0.0
            for h in 1...8 { buzz += sin(phase2 * Double(h)) / pow(Double(h), 1.2) }
            out[j] = Float(0.55 * tone + 0.35 * oo.run(buzz))
        }
        let loop = Array(out[warm...])
        let m = loop.map(abs).max() ?? 1   // normalize only: no fades, they would put a gap in the loop
        return loop.map { $0 / m * 0.45 }
    }

    static func startSiren() {
        guard sirenPlayer == nil, !UserDefaults.standard.bool(forKey: "soundMuted"),
              let p = try? AVAudioPlayer(data: wav(sirenLoop())) else { return }
        p.numberOfLoops = -1
        p.volume = Float(UserDefaults.standard.object(forKey: "soundVolume") as? Double ?? 0.7) * 0.8
        p.play(); sirenPlayer = p
    }

    static func stopSiren() { sirenPlayer?.stop(); sirenPlayer = nil }

    static func play(_ samples: [Float], gain: Float) {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "soundMuted"), let p = try? AVAudioPlayer(data: wav(samples)) else { return }
        p.volume = Float(d.object(forKey: "soundVolume") as? Double ?? 0.7) * gain
        players.removeAll { !$0.isPlaying }
        players.append(p); p.play()
    }

    // MARK: guards (no permission needed: these read device state, never audio)

    static func property(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32 {
        var v: UInt32 = 0, size = UInt32(4)
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr ? v : 0
    }

    static func device(_ sel: AudioObjectPropertySelector) -> AudioObjectID {
        var id = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    /// Any app recording (calls, SpeakFit, dictation). Built-in and wired mics only: Bluetooth mics don't report it.
    static var micInUse: Bool {
        property(device(kAudioHardwarePropertyDefaultInputDevice), kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal) != 0
    }

    static var systemMuted: Bool {
        property(device(kAudioHardwarePropertyDefaultOutputDevice), kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput) != 0
    }

    // MARK: building blocks

    struct RNG {
        var s: UInt64
        mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
        mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    }

    /// RBJ cookbook biquad: band-pass for formants and squelch, low-pass for warmth.
    struct Biquad {
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0, x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        init(bandpass f: Double, q: Double) { set(bandpass: f, q: q) }
        init(lowpass f: Double, q: Double = 0.707) { set(lowpass: f, q: q) }
        mutating func set(lowpass f: Double, q: Double = 0.707) {
            let w = 2 * .pi * f / Sound.rate, al = sin(w) / (2 * q), a0 = 1 + al
            b0 = (1 - cos(w)) / 2 / a0; b1 = (1 - cos(w)) / a0; b2 = b0; a1 = -2 * cos(w) / a0; a2 = (1 - al) / a0
        }
        mutating func set(bandpass f: Double, q: Double) {
            let w = 2 * .pi * f / Sound.rate, al = sin(w) / (2 * q), a0 = 1 + al
            b0 = al / a0; b1 = 0; b2 = -al / a0; a1 = -2 * cos(w) / a0; a2 = (1 - al) / a0
        }
        mutating func run(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y; return y
        }
    }

    /// Raised-cosine attack and release: no clicks at either end.
    static func env(_ t: Double, _ dur: Double, attack: Double, release: Double) -> Double {
        if t < 0 || t > dur { return 0 }
        if t < attack { return 0.5 - 0.5 * cos(.pi * t / attack) }
        if t > dur - release { return 0.5 - 0.5 * cos(.pi * (dur - t) / release) }
        return 1
    }

    /// A drop landing: the trapped air bubble rings with a pitch that rises as it dies (Minnaert resonance).
    static func bubble(_ out: inout [Float], at: Double, f0: Double, tau: Double, amp: Double) {
        let s0 = Int(at * rate); var phase = 0.0
        for j in 0..<Int(tau * 6 * rate) where s0 + j < out.count && s0 + j >= 0 {
            let t = Double(j) / rate
            phase += 2 * .pi * f0 * (1 + 1.6 * t / tau) / rate
            out[s0 + j] += Float(amp * sin(phase) * exp(-t / tau) * min(1, t / 0.002))
        }
    }

    /// A tiny voice: a soft glottal buzz shaped by mouth resonances (formants), plus breath.
    /// Nasal "mm" uses a low first formant and a weak upper one; open vowels raise them.
    static func voice(_ out: inout [Float], at: Double, dur: Double, pitch: (Double) -> Double,
                      formants: [(f: Double, q: Double, g: Double)], breath: Double, amp: Double, rng: inout RNG) {
        var filters = formants.map { Biquad(bandpass: $0.f, q: $0.q) }
        var warm = Biquad(lowpass: 3200)
        let s0 = Int(at * rate); var phase = 0.0
        for j in 0..<Int(dur * rate) where s0 + j < out.count {
            let t = Double(j) / rate
            let f = pitch(t / dur) * (1 + 0.006 * sin(2 * .pi * 5.5 * t)) * (1 + 0.004 * (rng.next() - 0.5))
            phase += 2 * .pi * f / rate
            var src = 0.0
            for h in 1...14 where Double(h) * f < 4500 { src += sin(phase * Double(h)) / pow(Double(h), 1.3) }
            src += breath * (rng.next() * 2 - 1)
            var y = 0.0
            for i in filters.indices { y += formants[i].g * filters[i].run(src) }
            out[s0 + j] += Float(amp * warm.run(y) * env(t, dur, attack: min(0.06, dur * 0.3), release: min(0.09, dur * 0.4)))
        }
    }

    /// A ripe fruit squeezed: noise through a resonance that sweeps down, like a wet squelch.
    static func squelch(_ out: inout [Float], at: Double, dur: Double, from: Double, to: Double, amp: Double, rng: inout RNG) {
        var bp = Biquad(bandpass: from, q: 4)
        let s0 = Int(at * rate)
        for j in 0..<Int(dur * rate) where s0 + j < out.count {
            let t = Double(j) / rate, k = t / dur
            if j % 32 == 0 { bp.set(bandpass: from * pow(to / from, k), q: 4) }
            out[s0 + j] += Float(amp * bp.run(rng.next() * 2 - 1) * env(t, dur, attack: 0.008, release: dur * 0.6))
        }
    }

    /// Leaves brushing: short bursts of airy high noise with crackle.
    static func rustle(_ out: inout [Float], at: Double, dur: Double, amp: Double, rng: inout RNG) {
        var bp = Biquad(bandpass: 2900, q: 1.1)
        let s0 = Int(at * rate)
        for j in 0..<Int(dur * rate) where s0 + j < out.count {
            let t = Double(j) / rate
            let crackle = rng.next() < 0.004 ? rng.range(2, 5) : 1
            out[s0 + j] += Float(amp * crackle * bp.run(rng.next() * 2 - 1) * env(t, dur, attack: 0.03, release: dur * 0.5) * (0.6 + 0.4 * sin(t * 37)))
        }
    }

    /// A soft wooden bar (marimba-like): warm fundamental, quickly fading overtones at 3.9x and 9.2x.
    static func wood(_ out: inout [Float], at: Double, f: Double, amp: Double) {
        let s0 = Int(at * rate)
        for j in 0..<Int(1.2 * rate) where s0 + j < out.count {
            let t = Double(j) / rate
            let v = sin(2 * .pi * f * t) * exp(-t / 0.45) + 0.25 * sin(2 * .pi * f * 3.9 * t) * exp(-t / 0.08) + 0.08 * sin(2 * .pi * f * 9.2 * t) * exp(-t / 0.03)
            out[s0 + j] += Float(amp * v * min(1, t / 0.004))
        }
    }

    // MARK: the sounds

    static let nasal: [(f: Double, q: Double, g: Double)] = [(260, 5, 1), (1050, 9, 0.18), (2600, 10, 0.05)]

    /// Breath sounds fit the 6 s cyclic sigh (TomoArt.breath): in 1.8 s plus a 0.7 s top-up, out 3.5 s.
    static func breathLength(_ cue: Cue) -> Double { cue == .inhale ? 2.5 : cue == .exhale ? 3.4 : 0 }

    static func render(_ cue: Cue, seed: UInt64) -> [Float] {
        var rng = RNG(s: seed)
        let p = rng.range(0.96, 1.04)
        // sized per cue: the breath sounds run longer than 1.9 s, and writing past a 1.9 s buffer crashed every
        // breathing break with sound on, from 0.3 to 0.5.2 (crash reports 23 and 24 Oct)
        var out = [Float](repeating: 0, count: Int(rate * max(1.9, breathLength(cue))))
        switch cue {
        case .splash:
            // wet plop, a squelch, then droplets pattering down
            bubble(&out, at: 0.01, f0: 380 * p, tau: 0.05, amp: 0.7)
            squelch(&out, at: 0, dur: 0.22, from: 1400 * p, to: 300, amp: 2.2, rng: &rng)
            for _ in 0..<Int(rng.range(10, 15)) {
                bubble(&out, at: rng.range(0.06, 0.75), f0: rng.range(650, 1700) * p, tau: rng.range(0.018, 0.04), amp: rng.range(0.08, 0.22))
            }
        case .ripe:
            bubble(&out, at: 0.02, f0: 820 * p, tau: 0.03, amp: 0.4)
            rustle(&out, at: 0, dur: 0.25, amp: 0.25, rng: &rng)
            wood(&out, at: 0.12, f: 523 * p, amp: 0.45); wood(&out, at: 0.3, f: 784 * p, amp: 0.38)
        case .start:
            // a little "hup!" as Tomo hops
            voice(&out, at: 0.02, dur: 0.15, pitch: { 330 * p * (1 + 0.25 * $0) }, formants: [(640, 6, 1), (1150, 8, 0.5), (2500, 10, 0.12)], breath: 0.35, amp: 0.5, rng: &rng)
            squelch(&out, at: 0.2, dur: 0.12, from: 900 * p, to: 400, amp: 1.0, rng: &rng)
        case .nudge:
            voice(&out, at: 0.02, dur: 0.26, pitch: { 260 * p * (1 + 0.35 * $0 * $0) }, formants: nasal, breath: 0.12, amp: 0.55, rng: &rng)
        case .hmmph:
            voice(&out, at: 0.02, dur: 0.34, pitch: { 300 * p * (1 - 0.3 * $0) }, formants: nasal, breath: 0.15, amp: 0.6, rng: &rng)
            squelch(&out, at: 0.33, dur: 0.1, from: 2400, to: 1600, amp: 0.6, rng: &rng)   // the "ph" breath puff
        case .simmer:
            // a kettle starting: slow, low bubbles and a rising grumble
            for _ in 0..<9 { bubble(&out, at: rng.range(0, 0.9), f0: rng.range(220, 420) * p, tau: rng.range(0.03, 0.06), amp: rng.range(0.15, 0.3)) }
            voice(&out, at: 0.05, dur: 0.6, pitch: { 170 * p * (1 + 0.15 * $0) }, formants: [(500, 4, 1), (900, 6, 0.4)], breath: 0.35, amp: 0.4, rng: &rng)
        case .boil:
            for _ in 0..<26 { bubble(&out, at: rng.range(0, 1.3), f0: rng.range(250, 700) * p, tau: rng.range(0.02, 0.05), amp: rng.range(0.1, 0.3)) }
            var lp = Biquad(lowpass: 220)
            for j in 0..<Int(1.4 * rate) { out[j] += Float(0.5 * lp.run(rng.next() * 2 - 1) * env(Double(j) / rate, 1.4, attack: 0.2, release: 0.5)) }
        case .siren:
            // Tomo's own voice doing "wee-woo" twice: alarming, but still a creature, not a car alarm
            for i in 0..<4 {
                let hi = i % 2 == 0
                voice(&out, at: Double(i) * 0.4, dur: 0.38, pitch: { (hi ? 620 : 470) * p * (1 + (hi ? 0.08 : -0.06) * $0) },
                      formants: hi ? [(380, 6, 1), (2300, 9, 0.4), (3000, 10, 0.1)] : [(450, 6, 1), (900, 8, 0.6), (2500, 10, 0.08)],
                      breath: 0.1, amp: 0.55, rng: &rng)
            }
        case .celebrate:
            for (i, f) in [523.0, 659, 784, 1047].enumerated() { wood(&out, at: Double(i) * 0.11, f: f * p, amp: 0.35) }
            for i in 0..<3 {
                voice(&out, at: 0.5 + Double(i) * 0.13, dur: 0.1, pitch: { (420 + 30 * Double(i)) * p * (1 + 0.1 * $0) },
                      formants: [(450, 6, 1), (2000, 9, 0.35), (2800, 10, 0.1)], breath: 0.5, amp: 0.38, rng: &rng)
            }
            for _ in 0..<6 { bubble(&out, at: rng.range(0.1, 1.0), f0: rng.range(900, 1600), tau: 0.025, amp: 0.12) }
        case .tick:
            // the dial's detent: a tiny wooden click with a hint of juice
            bubble(&out, at: 0, f0: 1900 * p, tau: 0.006, amp: 0.5)
            squelch(&out, at: 0, dur: 0.012, from: 3000, to: 2400, amp: 0.6, rng: &rng)
            return finish(Array(out.prefix(Int(rate * 0.05))), peak: 0.22)
        case .inhale:
            // in through the nose (26 Oct: "proper breathing sound inhale and exhale"): a bright, narrow hiss that
            // rises in pitch as the lungs fill, then a short sharper sniff for the top-up, matching the motion
            var bp = Biquad(bandpass: 1800, q: 1.4)
            for j in 0..<Int(2.5 * rate) {
                let t = Double(j) / rate
                let (a, f) = t < 1.75 ? (env(t, 1.75, attack: 0.35, release: 0.25), 1500 + 900 * t / 1.75)
                                      : (1.15 * env(t - 1.8, 0.65, attack: 0.06, release: 0.3), 2600.0)
                if j % 64 == 0 { bp.set(bandpass: f, q: 1.4) }
                out[j] += Float(a * bp.run(rng.next() * 2 - 1))
            }
            return finish(out, peak: 0.3)
        case .exhale:
            // out through the mouth: a long, low, breathy "haaah" (noise through an "ah" mouth shape), loud at once
            // and fading as the air runs out, its brightness falling with it
            var f1 = Biquad(bandpass: 700, q: 3), f2 = Biquad(bandpass: 1150, q: 4), lp = Biquad(lowpass: 1400)
            let dur = 3.4
            for j in 0..<Int(dur * rate) {
                let t = Double(j) / rate, k = t / dur
                if j % 64 == 0 { lp.set(lowpass: 1400 - 900 * k) }
                let n = rng.next() * 2 - 1
                let a = env(t, dur, attack: 0.12, release: 0.6) * (1 - 0.65 * k)
                out[j] += Float(a * lp.run(f1.run(n) + 0.6 * f2.run(n) + 0.25 * n))
            }
            return finish(out, peak: 0.34)
        case .park:
            rustle(&out, at: 0, dur: 0.3, amp: 0.3, rng: &rng)
            squelch(&out, at: 0.05, dur: 0.1, from: 1200 * p, to: 700, amp: 0.7, rng: &rng)
        }
        return finish(out, peak: 0.55)
    }

    static func render(_ presence: Presence, seed: UInt64) -> [Float] {
        var rng = RNG(s: seed)
        let p = rng.range(0.95, 1.05)
        var out = [Float](repeating: 0, count: Int(rate * 0.7))
        switch presence {
        case .hum:
            // a contented little "mm" with a gentle rise and fall
            let up = rng.range(0.05, 0.2)
            voice(&out, at: 0.01, dur: rng.range(0.32, 0.5), pitch: { 240 * p * (1 + up * sin($0 * .pi)) }, formants: nasal, breath: 0.08, amp: 0.5, rng: &rng)
        case .pop:
            bubble(&out, at: 0.01, f0: rng.range(1100, 1500), tau: 0.02, amp: 0.4)
        case .rustle:
            rustle(&out, at: 0, dur: rng.range(0.25, 0.4), amp: 0.35, rng: &rng)
        }
        return finish(out, peak: 0.3)
    }

    /// Trim trailing silence, warm the top end, fade both ends (no clicks, ever), normalize.
    static func finish(_ x: [Float], peak: Float) -> [Float] {
        var lp = Biquad(lowpass: 5000)
        var y = x.map { Float(lp.run(Double($0))) }
        while let last = y.last, abs(last) < 1e-4, y.count > 1000 { y.removeLast() }
        let fadeIn = Int(0.003 * rate), fadeOut = min(y.count / 4, Int(0.04 * rate))
        for i in 0..<min(fadeIn, y.count) { y[i] *= Float(i) / Float(fadeIn) }
        for i in 0..<fadeOut { y[y.count - 1 - i] *= Float(i) / Float(fadeOut) }
        let m = y.map(abs).max() ?? 1
        return m > 0 ? y.map { $0 / m * peak } : y
    }

    static func wav(_ x: [Float]) -> Data {
        var d = Data()
        func put<T>(_ v: T) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
        let bytes = UInt32(x.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + bytes).littleEndian); d.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16).littleEndian); put(UInt16(1).littleEndian); put(UInt16(1).littleEndian)
        put(UInt32(rate).littleEndian); put(UInt32(rate * 2).littleEndian); put(UInt16(2).littleEndian); put(UInt16(16).littleEndian)
        d.append(contentsOf: Array("data".utf8)); put(bytes.littleEndian)
        for s in x { put(Int16(max(-1, min(1, s)) * 32767).littleEndian) }
        return d
    }
}
