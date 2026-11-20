//  BuiltInPresets.swift
//  GtrBoard
//
//  Factory rig presets. Each one is a complete board snapshot modelled on a
//  well-known guitar rig; the `gear` field names the reference equipment and
//  `notes` explains the intent so the preset browser teaches while it plays.
//
//  Values are deliberate starting points, not measurements of the original
//  hardware. The amps/pedals in this app are original DSP voiced to feel like
//  the classics, so these presets are the fastest way to get into that
//  territory and then twist the knobs.

import Foundation

public enum BuiltInPresets {
    /// Fixed timestamp so factory preset identity is stable across launches.
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    public static let all: [Preset] = balanced([
        rig(
            name: "Studio Clean",
            gear: "Clean valve amp · compressor · room reverb",
            tags: ["clean", "studio", "pop"],
            notes: "A polished clean tone with a gentle compressor and a short room. The default starting point for pedal testing.",
            units: [
                unit(.compressor, ["threshold": -22, "ratio": 3, "attack": 15, "release": 200, "makeup": 4]),
                unit(.amp, ["voicing": 0, "gain": 6, "bass": 1, "mid": 0.5, "treble": 1.5, "presence": 3, "master": -6]),
                unit(.cabinet, ["lowCut": 80, "highCut": 6_000, "resonance": 3]),
                unit(.reverb, ["size": 0.35, "damping": 0.5, "mix": 0.15, "predelay": 15, "mode": 0])
            ]
        ),
        rig(
            name: "Sultans of Swing",
            gear: "Strat · Fender Vibrolux · compressor",
            tags: ["clean", "blues", "dire-straits"],
            notes: "Mark Knopfler's in-between clean: compressor up front, amp just at the edge of breakup, almost no reverb. Play with your fingers and the amp does the rest.",
            units: [
                unit(.compressor, ["threshold": -20, "ratio": 2.5, "attack": 20, "release": 250, "makeup": 3]),
                unit(.amp, ["voicing": 0, "gain": 9, "bass": 1, "mid": 1, "treble": 2, "presence": 4, "master": -7]),
                unit(.cabinet, ["lowCut": 90, "highCut": 5_500, "resonance": 4]),
                unit(.reverb, ["size": 0.3, "damping": 0.55, "mix": 0.12, "predelay": 12, "mode": 0])
            ]
        ),
        rig(
            name: "Little Wing",
            gear: "Strat · clean amp · slow phaser · hall",
            tags: ["clean", "blues", "hendrix"],
            notes: "Woodstock-era clean with a slow, deep phase sweep standing in for the Uni-Vibe and a wide hall behind it.",
            units: [
                unit(.compressor, ["threshold": -24, "ratio": 2, "attack": 25, "release": 220, "makeup": 3]),
                unit(.amp, ["voicing": 0, "gain": 7, "bass": 2, "mid": 0.5, "treble": 2.5, "presence": 5, "master": -8]),
                unit(.cabinet, ["lowCut": 85, "highCut": 6_000, "resonance": 3]),
                unit(.phaser, ["rate": 0.18, "depth": 0.35, "feedback": 0.15, "mix": 0.25, "stages": 0]),
                unit(.reverb, ["size": 0.5, "damping": 0.45, "mix": 0.22, "predelay": 22, "mode": 1])
            ]
        ),
        rig(
            name: "Texas Flood",
            gear: "Strat · TS-808 → clean Fender · room",
            tags: ["blues", "lead", "srv"],
            notes: "Tube Screamer with the drive around noon into a loud clean Fender: the classic SRV mid-hump lead. Roll the guitar volume back for rhythm.",
            units: [
                unit(.overdrive, ["drive": 20, "tone": 0.5, "level": -5, "mid": 0.75]),
                unit(.amp, ["voicing": 0, "gain": 10, "bass": 1, "mid": 1, "treble": 1.5, "presence": 4, "master": -8]),
                unit(.cabinet, ["lowCut": 90, "highCut": 5_500, "resonance": 4]),
                unit(.reverb, ["size": 0.3, "damping": 0.5, "mix": 0.18, "predelay": 15, "mode": 0])
            ]
        ),
        rig(
            name: "Slow Dancing",
            gear: "Strat · low-gain OD · analog delay",
            tags: ["blues", "lead", "mayer"],
            notes: "Edge-of-breakup overdrive with a dark analog echo. Great for neck-pickup lines where the note blooms into feedback.",
            units: [
                unit(.compressor, ["threshold": -26, "ratio": 2, "attack": 30, "release": 250, "makeup": 3]),
                unit(.overdrive, ["drive": 14, "tone": 0.45, "level": -7, "mid": 0.65]),
                unit(.amp, ["voicing": 1, "gain": 14, "bass": 1, "mid": 1, "treble": 1, "presence": 3, "master": -10]),
                unit(.cabinet, ["lowCut": 90, "highCut": 5_200, "resonance": 4]),
                unit(.delay, ["time": 420, "feedback": 0.28, "mix": 0.18, "tone": 0.4, "mode": 1]),
                unit(.reverb, ["size": 0.45, "damping": 0.5, "mix": 0.2, "predelay": 25, "mode": 1])
            ]
        ),
        rig(
            name: "Plexi Crunch",
            gear: "Marshall Plexi · 4×12 cabinet",
            tags: ["crunch", "classic-rock"],
            notes: "Non-master-volume British crunch: everything on the amp, guitar volume does the cleaning up. Mid-forward and percussive.",
            units: [
                unit(.amp, ["voicing": 1, "gain": 24, "bass": 1, "mid": 2, "treble": 1, "presence": 5, "master": -11]),
                unit(.cabinet, ["lowCut": 85, "highCut": 5_200, "resonance": 4]),
                unit(.reverb, ["size": 0.3, "damping": 0.6, "mix": 0.08, "predelay": 10, "mode": 0])
            ]
        ),
        rig(
            name: "Back in Black",
            gear: "Marshall JCM800 · Gretsch",
            tags: ["crunch", "classic-rock", "acdc"],
            notes: "Dry, tight and mid-forward. Minimal effects and a speaker that barks: the riff tone from the record, more or less.",
            units: [
                unit(.amp, ["voicing": 1, "gain": 26, "bass": 2, "mid": 2.5, "treble": 1.5, "presence": 4, "master": -12]),
                unit(.cabinet, ["lowCut": 90, "highCut": 5_000, "resonance": 5])
            ]
        ),
        rig(
            name: "Purple Haze",
            gear: "Fuzz Face → Plexi",
            tags: ["fuzz", "rock", "hendrix"],
            notes: "Germanium-style fuzz spitting into a cooking Marshall. Clean up with the guitar volume and the fuzz crisps up instead of dying.",
            units: [
                unit(.fuzz, ["sustain": 0.75, "tone": 0.6, "level": -8, "bias": 0.55]),
                unit(.amp, ["voicing": 1, "gain": 20, "bass": 1, "mid": 2, "treble": 2, "presence": 5, "master": -11]),
                unit(.cabinet, ["lowCut": 90, "highCut": 5_500, "resonance": 4])
            ]
        ),
        rig(
            name: "Comfortably Numb",
            gear: "Big Muff → Electric Mistress → Hiwatt · analog delay",
            tags: ["lead", "ambient", "floyd"],
            notes: "The solo rig: creamy Muff lead through a subtle Electric Mistress flanger into a loud clean amp, long dark echo and a hall. Hold notes and let the feedback sing.",
            units: [
                unit(.fuzz, ["sustain": 0.65, "tone": 0.45, "level": -10, "bias": 0.5]),
                unit(.flanger, ["rate": 0.22, "depth": 0.35, "feedback": 0.25, "mix": 0.28, "manual": 1.6]),
                unit(.amp, ["voicing": 2, "gain": 20, "bass": 1, "mid": 1, "treble": 1.5, "presence": 4, "master": -10]),
                unit(.cabinet, ["lowCut": 90, "highCut": 5_000, "resonance": 4]),
                unit(.delay, ["time": 480, "feedback": 0.38, "mix": 0.25, "tone": 0.4, "mode": 1]),
                unit(.reverb, ["size": 0.55, "damping": 0.45, "mix": 0.22, "predelay": 30, "mode": 1])
            ]
        ),
        rig(
            name: "Smells Like Teen Spirit",
            gear: "DS-1-style distortion · Small Clone chorus · clean amp",
            tags: ["alternative", "grunge", "nirvana"],
            notes: "The Nevermind recipe: a hard-clipping DS-1-style pedal into a clean Twin-style amp with a deep chorus. Dial the tone darker than feels right; the amp stays clean.",
            units: [
                unit(.distortion, ["gain": 24, "tone": 0.45, "level": -9, "edge": 0.35]),
                unit(.amp, ["voicing": 0, "gain": 7, "bass": 1, "mid": 1, "treble": 2, "presence": 4, "master": -8]),
                unit(.cabinet, ["lowCut": 85, "highCut": 5_500, "resonance": 4]),
                unit(.chorus, ["rate": 0.9, "depth": 0.45, "mix": 0.3, "width": 0.65])
            ]
        ),
        rig(
            name: "Master of Puppets",
            gear: "TS-9 boost → Mesa Mark · tight gate · scooped EQ",
            tags: ["metal", "thrash", "metallica"],
            notes: "Tight palm mutes: gate first, a mid-boosting boost into a high-gain amp, and a graphic EQ with the low mids pulled out.",
            units: [
                unit(.gate, ["threshold": -50, "decay": 120, "range": 70]),
                unit(.boost, ["gain": 12, "tone": 2, "tight": 110]),
                unit(.amp, ["voicing": 3, "gain": 30, "bass": 1, "mid": -4, "treble": 3, "presence": 6, "master": -13]),
                unit(.cabinet, ["lowCut": 95, "highCut": 4_800, "resonance": 5])
            ],
            eq: [0, 1, 0, 0, -2, -2, 1, 0, -1, 0]
        ),
        rig(
            name: "Enter Sandman",
            gear: "Mesa Dual Rectifier · TS boost · room",
            tags: ["metal", "hard-rock", "metallica"],
            notes: "Big, scooped Recto chunk with a boost to tighten the low end and a small room so the chugs do not sound dry.",
            units: [
                unit(.gate, ["threshold": -48, "decay": 140, "range": 65]),
                unit(.boost, ["gain": 8, "tone": 0, "tight": 120]),
                unit(.amp, ["voicing": 3, "gain": 28, "bass": 1, "mid": -1, "treble": 2, "presence": 5, "master": -12]),
                unit(.cabinet, ["lowCut": 90, "highCut": 5_200, "resonance": 5]),
                unit(.reverb, ["size": 0.3, "damping": 0.6, "mix": 0.08, "predelay": 10, "mode": 0])
            ]
        ),
        rig(
            name: "Killing in the Name",
            gear: "Hard-clip distortion · high-gain amp",
            tags: ["metal", "rap-rock", "ratm"],
            notes: "A hostile, mid-forward wall of distortion: a Tele bridge pickup straight into a cooking JCM800. No boost pedal; dig in for the drop-D riffs.",
            units: [
                unit(.amp, ["voicing": 2, "gain": 26, "bass": 2, "mid": 3, "treble": 2, "presence": 5, "master": -12]),
                unit(.cabinet, ["lowCut": 95, "highCut": 5_200, "resonance": 4])
            ]
        ),
        rig(
            name: "Seven Nation Army",
            gear: "Big Muff · clean amp · rolled-off tone",
            tags: ["fuzz", "riff", "rock"],
            notes: "The bass-like fuzz riff. Neck pickup, tone rolled off, and the fuzz does the octave illusion on its own.",
            units: [
                unit(.fuzz, ["sustain": 0.85, "tone": 0.35, "level": -10, "bias": 0.35]),
                unit(.amp, ["voicing": 0, "gain": 6, "bass": 3, "mid": -2, "treble": 0, "presence": 2, "master": -7]),
                unit(.cabinet, ["lowCut": 60, "highCut": 4_500, "resonance": 6])
            ]
        ),
        rig(
            name: "Streets Have No Name",
            gear: "Clean amp · dotted-8th delay · chorus",
            tags: ["ambient", "alternative", "u2"],
            notes: "The Edge's dotted-eighth delay into a bright clean amp with a wide chorus. Set the delay by ear against the tempo; 380 ms is a good start.",
            units: [
                unit(.compressor, ["threshold": -26, "ratio": 2, "attack": 20, "release": 220, "makeup": 3]),
                unit(.amp, ["voicing": 0, "gain": 8, "bass": 1, "mid": 1, "treble": 2, "presence": 5, "master": -8]),
                unit(.cabinet, ["lowCut": 90, "highCut": 6_000, "resonance": 3]),
                unit(.chorus, ["rate": 0.5, "depth": 0.3, "mix": 0.3, "width": 0.8]),
                unit(.delay, ["time": 380, "feedback": 0.42, "mix": 0.28, "tone": 0.6, "mode": 0]),
                unit(.reverb, ["size": 0.5, "damping": 0.5, "mix": 0.25, "predelay": 20, "mode": 1])
            ]
        ),
        rig(
            name: "Everlong",
            gear: "Distortion · chorus · analog delay",
            tags: ["alternative", "rock", "foofighters"],
            notes: "Wide, layered alternative rock: distortion into a crunchy amp, chorus for stereo width, short echo to glue the double-track feel.",
            units: [
                unit(.distortion, ["gain": 26, "tone": 0.5, "level": -8, "edge": 0.5]),
                unit(.amp, ["voicing": 1, "gain": 20, "bass": 1, "mid": 1, "treble": 1.5, "presence": 4, "master": -9]),
                unit(.cabinet, ["lowCut": 90, "highCut": 5_500, "resonance": 4]),
                unit(.chorus, ["rate": 0.7, "depth": 0.45, "mix": 0.3, "width": 0.75]),
                unit(.delay, ["time": 440, "feedback": 0.3, "mix": 0.2, "tone": 0.5, "mode": 1]),
                unit(.reverb, ["size": 0.35, "damping": 0.5, "mix": 0.12, "predelay": 12, "mode": 0])
            ]
        ),
        rig(
            name: "Only Shallow",
            gear: "Burman/Showman amps · tremolo · long reverb",
            tags: ["shoegaze", "ambient", "mbv"],
            notes: "My Bloody Valentine's glide-guitar wall: tremolo-picked chords, a deep amp tremolo and a long, bright reverb smearing everything together. Bend chords with the vibrato bar.",
            units: [
                unit(.amp, ["voicing": 2, "gain": 20, "bass": 1, "mid": 0, "treble": 2, "presence": 4, "master": -10]),
                unit(.cabinet, ["lowCut": 85, "highCut": 5_500, "resonance": 4]),
                unit(.tremolo, ["rate": 5.2, "depth": 0.75, "shape": 1, "stereo": 0.6]),
                unit(.reverb, ["size": 0.7, "damping": 0.3, "mix": 0.35, "predelay": 30, "mode": 1])
            ]
        ),
        rig(
            name: "Ambient Swell",
            gear: "Clean amp · slow tremolo · long delay · hall",
            tags: ["ambient", "clean", "texture"],
            notes: "Long, slow movement for volume swells and pads. The tremolo is gentle; the delay and hall do the heavy lifting.",
            units: [
                unit(.compressor, ["threshold": -28, "ratio": 2.5, "attack": 30, "release": 300, "makeup": 4]),
                unit(.amp, ["voicing": 0, "gain": 6, "bass": 2, "mid": 0, "treble": 1.5, "presence": 3, "master": -8]),
                unit(.cabinet, ["lowCut": 80, "highCut": 6_000, "resonance": 3]),
                unit(.tremolo, ["rate": 0.35, "depth": 0.35, "shape": 0, "stereo": 0.8]),
                unit(.delay, ["time": 600, "feedback": 0.5, "mix": 0.3, "tone": 0.45, "mode": 1]),
                unit(.reverb, ["size": 0.8, "damping": 0.35, "mix": 0.45, "predelay": 40, "mode": 1])
            ]
        ),
        rig(
            name: "Djent Tight",
            gear: "Gate · boost · high-gain amp · low-cut cab",
            tags: ["metal", "djent", "progressive"],
            notes: "Maximum string separation: hard gate, mid-heavy boost, high gain and a cab low-cut that removes the mud. Pick hard.",
            units: [
                unit(.gate, ["threshold": -45, "decay": 80, "range": 80]),
                unit(.boost, ["gain": 14, "tone": 0, "tight": 140]),
                unit(.amp, ["voicing": 3, "gain": 32, "bass": 0, "mid": -3, "treble": 3, "presence": 7, "master": -14]),
                unit(.cabinet, ["lowCut": 110, "highCut": 6_500, "resonance": 6])
            ],
            eq: [3, 2, 0, -2, -1, 0, 1, 0, 0, 0]
        ),
        rig(
            name: "Funk Clean",
            gear: "Strat · compressor · clean amp",
            tags: ["funk", "clean", "rhythm"],
            notes: "Squash and snap: a fast compressor, bright clean amp and almost no ambience so the sixteenth notes stay articulate.",
            units: [
                unit(.compressor, ["threshold": -28, "ratio": 4, "attack": 5, "release": 120, "makeup": 6]),
                unit(.amp, ["voicing": 0, "gain": 7, "bass": 0, "mid": 1, "treble": 2, "presence": 5, "master": -7]),
                unit(.cabinet, ["lowCut": 100, "highCut": 6_500, "resonance": 2]),
                unit(.reverb, ["size": 0.25, "damping": 0.6, "mix": 0.08, "predelay": 8, "mode": 0])
            ]
        ),
        rig(
            name: "Garage Rock",
            gear: "Overdrive · cooking amp · room",
            tags: ["rock", "garage", "crunch"],
            notes: "Loud, simple and slightly trashy: overdrive pushing a crunchy amp, a short room and nothing else. Turn it up.",
            units: [
                unit(.overdrive, ["drive": 28, "tone": 0.6, "level": -8, "mid": 0.5]),
                unit(.amp, ["voicing": 1, "gain": 18, "bass": 2, "mid": 1, "treble": 1.5, "presence": 4, "master": -10]),
                unit(.cabinet, ["lowCut": 90, "highCut": 5_000, "resonance": 4]),
                unit(.reverb, ["size": 0.3, "damping": 0.6, "mix": 0.15, "predelay": 10, "mode": 0])
            ]
        ),
        rig(
            name: "Ain't Talkin' 'Bout Love",
            gear: "Phase 90 → variac Plexi",
            tags: ["crunch", "classic-rock", "van-halen"],
            notes: "Script-logo Phase 90 in front of a boosted Plexi. The phaser is part of the rhythm sound on the record, not just a solo effect.",
            units: [
                unit(.phaser, ["rate": 0.28, "depth": 0.55, "feedback": 0.2, "mix": 0.45, "stages": 0]),
                unit(.amp, ["voicing": 1, "gain": 26, "bass": 1, "mid": 2, "treble": 2, "presence": 6, "master": -12]),
                unit(.cabinet, ["lowCut": 90, "highCut": 5_000, "resonance": 5])
            ]
        ),
        rig(
            name: "Whole Lotta Love",
            gear: "Tone Bender fuzz → Vox-style crunch",
            tags: ["fuzz", "classic-rock", "led-zeppelin"],
            notes: "Mid-forward, fuzzy and a little unruly: a Tone Bender-style fuzz into a cooking Vox-ish amp. Not the Marshall sound people often assume.",
            units: [
                unit(.fuzz, ["sustain": 0.72, "tone": 0.55, "level": -9, "bias": 0.6]),
                unit(.amp, ["voicing": 1, "gain": 18, "bass": 2, "mid": 1, "treble": 2, "presence": 4, "master": -11]),
                unit(.cabinet, ["lowCut": 90, "highCut": 5_500, "resonance": 4]),
                unit(.reverb, ["size": 0.3, "damping": 0.6, "mix": 0.1, "predelay": 12, "mode": 0])
            ]
        ),
        rig(
            name: "Modern Lead",
            gear: "High-gain head · digital delay · hall",
            tags: ["lead", "metal", "progressive"],
            notes: "Smooth, sustaining lead tone with a clean digital echo. Roll the guitar tone back for a violin-like attack.",
            units: [
                unit(.amp, ["voicing": 3, "gain": 26, "bass": 0, "mid": 1, "treble": 2, "presence": 5, "master": -11]),
                unit(.cabinet, ["lowCut": 95, "highCut": 5_800, "resonance": 4]),
                unit(.delay, ["time": 420, "feedback": 0.3, "mix": 0.22, "tone": 0.55, "mode": 0]),
                unit(.reverb, ["size": 0.55, "damping": 0.4, "mix": 0.2, "predelay": 25, "mode": 1])
            ]
        )
    ])

    /// Factory loudness calibration.
    ///
    /// Every preset was rendered with the same decaying guitar note and its
    /// RMS was matched to 0.075. The trim is applied after the master volume
    /// and before the limiter, so it changes level without changing the amp's
    /// drive, tone stack or the user's master setting.
    private static let levelTrims: [String: Double] = [
        "Studio Clean": 21.0,
        "Sultans of Swing": 19.5,
        "Little Wing": 18.5,
        "Texas Flood": 23.5,
        "Slow Dancing": 14.5,
        "Plexi Crunch": 4.0,
        "Back in Black": 1.5,
        "Purple Haze": -3.5,
        "Comfortably Numb": -4.0,
        "Smells Like Teen Spirit": 16.5,
        "Master of Puppets": -3.0,
        "Enter Sandman": -2.0,
        "Killing in the Name": 0.0,
        "Seven Nation Army": 6.0,
        "Streets Have No Name": 23.0,
        "Everlong": -2.0,
        "Only Shallow": -1.5,
        "Ambient Swell": 17.0,
        "Djent Tight": 0.0,
        "Funk Clean": 24.0,
        "Garage Rock": 5.0,
        "Ain't Talkin' 'Bout Love": -0.5,
        "Whole Lotta Love": -3.0,
        "Modern Lead": -3.5
    ]

    /// Applies the calibration table to the factory catalogue.
    private static func balanced(_ presets: [Preset]) -> [Preset] {
        presets.map { preset in
            var copy = preset
            copy.settings.outputTrim = (levelTrims[preset.name] ?? 0)
                .clamped(to: BoardSettings.trimRange)
            return copy
        }
    }

    /// Builds one factory preset with a stable id.
    private static func rig(
        name: String,
        gear: String,
        tags: [String],
        notes: String,
        units: [FXUnit],
        eq: [Double]? = nil,
        master: Double = -6
    ) -> Preset {
        var settings = board(overrides: units, eq: eq, master: master)
        settings.masterVolume = master
        return Preset(
            id: "builtin." + Preset.slug(from: name),
            name: name,
            author: "GtrBoard",
            gear: gear,
            notes: notes,
            tags: tags,
            settings: settings,
            isBuiltIn: true,
            createdAt: epoch,
            modifiedAt: epoch
        )
    }

    /// Canonical chain with every pedal disabled unless the preset overrides
    /// it. This keeps presets reproducible: adding a new effect kind later
    /// does not silently turn it on in old presets.
    private static func board(overrides: [FXUnit], eq: [Double]?, master: Double) -> BoardSettings {
        var table: [FXKind: FXUnit] = [:]
        for unit in overrides {
            table[unit.kind] = unit
        }
        let units = FXKind.defaultChain.map { kind -> FXUnit in
            if let unit = table[kind] { return unit }
            var unit = FXUnit(kind: kind)
            unit.enabled = false
            return unit
        }
        let gains = eq ?? Array(repeating: 0.0, count: 10)
        return BoardSettings(
            units: units,
            graphicEQ: GraphicEQSettings(gains: GraphicEQSettings.sanitize(gains)),
            masterVolume: master,
            limiter: true,
            bypass: false
        )
    }

    /// Creates an enabled pedal with the supplied real-unit values.
    private static func unit(_ kind: FXKind, _ params: [String: Double]) -> FXUnit {
        var unit = FXUnit(kind: kind, enabled: true)
        for (key, value) in params {
            unit.setValue(value, for: key)
        }
        return unit
    }
}
