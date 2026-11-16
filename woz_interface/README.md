# WoZ Control – Restaurant Dialogue (MATLAB)

MATLAB Wizard-of-Oz control interface for the restaurant ordering dialogue
(`restaurant_ordering_branching_dialogue.drawio`). The wizard listens to the
participant, clicks the matching customer intent, and the avatar (UE5 MetaHuman)
answers with a prerecorded waiter line.

## Files

| File | Purpose |
|---|---|
| `WoZControl.m` | The GUI (start this) |
| `dialogueTree.m` | Dialogue tree: states, customer intents, waiter clip IDs and texts. Edit this to change the dialogue |
| `exportClipList.m` | Exports the recording script (all waiter clips) to `clip_list.csv` |
| `ue5Simulator.m` / `ue5_simulator.py` | Fake UE5 endpoint for testing without Unreal |
| `audio/` | Waiter recordings, one file per clip: `audio/<clip_id>.wav` |
| `logs/` | Session logs (CSV), one file per session |

Requirements: MATLAB R2021a or later, no toolboxes. The simulator needs Python 3 (the macOS system Python is fine).

## Running

Run these in the MATLAB Command Window:

```matlab
cd /Users/taey/matlab-workspace/woz_interface
```

### 1. Local test without UE5

```matlab
WoZControl
```

MATLAB plays the waiter lines itself. If `audio/<clip_id>.wav` exists, that file is played.
If it doesn't exist yet, the line is read aloud with the OS text-to-speech
(macOS `say`, Windows SAPI). You can test the whole dialogue tree before recording anything.

### 2. Test with the fake UE5

```matlab
ue5Simulator('start')
WoZControl('UE5Port',7000)
```

The simulator behaves like the real UE5 project: it replies `started` / `done` to every clip
and `pong` to pings. No sound plays in this mode, because audio is UE5's job. Check the
log table to see that commands and replies are flowing.

### 3. Connect to the real UE5

```matlab
WoZControl('UE5Host','192.168.0.20','UE5Port',7000)
```

UE5 must already be running as a TCP server on that port. If UE5 runs on the same
machine, `UE5Host` can be omitted (default `127.0.0.1`).

### Other commands

```matlab
exportClipList          % write recording script -> clip_list.csv
ue5Simulator('stop')    % stop the fake UE5
```

### Options

```matlab
WoZControl('ParticipantID','P03', ...      % skip the ID prompt
           'UE5Host','127.0.0.1', 'UE5Port',7000, ...
           'AudioOutput','ue5', ...        % 'matlab' | 'ue5' | 'both'
           'DoneTimeout',2.0, ...          % extra seconds to wait for UE5 "done"
           'AudioDir','audio', 'LogDir','logs', ...
           'UseTTS',true)                  % TTS placeholder for missing WAVs
```

`AudioOutput` defaults to `'matlab'` when no UE5 port is given, and to `'ue5'` otherwise.

## Using the GUI

| Key | Action |
|---|---|
| `1`–`9` | Customer intent buttons (what the participant said) |
| `F` | Fallback: "Sorry, could you choose from our menu?" |
| `R` / `S` | Replay last line / stop |
| `Backspace` | Undo last step |
| `Q W E A D Z X C` | Avatar gestures: nod, shake head, smile, listen, think, point at menu, wave, back to idle |

Press **Start session** to begin. The waiter asks "Are you ready to order?".

## Dialogue diagram (source and differences)

The dialogue tree in `dialogueTree.m` is based on Yunye's diagram on the `yunye` branch
(`restaurant_ordering_branching_dialogue.drawio-2.drawio`, commit `1d3a037` "Changed drawing", 13.11.2026).
The diagram itself is maintained by Yunye; this folder only contains an exported copy.

`diagram/` holds SVG exports of that diagram with the small changes made for this interface:

| File | Content |
|---|---|
| `diagram/dialogue_1_start_and_intents.svg` | Page 1: start, customer intents |
| `diagram/dialogue_2_drinks_and_confirmation.svg` | Page 2: drinks, confirmation, change/cancel |
| `diagram/dialogue_3_implementation_notes.svg` | Page 3: implementation notes |

Changes compared to Yunye's diagram:
- **Ask for recommendation**: "I recommend our chicken salad" is followed by
  "Would you like to order that, or something else?" (W09), the same as special/discount,
  instead of going straight to the drink question.
- **Tea → ginger tea** in the drink options and the waiter lines.

Note: the Mermaid flowcharts in the top-level `README.md` (main branch) were written before the
13.11 diagram update. They do not include "Please take your time" (irrelevant answer), "Start over",
the irrelevant-answer branches or the recommendation flow above, so they no longer match the
diagram or this interface.

## Audio clips

All 27 waiter lines are in `audio/<clip_id>.wav`, generated with the Kokoro TTS model
(kokoro-onnx v1.0, voice `af_heart`, speed 1.0).

- Format: **24 kHz, mono, WAV**. MATLAB (`audioread`/`audioplayer`) plays this as is.
- **Unreal Engine 5:** UE5 imports 24 kHz WAV and resamples at playback, so it works without changes.
  If the project needs a fixed rate (44.1 or 48 kHz, e.g. to match the MetaHuman/lip-sync pipeline
  or the lab's audio interface), resample the files. Do **not** re-generate with Kokoro: Kokoro
  only outputs 24 kHz, and upsampling cannot add detail, so resampling the existing files gives the
  same result.

```matlab
% resample all clips to 48 kHz (writes to audio_48k/)
inDir = 'audio'; outDir = 'audio_48k'; fsOut = 48000;   % or 44100
if ~exist(outDir,'dir'), mkdir(outDir); end
for f = dir(fullfile(inDir,'*.wav'))'
    [y,fs] = audioread(fullfile(inDir,f.name));
    [P,Q] = rat(fsOut/fs);
    audiowrite(fullfile(outDir,f.name), resample(y,P,Q), fsOut);
end
```

`resample` needs the Signal Processing Toolbox. Without it, use `sox in.wav -r 48000 out.wav`
or `ffmpeg -i in.wav -ar 48000 out.wav`.

To change the voice, re-run generation with another Kokoro voice (e.g. `am_michael`) and keep
all 27 clips in the same voice.

## UE5 protocol (TCP, one JSON object per line)

UE5 is the server and MATLAB connects as the client.

MATLAB → UE5
```json
{"event":"play","clip":"W06_special","seq":12,"duration":3.6,"text":"...","state":"ORDER","dish":"salmon","drink":""}
{"event":"gesture","name":"nod","seq":13}
{"event":"stop","seq":14}
{"event":"ping","seq":15}
```

UE5 → MATLAB
```json
{"event":"started","clip":"W06_special","seq":12}
{"event":"done","clip":"W06_special","seq":12}
{"event":"pong","seq":15}
```

- `play`: UE5 plays the Level Sequence for this clip ID (voice + face + body) and sends `done` when it finishes.
- When one intent triggers several clips, MATLAB sends the next clip only after `done` arrives.
  If `done` does not arrive within the expected duration plus `DoneTimeout`, MATLAB sends the next clip anyway and logs `ue5_timeout`.

## Log format

`logs/<ParticipantID>_<yyyyMMdd_HHmmss>.csv`:
`wallclock, t_sec, state, action, detail, clips, seq, latency_ms`

`latency_ms` is the time from a command being sent until UE5's reply. Use it for the timing evaluation.
