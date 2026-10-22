# Cineo Music: Audio E2E and camera cues

This slice builds on the audio polish branch and PR #60. All code remains local-first;
there are no LLM suggestions, cloud media services or Xcode.app dependencies.

## Testable production audio mixer

The existing CineoAudioMuxer was moved, unchanged in behavior, from the app
executable into the shared macOS Swift package Packages/CineoAudio. The app
imports that package; the CLI regression test imports the **same production
mixer** (not a mock).

The executable cineo-audio-smoke creates a short actual H264 video and three
44.1 kHz PCM WAV fixtures, then uses CineoAudioMuxer twice to produce MP4s.
It decodes the output audio to verify video/audio streams, clip duration,
that the waveform is audible outside the duck window, the level is reduced
in the synthetic duck region and recovers afterward, and that original
narration remains audible when mixed with music.

To run on a Mac with only Apple Command Line Tools:

~~~bash
cd ~/Personal/cineo
swift run --package-path Packages/CineoAudio --configuration release cineo-audio-smoke
~~~

CI runs this program in its native macOS CLT smoke. It is a reproducible
baseline, not a replacement for headphone listening with a real recorded
SaaS demo and ACE-Step output.

## Ducking precision

The analyzer now exposes local **20 ms RMS levels** independently of the
coarser 256-bin preview waveform. The same activity detector is applied to
these RMS levels, so brief breaks in narration are no longer forced into
seconds-wide buckets on long videos.

Ducking still means original **audio activity**, not confirmed speech or
speaker classification. A browser notification can therefore lower the
music. The user can disable the feature and adjust the sensitivity.

## Manual cues that drive actual camera motion

Each user-authored Hit / Crescendo / Transition cue exposes *Prepara zoom*
in Music Director. This creates an inspectable, non-destructive **proposal**:
- Hit: focus peak at the cue timestamp, hold and return to wide.
- Crescendo: approach focus progressively, then return.
- Transition: pull back to the full frame.

The existing Cineo camera renderer renders the proposed keyframes **only
after the user presses Applica animazione**. The process refuses any cue
too near the clip boundary or whose generated keyframe segment would
overlap an existing manually edited keyframe. No automatic overwrites.
All existing cues and generated camera keyframes persist using the ordinary
Cineo project formats. Cancelling the proposal changes nothing.

## Next technical gates

1. CI must pass the new native H264 + WAV / AAC composition smoke, the
   integrated app build, the pure Swift camera cue tests and RMS audio tests.
2. On an Apple Silicon Mac, play an imported track with hard loop vs crossfade
   with original audio. Compare video preview and the final export by ear.
3. Try ducking with speech, browser notifications and silence; verify that
   short pauses recover correctly and that no original narration disappears.
4. Apply each cue with user confirmation, re-export, reopen the Cineo project
   and verify camera/markers/audio are identical. Try an overlapping cue and
   verify rejection.
5. Confirm original recordings and music source files are not modified and
   cancellation doesn't corrupt the output.

No automated ACE-Step backend install or music regeneration changes in this
slice; both remain independent future milestones.
