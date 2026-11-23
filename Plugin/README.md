# GtrBoard AUv3

The DAW version of GtrBoard. It is an **Audio Unit v3 effect** (`aufx`),
manufacturer `Andrey Ilin`, name `GtrBoard`, built from the same `BoardCore`
engine as the standalone app.

## Build and install

Requirements: full Xcode (not only Command Line Tools) and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
./plugin-build.sh
```

The script generates `GtrBoardPlugin.xcodeproj`, builds the extension, embeds
it in **GtrBoard Plugin Host.app**, installs the host into `/Applications`,
registers the extension and runs `auval`.

## Use it in Logic / GarageBand

1. Run `./plugin-build.sh` once (it also launches the host).
2. Quit and reopen Logic/GarageBand.
3. Add the plug-in as an insert on the guitar track:
   **Audio FX → Audio Units → Andrey Ilin → GtrBoard**.

The plug-in window is the full pedalboard: 15 pedals, the graphic EQ, master,
limiter, bypass and the feedback guard. Every knob is also exposed as a host
parameter for automation. The board is saved in the project state.

## Details

- Stereo in/out. Guitar is mono but the DAW can use the plug-in on a mono or
  stereo track; the board processes both channels.
- Latency is reported to the host (limiter look-ahead plus 64 samples when the
  IR pedal is on).
- Built-in IR cabinets work. Importing a custom WAV is only available in the
  standalone app, because the AU cannot rebuild its convolution kernels while
  the host is rendering.
- Project state stores the complete board, including pedal order and the IR
  model. Presets are available from the plug-in header.
- The AUv3 is sandboxed and ad-hoc signed, like the standalone build. It is an
  arm64 build.
