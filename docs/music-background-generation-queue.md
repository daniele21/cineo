# Background ACE-Step queue — Cineo Studio

## User experience

Use **Music Director → Accoda generazione ACE-Step** or select an audio
region and choose **Rigenera solo l'intervallo**. Both submit jobs to the
same durable application queue. Close the **Music Director sheet** and
continue editing the video, return to the recording dashboard or open another
video: **generation continues while the Cineo application is running**.

The **Coda musica** button remains visible on the capture dashboard, video
editor and music sheet. It shows queued jobs, active stage, errors and finished
results. ACE-Step itself serializes requests; Cineo submits at most one
job pipeline at a time. Progress reports the *actual LM / synth / repaint
stage*, not fabricated completion percentages.

When a new WAV is available, return to its source video and click
**Applica al video**. There is intentionally no automatic overwriting of
the user's existing soundtrack, current timeline edits or media assets.
A pending job remains associated with its source video after "Save As .cineo".

## Durability and process boundaries

The serial queue and latest remote ACE job ID are atomically persisted in
`~/Library/Application Support/Cineo/music-job-queue.json`.
New WAV assets live in `~/Library/Application Support/Cineo/MusicJobs/`.
Files are never uploaded to any cloud service. Both output and job history
survive ordinary editor navigation and application relaunch.

At remote submission time, the ACE client saves the real `/lm`, `/synth`
or repaint job ID **before** continuing. When the app reopens:

- If the stored job was executing and a remote ID is known, Cineo resumes
  polling that same job, **provided the same ACE-Step server retained it**.
- If a result WAV exists after a crash, the job is recovered as complete.
- If there was no persisted remote ID, the job is shown as **Interrotto**.
  Retrying is explicit, to avoid blindly duplicating an unknown submission.
- If the server restarted or lost its FIFO/job registry, the job cannot
  be transparently recovered: the user can manually retry from the queue.
- If the queue file is corrupt or unreadable, the original JSON is
  preserved and no new queue is written over it.

**Not a detached daemon:** if you quit the Cineo app completely, Cineo does
not keep a hidden client polling in the background. An *independently running*
ACE-Step server may finish an already-submitted remote job, and the app can
collect that result on reopening. Jobs not yet submitted wait for Cineo to
reopen. Stopping an ACE-Step process launched inside Cineo can also lose its
in-memory remote queue. For generation to continue even after quitting the
app, a dedicated LaunchAgent/service architecture would be a separate
explicit milestone, requiring user opt-in.

## Controls and limits

- Single Cineo worker, up to 20 live queued/running jobs; 50 history items.
- **Annulla** cancels the local task and requests ACE server-side job cancel
  for a job with a known remote ID.
- **Riprendi** retries remote polling when possible; **Riprova** explicitly
  submits a fresh job after a permanent failure.
- Result is only applicable to the original video or same saved .cineo
  project. Opening another video never silently applies the music.
- Generated WAVs are kept after job-list removal, not destroyed silently.

## Verification

Pure Swift tests cover Codable round-trip, saved synth checkpoint recovery,
interrupted ambiguous submission, output recovery and invalid remote IDs.
macOS CI must compile the entire app without full Xcode.app and run the
ACE endpoint adapter, music tests and integrated Studio suite.

Final perceptual audio/video E2E on the developer's Mac is deliberately
deferred to the last overall Cineo milestone as requested.
