# Cineo Music polish: crossfade, ducking and manual cues

This work stacks on Music Timeline & BeatSync PR #58 and is built with
Apple Command Line Tools only, without Xcode.app. All audio analysis is local.
No LLM suggestions, cloud analysis or external model downloads.

## What changed

**Loop crossfade:** the music clip now has a loopCrossfade duration, default 0.
The pure-Swift CineoMusicClip schedules repeat starts earlier by the overlap.
Preview uses two synchronized AVPlayers for the two simultaneously audible
source layers. AVFoundation export places alternating repeat segments on two
composition tracks, mixing matching linear crossfade gain automation and
global fade-in/fade-out. A value of 0 retains the existing hard-loop path.

**Ducking:** on request, the original recording's audio is decoded locally,
then non-silent activity regions are detected using a conservative peak
threshold. Background music is attenuated during those regions, with a
0.2s attack and 0.55s release by default. The UI controls the threshold
and lowered music gain. This is **not voice identification or speech VAD**:
notifications, system audio and other sounds may activate it. The exact
activity ranges and gain formula are shared between preview and export.
Ducking is disabled by default. Videos with no original audio remain usable.

**Cues:** add hit, crescendo or transition markers at the video playhead,
inspect them on the waveform and click to scrub, or remove them. These are
editorial markers, not sound effects, generated stems or audio-automation
events. They are persisted per project and included in unified instructions.

## Strict JSON
The existing music object now optionally accepts:

~~~json
{
  "loopCrossfade": 0.35,
  "duckingEnabled": true,
  "duckingLevel": 0.25,
  "duckingThreshold": 0.08,
  "cues": [
    {"id": "main-reveal", "at": 8.6, "kind": "hit", "label": "Show result"},
    {"id": "summary", "at": 17.1, "kind": "transition", "label": "Closing"}
  ]
}
~~~

These fields join the pre-existing music.generate recipe and
sourceIn/clipDuration/loop settings. This fragment is not a full Cineo
instruction document; wrap it inside the existing music object and include
version=1, timebase=output, actions=[] as described in music-beatsync-v1.md.
Old music.json without crossfade, ducking or cues remains compatible.

## Regression testing and release gate

Automated pure Swift tests cover loop segments/dual playback layers, old
JSON defaults, ducking gain ramps, activity regions and cue validation.
Mac CI compiles and packages Cineo without Xcode.app but is not a substitute
for audiovisual inspection. The experimental PR must remain draft until:

1. Import a musical source with clearly different ending and beginning.
   Repeat with loopCrossfade=0 and 0.5s. Compare the audible seam, verify
   the sound is continuous and that preview matches exported MP4.
2. Scrub backwards/forwards across a crossfade boundary, pause and resume,
   and confirm both AVPlayers stop when music is inactive.
3. Enable original audio ducking, play a short recording with speaking,
   notification sound and silent portions. Confirm ducking is triggered by
   audio activity, and volume returns afterwards.
4. Export a recording without original audio and one with system audio
   and microphone. Verify original sound isn't lost and ducking is skipped
   safely when no activity is present.
5. Add three cue types and save/reopen a .cineo project. Confirm identical
   positions and strict JSON export/import. Cues must never trigger
   hidden ACE-Step generation.
6. Test clips shorter than the fade, sourceIn close to the end,
   source audio missing, a cancelled export and disk-full recovery.
7. Listen for audio/video sync and compare fade/crossfade/duck levels to
   the preview. Record macOS version, audio sample rates, and source lengths.

## Not done

- Audio-ducking speech recognition/VAD and per-speaker logic.
- Audio stem separation, new sound effect synthesis, editable cue automation,
  arbitrary split clips and multitrack mixing.
- ACE-Step partial regeneration or built-in GGUF model install/launch.
- User-facing LLM editing suggestions.
