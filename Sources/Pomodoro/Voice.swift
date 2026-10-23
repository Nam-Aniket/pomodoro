import Foundation

/// Tomo's voice: one character, three candidate palettes (DESIGN.md section 6c). Identity, whatever the palette:
/// pitch centred near 520 Hz (higher than a person, like a small creature), soft rounded timbre, short syllables
/// (~80 ms), rising contours when happy or curious, falling when grumpy or sleepy, a little different every play.
/// Pitch follows mood the way Animal Crossing's Animalese does: happy sounds higher, cross sounds lower.
extension Sound {
    enum Palette: String, CaseIterable { case mix, voice, boops, juicy }

    /// Default: the mix (A babble voice for feelings + C juicy foley for physical moments).
    static var palette: Palette? { Palette(rawValue: UserDefaults.standard.string(forKey: "soundPalette") ?? "mix") }

    /// Vowel mouth shapes (first two formants), raised about 25% for a small creature's shorter "mouth".
    static let vowels: [(f1: Double, f2: Double)] = [(1000, 1500), (620, 2350), (400, 2800), (620, 1100), (440, 1000)]

    /// Babble: a few syllables of Tomo-speak. `contour` maps 0...1 through the phrase to a pitch multiplier.
    static func babble(_ out: inout [Float], at: Double, syllables n: Int, base: Double, contour: (Double) -> Double,
                       gap: Double = 0.025, len: ClosedRange<Double> = 0.07...0.1, amp: Double = 0.5, rng: inout RNG) {
        var t = at
        for k in 0..<n {
            let v = vowels[Int(rng.next() * Double(vowels.count)) % vowels.count]
            let d = rng.range(len.lowerBound, len.upperBound)
            let p0 = base * contour(Double(k) / Double(max(1, n - 1))) * rng.range(0.97, 1.03)
            // a soft consonant onset now and then ("t" or "p" as a tiny breath click)
            if rng.next() < 0.5 { squelch(&out, at: t, dur: 0.012, from: 3200, to: 2600, amp: 0.35, rng: &rng) }
            voice(&out, at: t + 0.006, dur: d, pitch: { p0 * (1 + 0.05 * $0) }, formants: [(v.f1, 5, 1), (v.f2, 8, 0.45), (3300, 10, 0.08)],
                  breath: 0.18, amp: amp, rng: &rng)
            t += d + gap
        }
    }

    /// A rounded "boop": nearly a pure tone with a soft second harmonic and a tiny pitch drop at the start, like
    /// a soft mallet on a small wooden key.
    static func boop(_ out: inout [Float], at: Double, f: Double, dur: Double = 0.22, amp: Double = 0.5) {
        let s0 = Int(at * rate); var phase = 0.0
        for j in 0..<Int(dur * rate) where s0 + j < out.count {
            let t = Double(j) / rate
            phase += 2 * .pi * f * (1 + 0.04 * exp(-t / 0.015)) / rate
            let v = sin(phase) + 0.18 * sin(2 * phase) + 0.05 * sin(4 * phase) * exp(-t / 0.03)
            out[s0 + j] += Float(amp * v * exp(-t / (dur * 0.45)) * min(1, t / 0.004))
        }
    }

    /// Pentatonic steps above C5: every combination sounds sweet, never sour.
    static func note(_ step: Int) -> Double {
        let pent = [0, 2, 4, 7, 9]
        let oct = Int(floor(Double(step) / 5)), idx = ((step % 5) + 5) % 5
        return 523.25 * pow(2, Double(oct * 12 + pent[idx]) / 12)
    }

    /// A juicy pop: a fat drop with a quick squish under it.
    static func juicyPop(_ out: inout [Float], at: Double, f: Double, amp: Double = 0.5, rng: inout RNG) {
        bubble(&out, at: at, f0: f, tau: 0.035, amp: amp)
        squelch(&out, at: at, dur: 0.05, from: f * 2.2, to: f * 1.2, amp: amp * 0.9, rng: &rng)
    }

    static func render(_ cue: Cue, palette: Palette, seed: UInt64) -> [Float] {
        if palette == .mix && cue != .inhale && cue != .exhale {
            // the voice says how Tomo feels; the juice says what physically happens, a touch quieter underneath
            let a = render(cue, palette: .voice, seed: seed), c = render(cue, palette: .juicy, seed: seed &+ 77)
            var out = [Float](repeating: 0, count: max(a.count, c.count))
            for i in a.indices { out[i] += a[i] }
            for i in c.indices { out[i] += 0.6 * c[i] }
            return finish(out, peak: 0.5)
        }
        var rng = RNG(s: seed)
        let p = rng.range(0.96, 1.04)
        var out = [Float](repeating: 0, count: Int(rate * 2))
        let base = 520 * p
        switch (palette, cue) {
        // A. Babble voice: Tomo talks in tiny syllables
        case (.voice, .start): babble(&out, at: 0, syllables: 3, base: base, contour: { 1 + 0.35 * $0 }, rng: &rng)            // "ta-da-da!"
        case (.voice, .nudge): babble(&out, at: 0, syllables: 1, base: base * 0.95, contour: { _ in 1 }, len: 0.16...0.18, rng: &rng)
            voice(&out, at: 0.16, dur: 0.14, pitch: { base * (1.05 + 0.4 * $0) }, formants: [(440, 5, 1), (1000, 8, 0.4)], breath: 0.1, amp: 0.45, rng: &rng) // "oo?"
        case (.voice, .hmmph):
            voice(&out, at: 0, dur: 0.22, pitch: { base * 0.72 * (1 - 0.15 * $0) }, formants: nasal, breath: 0.1, amp: 0.6, rng: &rng)
            voice(&out, at: 0.25, dur: 0.12, pitch: { _ in base * 0.62 }, formants: nasal, breath: 0.25, amp: 0.5, rng: &rng)          // "hm-mph"
        case (.voice, .simmer): voice(&out, at: 0, dur: 0.5, pitch: { base * 0.55 * (1 + 0.12 * sin($0 * 9)) }, formants: [(500, 5, 1), (900, 7, 0.4)], breath: 0.3, amp: 0.5, rng: &rng)  // "grrr"
        case (.voice, .boil): babble(&out, at: 0, syllables: 8, base: base * 0.7, contour: { 1 + 0.1 * sin($0 * 12) }, gap: 0.01, len: 0.05...0.07, amp: 0.55, rng: &rng)
        case (.voice, .siren):
            for i in 0..<4 { voice(&out, at: Double(i) * 0.36, dur: 0.33, pitch: { _ in base * (i % 2 == 0 ? 1.25 : 0.95) }, formants: [(400, 6, 1), (2400, 9, 0.4)], breath: 0.08, amp: 0.55, rng: &rng) }
        case (.voice, .splash):
            juicyPop(&out, at: 0, f: 420 * p, amp: 0.7, rng: &rng)
            babble(&out, at: 0.18, syllables: 2, base: base * 1.2, contour: { 1 + 0.5 * $0 }, len: 0.1...0.14, rng: &rng)        // "whee!"
        case (.voice, .ripe):
            juicyPop(&out, at: 0, f: 900 * p, amp: 0.4, rng: &rng)
            babble(&out, at: 0.12, syllables: 2, base: base * 1.1, contour: { 1 + 0.25 * $0 }, rng: &rng)                       // "hi-hi!"
        case (.voice, .celebrate): babble(&out, at: 0, syllables: 6, base: base * 1.1, contour: { 1 + 0.4 * $0 + 0.08 * sin($0 * 20) }, gap: 0.015, rng: &rng)
            babble(&out, at: 0.7, syllables: 3, base: base * 1.35, contour: { _ in 1 }, len: 0.05...0.06, rng: &rng)          // giggle
        case (.voice, .park): voice(&out, at: 0, dur: 0.2, pitch: { base * (1 + 0.2 * $0) }, formants: nasal, breath: 0.08, amp: 0.5, rng: &rng)  // "mm!"

        // B. Musical boops: Tomo sings in a soft pentatonic
        case (.boops, .start): for (i, s) in [0, 2, 4].enumerated() { boop(&out, at: Double(i) * 0.09, f: note(s) * p) }
        case (.boops, .nudge): boop(&out, at: 0, f: note(2) * p); boop(&out, at: 0.12, f: note(4) * p * 1.03, dur: 0.3)
        case (.boops, .hmmph): boop(&out, at: 0, f: note(-2) * p, dur: 0.18); boop(&out, at: 0.16, f: note(-4) * p, dur: 0.3)
        case (.boops, .simmer): for i in 0..<4 { boop(&out, at: Double(i) * 0.14, f: note(-4 + (i % 2)) * p, dur: 0.16, amp: 0.4) }
        case (.boops, .boil): for i in 0..<10 { boop(&out, at: Double(i) * 0.08, f: note(-5 + (i % 3)) * p * rng.range(0.97, 1.03), dur: 0.12, amp: 0.45) }
        case (.boops, .siren): for i in 0..<4 { boop(&out, at: Double(i) * 0.36, f: note(i % 2 == 0 ? 7 : 4) * p, dur: 0.34) }
        case (.boops, .splash): for i in 0..<6 { boop(&out, at: Double(i) * 0.06, f: note(9 - i * 2) * p, dur: 0.16, amp: 0.4) }
            bubble(&out, at: 0.4, f0: 700, tau: 0.04, amp: 0.3)
        case (.boops, .ripe): boop(&out, at: 0, f: note(4) * p); boop(&out, at: 0.15, f: note(7) * p, dur: 0.45)
        case (.boops, .celebrate): for (i, s) in [0, 2, 4, 5, 7, 9, 10].enumerated() { boop(&out, at: Double(i) * 0.08, f: note(s) * p, dur: 0.3, amp: 0.42) }
        case (.boops, .park): boop(&out, at: 0, f: note(5) * p, dur: 0.16); boop(&out, at: 0.08, f: note(3) * p, dur: 0.22, amp: 0.35)

        // C. Juicy foley: squishes, pops and bubbles shaped like little moods
        case (.juicy, .start): for i in 0..<3 { juicyPop(&out, at: Double(i) * 0.1, f: (520 + Double(i) * 160) * p, rng: &rng) }
        case (.juicy, .nudge): squelch(&out, at: 0, dur: 0.18, from: 600 * p, to: 1500 * p, amp: 1.4, rng: &rng)       // a rising squish: "hm?"
        case (.juicy, .hmmph): squelch(&out, at: 0, dur: 0.26, from: 900 * p, to: 260, amp: 1.6, rng: &rng)            // a sulky low squelch
            bubble(&out, at: 0.24, f0: 300, tau: 0.05, amp: 0.4)
        case (.juicy, .simmer): for _ in 0..<8 { juicyPop(&out, at: rng.range(0, 0.9), f: rng.range(240, 420) * p, amp: rng.range(0.2, 0.35), rng: &rng) }
        case (.juicy, .boil): for _ in 0..<22 { juicyPop(&out, at: rng.range(0, 1.2), f: rng.range(280, 620) * p, amp: rng.range(0.25, 0.45), rng: &rng) }
        case (.juicy, .siren): for i in 0..<4 { squelch(&out, at: Double(i) * 0.36, dur: 0.32, from: i % 2 == 0 ? 900 : 1500, to: i % 2 == 0 ? 1500 : 900, amp: 1.4, rng: &rng) }
        case (.juicy, .splash): return render(.splash, seed: seed)
        case (.juicy, .ripe): juicyPop(&out, at: 0, f: 820 * p, rng: &rng); rustle(&out, at: 0.05, dur: 0.25, amp: 0.25, rng: &rng)
        case (.juicy, .celebrate): for i in 0..<8 { juicyPop(&out, at: Double(i) * 0.09, f: (500 + Double(i) * 90) * p, amp: 0.45, rng: &rng) }
        case (.juicy, .park): rustle(&out, at: 0, dur: 0.25, amp: 0.3, rng: &rng); juicyPop(&out, at: 0.12, f: 700 * p, amp: 0.35, rng: &rng)

        case (.mix, _): return []
        // breath cues stay the same soft air in every palette
        case (_, .inhale), (_, .exhale): return render(cue, seed: seed)
        }
        return finish(out, peak: 0.5)
    }

    /// `Pomodoro --reels <dir>`: one demo reel per palette, the same moments in the same order.
    static func reels(to dir: URL) {
        let order: [Cue] = [.start, .nudge, .hmmph, .simmer, .boil, .splash, .ripe, .celebrate, .park]
        for pal in Palette.allCases {
            var reel: [Float] = []
            for (i, c) in order.enumerated() {
                for take in 0..<2 {   // two takes each, so the variation is audible
                    reel += render(c, palette: pal, seed: UInt64(1000 + i * 31 + take * 7))
                    reel += [Float](repeating: 0, count: Int(rate * (take == 0 ? 0.35 : 0.9)))
                }
            }
            reel += sirenLoop() + sirenLoop()   // the siren loops seamlessly in every palette
            try? wav(reel).write(to: dir.appendingPathComponent("reel-\(["mix": "AC-mix", "voice": "A-babble-voice", "boops": "B-musical-boops", "juicy": "C-juicy-foley"][pal.rawValue]!).wav"))
        }
    }
}
