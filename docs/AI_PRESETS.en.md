# GtrBoard presets with AI

<p><b>English</b> · <a href="AI_PRESETS.md">🇷🇺 Русский</a></p>

GtrBoard stores presets as open JSON. That means a preset can be **generated in
any LLM chat** — ChatGPT, Claude, DeepSeek, Gemini — and then imported into the
app. GtrBoard itself never calls the network and needs no API keys: you simply
copy the JSON into a file.

> This is not “magic” import of proprietary formats. The model writes a normal
> `.gtrpreset`; GtrBoard validates and clamps every value on import.

## Three steps

1. Copy the prompt below into a chat and describe the tone you want.
2. Save the answer as `MyTone.gtrpreset` (UTF-8).
3. In GtrBoard: **⌘O** (Import) or **Browse Presets → Import**. The preset
   appears in the library and can be assigned to A/B.

Ready example:
[`examples/ai-british-crunch.gtrpreset`](examples/ai-british-crunch.gtrpreset).

## Prompt

```text
You are a guitar tone engineer. Generate ONE GtrBoard preset for this
description: "warm British crunch for humbuckers, a little midrange, light
room reverb".

Return ONLY valid JSON, without markdown fences, comments or explanations:

{
  "format": "com.andreyilin.gtrboard.preset",
  "version": 1,
  "preset": {
    "name": "...",
    "author": "AI + <your name>",
    "gear": "...",
    "tags": ["..."],
    "notes": "...",
    "settings": {
      "units": [
        {"kind": "gate", "enabled": false},
        {"kind": "compressor", "enabled": false},
        {"kind": "boost", "enabled": false},
        {"kind": "overdrive", "enabled": false},
        {"kind": "distortion", "enabled": false},
        {"kind": "fuzz", "enabled": false},
        {"kind": "amp", "enabled": true},
        {"kind": "cabinet", "enabled": true},
        {"kind": "chorus", "enabled": false},
        {"kind": "flanger", "enabled": false},
        {"kind": "phaser", "enabled": false},
        {"kind": "tremolo", "enabled": false},
        {"kind": "delay", "enabled": false},
        {"kind": "reverb", "enabled": true}
      ],
      "graphicEQ": {"enabled": true, "gains": [0,0,0,0,0,0,0,0,0,0]},
      "masterVolume": -6,
      "outputTrim": 0,
      "limiter": true,
      "bypass": false
    }
  }
}

Rules:
1. `units` must contain exactly 14 kinds in this order: gate, compressor,
   boost, overdrive, distortion, fuzz, amp, cabinet, chorus, flanger, phaser,
   tremolo, delay, reverb. Enable only the pedals you need.
2. Parameters are optional — omit them to use factory defaults. When present,
   use real units: dB, Hz, ms; percentages are 0…1.
3. Switches: amp.voicing 0 Clean / 1 Crunch / 2 Lead / 3 High Gain;
   phaser.stages 0=4 / 1=6 / 2=8 / 3=12; tremolo.shape 0 Sine / 1 Triangle /
   2 Square; delay.mode 0 Digital / 1 Analog / 2 Ping-Pong; reverb.mode
   0 Room / 1 Hall / 2 Plate.
4. `graphicEQ.gains` has exactly 10 dB values in this order: 31.5…16k Hz.
5. masterVolume is −60…12 dB; outputTrim is −24…24 dB.
6. Do not add id, createdAt, modifiedAt or isBuiltIn. JSON only.
```

> If the model still wraps the answer in ` ```json ... ``` `, remove the fences
> and keep only the content from `{` to `}`.

## Parameter reference

Every parameter is optional. If a key is missing, GtrBoard uses the factory
default. Unknown keys are dropped and out-of-range values are clamped — a preset
cannot break the DSP.

### Chain order

```
gate → compressor → boost → overdrive → distortion → fuzz → amp → cabinet
→ chorus → flanger → phaser → tremolo → delay → reverb
```

The order in `units` sets the chain order. Each `kind` must appear at most once;
missing units are appended with factory settings, so it is best to list all 14.

### Pedals

| kind | Parameters (range, default) |
|---|---|
| `gate` | `threshold` −80…−20 dB (−60), `decay` 20…1000 ms (180), `range` 0…80 dB (60) |
| `compressor` | `threshold` −60…0 dB (−24), `ratio` 1…20 (4), `attack` 0.5…100 ms (10), `release` 20…1000 ms (180), `makeup` 0…24 dB (6) |
| `boost` | `gain` 0…30 dB (9), `tone` −12…12 dB (0), `tight` 20…400 Hz (70) |
| `overdrive` | `drive` 0…40 dB (18), `tone` 0…1 (0.55), `level` −30…6 dB (−6), `mid` 0…1 (0.6) |
| `distortion` | `gain` 0…50 dB (26), `tone` 0…1 (0.55), `level` −30…6 dB (−8), `edge` 0…1 (0.5) |
| `fuzz` | `sustain` 0…1 (0.7), `tone` 0…1 (0.5), `level` −30…6 dB (−6), `bias` 0…1 (0.5) |
| `amp` | `gain` 0…40 dB (12), `bass`/`mid`/`treble` −12…12 dB (0), `presence` 0…12 dB (3), `master` −40…6 dB (−8), `voicing` 0…3 (1) |
| `cabinet` | `lowCut` 40…250 Hz (80), `highCut` 2000…12000 Hz (5500), `resonance` 0…12 dB (4) |
| `chorus` | `rate` 0.05…8 Hz (0.8), `depth` 0…1 (0.5), `mix` 0…1 (0.4), `width` 0…1 (0.7) |
| `flanger` | `rate` 0.02…5 Hz (0.25), `depth` 0…1 (0.6), `feedback` −0.95…0.95 (0.35), `mix` 0…1 (0.5), `manual` 0.5…10 ms (2.5) |
| `phaser` | `rate` 0.02…5 Hz (0.35), `depth` 0…1 (0.6), `feedback` 0…0.9 (0.3), `mix` 0…1 (0.5), `stages` 0…3 (1) |
| `tremolo` | `rate` 0.2…12 Hz (4.5), `depth` 0…1 (0.6), `shape` 0…2 (0), `stereo` 0…1 (0) |
| `delay` | `time` 20…1500 ms (380), `feedback` 0…0.95 (0.35), `mix` 0…1 (0.3), `tone` 0…1 (0.55), `mode` 0…2 (1) |
| `reverb` | `size` 0…1 (0.55), `damping` 0…1 (0.45), `mix` 0…1 (0.22), `predelay` 0…120 ms (20), `mode` 0…2 (1) |

### Switches

| Key | Values |
|---|---|
| `amp.voicing` | `0` Clean · `1` Crunch · `2` Lead · `3` High Gain |
| `phaser.stages` | `0` 4 stages · `1` 6 · `2` 8 · `3` 12 |
| `tremolo.shape` | `0` Sine · `1` Triangle · `2` Square |
| `delay.mode` | `0` Digital · `1` Analog · `2` Ping-Pong |
| `reverb.mode` | `0` Room · `1` Hall · `2` Plate |

### Global fields

| Field | Meaning |
|---|---|
| `graphicEQ.gains` | 10 bands in dB, −12…12; order 31.5…16k Hz |
| `graphicEQ.enabled` | whether the EQ section is active |
| `masterVolume` | preset output level, −60…12 dB |
| `outputTrim` | preset loudness calibration, −24…24 dB |
| `limiter` | output look-ahead limiter |
| `bypass` | pass the signal through (usually `false`) |

## Example result

Description: “warm British crunch for humbuckers, a little midrange, light room
reverb.”

The model returns JSON where `boost`, `amp`, `cabinet` and `reverb` are enabled
and the rest are off. Full file:

[`examples/ai-british-crunch.gtrpreset`](examples/ai-british-crunch.gtrpreset)

Import it and adjust the **PRESET** slider in the footer to match your guitar
and interface.

## Getting a good result

- **Describe the tone like an engineer:** genre, guitar/pickups, amp, gain
  level, brightness, effects, reference players. More detail is better.
- **Ask for several versions** (“less gain”, “more mids”, “add delay”) and
  import all of them — compare in A/B.
- **Do not ask for normalized 0…1** for level/frequency values: GtrBoard expects
  real dB/Hz/ms. Percentages (`tone`, `mix`, `depth`) are genuinely 0…1.
- **Leave `outputTrim` at 0** when generating. After import, adjust the
  **PRESET** slider so the preset level sits well against the others.
- **Trust your ears.** The model cannot hear your rig; the same JSON sounds
  different on another guitar or interface.
- **Never paste secrets/API keys.** Generation happens in an external service.

## If the import fails

| Symptom | Check |
|---|---|
| “bad JSON” | Remove ``` fences, check double quotes and commas |
| Preset is silent | `amp` and `cabinet` enabled; `bypass` is not `true` |
| Too loud | Lower `masterVolume`/`outputTrim` or the PRESET slider |
| No effect | `enabled: true` on the pedal and parameters in real units |
| Wrong order | The `units` array sets the order; list all 14 kinds in order |

## File format

A preset is an envelope:

```json
{
  "format": "com.andreyilin.gtrboard.preset",
  "version": 1,
  "preset": {
    "name": "...",
    "settings": {
      "units": [],
      "graphicEQ": {},
      "masterVolume": -6,
      "outputTrim": 0,
      "limiter": true,
      "bypass": false
    }
  }
}
```

`id`, `createdAt`, `modifiedAt` and `isBuiltIn` are optional. On import
GtrBoard creates a new `id` so an existing preset is never overwritten.
