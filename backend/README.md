# Gym app backend: set video analysis

The iOS app uploads one video per set to Firebase Storage. A Cloud Function
picks it up, runs pose estimation and rule-based analysis, and writes the
result to Firestore, where the app is already listening.

## Architecture

```
iOS app ──upload──▶ Storage  videos/{uid}/{sessionId}/{setId}.mov|.mp4  (+ custom metadata)
                       │ object finalized
                       ▼
          Cloud Function  analyze_set_video        (functions/main.py, Python, 2nd gen)
            1. users/{uid}/sessions/{sessionId}/sets/{setId}  ← status: "processing"
            2. ANALYZER_URL set?   ── yes ─▶ Cloud Run  POST /analyze {bucket, path}
                                              (ID-token auth, analyzer/server.py)
                                   ── no ──▶ import analyzer in-process (emulator)
            3. set doc ← status "done" + analysis + analyzedAt   (or "failed" + error)
                       ▼
                 Firestore ──snapshot listener──▶ iOS app
```

The analyzer (`analyzer/`) is a plain Python package:

| Module | Role |
|---|---|
| `pose.py` | MediaPipe Pose over frames sampled at ~15 fps with OpenCV. Returns a `PoseSequence` (T × 33 × [x, y, z, visibility]). MediaPipe/OpenCV are imported lazily; any estimator implementing `PoseEstimator.estimate()` (MoveNet etc.) can replace it. Uses the Tasks API `PoseLandmarker` when `POSE_MODEL_PATH` points to a `.task` model, otherwise the legacy `solutions.pose`. |
| `features.py` | 2D joint angles (knee, hip, elbow, shoulder, body line), trunk lean, positions normalised by torso length, camera side/view detection, NaN filling and Savitzky-Golay smoothing (numpy only). |
| `classify.py` | Rule-based classifier: body orientation (standing / supine / prone / hanging) plus which joints move most, as fuzzy scores per exercise. The app's `exerciseId` is a strong prior (30 % weight) but a clearly different movement still wins. |
| `reps.py` | Rep counting by hysteresis on the exercise's primary angle (valley or peak), partial reps from range of motion, eccentric/concentric tempo per rep. |
| `form.py` | Per-exercise checks producing `formIssues` and `formScore` (100 minus 6/14/25 per low/medium/high issue). |
| `load.py` | Weight from the logged value, velocity loss and RPE from rep slowdown, rest time, and the `estimate_load_from_frames` hook (returns `None`). |
| `pipeline.py` | `analyze_video(path, metadata)` and `analyze_pose_sequence(seq, metadata)` → the `analysis` map. |
| `gcs.py` | Download from Storage + read custom metadata + analyse (shared by Cloud Run and the in-process fallback). |
| `server.py` | FastAPI app: `POST /analyze {bucket, path}` → `{"analysis": {...}}`, `GET /healthz`. |

## Contract (the iOS app depends on this)

**Storage path:** `videos/{uid}/{sessionId}/{setId}.mov` (or `.mp4`).
Custom metadata, all strings: `exerciseId`, `exerciseName`, `plannedReps`,
`loggedWeightKg`, `setIndex`, `startedAt` (ISO 8601), `endedAt` (ISO 8601),
`previousSetEndedAt` (ISO 8601 or empty), optional `bodyMassKg`,
`heartRateAvg`, `heartRateMax`.

**Firestore doc:** `users/{uid}/sessions/{sessionId}/sets/{setId}`. The
server writes only these fields:

| Field | Value |
|---|---|
| `status` | `"processing"` → `"done"` or `"failed"` |
| `error` | string or `null` |
| `analyzedAt` | server timestamp (written on done and failed) |
| `analysis` | map below (only on done) |

`analysis`:

| Key | Type | Notes |
|---|---|---|
| `detectedExercise` | string | `squat`, `deadlift`, `bench_press`, `overhead_press`, `barbell_row`, `pull_up`, `push_up`, `lunge`, `bicep_curl`, `romanian_deadlift`, `hip_thrust`, `lateral_raise`, `unknown` |
| `exerciseConfidence` | float 0-1 | |
| `reps` | int | full-range reps only |
| `repTimestamps` | [float] | seconds into the video of the bottom/peak of each full rep (`len == reps`) |
| `partialReps` | int | reps with clearly less range than the set's best reps (or < 50 % of the exercise's normal range) |
| `avgRepDurationSec` | float | |
| `tempo` | `{eccentricSec, concentricSec}` floats | mean over full reps |
| `rangeOfMotionScore` | int 0-100 | rep range vs. typical full range |
| `formScore` | int 0-100 | 0 when no reps were found |
| `formIssues` | [`{code, severity, message, atSec}`] | severity `low`/`medium`/`high`; `atSec` float or null |
| `estimatedWeightKg` | float or null | see limitations |
| `estimatedRPE` | float or null | 0.5 steps; needs ≥ 3 reps |
| `velocityLossPct` | float or null | needs ≥ 3 reps |
| `restBeforeSec` | float or null | `startedAt − previousSetEndedAt` |
| `idleSecInVideo` | float | before the first rep + after the last rep |
| `setDurationSec` | float | `endedAt − startedAt`, or the video length if those are missing |
| `framesAnalyzed` | int | |
| `poseVisibility` | float 0-1 | mean landmark visibility |
| `coachingTip` | string | one sentence |

Form issue codes: `insufficient_depth`, `excessive_lean`, `knee_valgus`,
`back_rounding`, `elbow_flare`, `hip_shift`, `lockout_incomplete`,
`asymmetry`, plus `hip_sag`, `elbow_drift`, `partial_reps`, `fast_eccentric`,
`low_visibility`, `no_reps_detected`. The app should show `message` for
codes it does not know.

**Client writes to set docs:** the Firestore rules reject any client write
that touches `status`, `error`, `analyzedAt` or `analysis`. When the app
writes its own fields on a set doc it must use `setData(..., merge: true)` or
`updateData`; a full overwrite would delete the server fields and be denied.

## Deploy

Prerequisites: Firebase CLI (`npm i -g firebase-tools`), `gcloud`, a Firebase
project on the Blaze plan with Firestore and Storage enabled.

```bash
cd backend
cp .firebaserc.example .firebaserc        # put your project id in it
PROJECT=$(python3 -c "import json;print(json.load(open('.firebaserc'))['projects']['default'])")
REGION=us-central1

# 1. Analyzer on Cloud Run (private)
gcloud run deploy set-analyzer \
  --project "$PROJECT" --region "$REGION" \
  --source analyzer \
  --no-allow-unauthenticated \
  --memory 4Gi --cpu 2 --timeout 600 --concurrency 1 --max-instances 10

ANALYZER_URL=$(gcloud run services describe set-analyzer --project "$PROJECT" \
  --region "$REGION" --format 'value(status.url)')

# Cloud Run reads the videos with its runtime service account:
#   grant it roles/storage.objectViewer on the bucket if it differs from the
#   default compute service account.

# 2. Let the function's service account call Cloud Run
#    (2nd gen functions run as the default compute service account unless set otherwise)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format 'value(projectNumber)')
gcloud run services add-iam-policy-binding set-analyzer \
  --project "$PROJECT" --region "$REGION" \
  --member "serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role roles/run.invoker

# 3. Function + rules + indexes
echo "ANALYZER_URL=$ANALYZER_URL" > functions/.env
python3.12 -m venv functions/venv
functions/venv/bin/pip install -r functions/requirements.txt
firebase deploy --only functions,firestore,storage
```

The function is deployed in `us-central1` (the SDK default); keep the default
Storage bucket in a compatible location or pass `region=` in the decorator.

## Local emulator

Without `ANALYZER_URL` the function imports `../analyzer` and analyses
in-process, so the emulator venv needs the heavy dependencies too:

```bash
cd backend
python3.12 -m venv functions/venv
functions/venv/bin/pip install -r functions/requirements.txt -r analyzer/requirements.txt
# MediaPipe Tasks model (otherwise the legacy solutions API is used if available)
curl -fsSL -o /tmp/pose_landmarker_full.task \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task
export POSE_MODEL_PATH=/tmp/pose_landmarker_full.task
firebase emulators:start --only functions,firestore,storage,auth
```

Point the iOS app at the emulators (`Auth.auth().useEmulator`,
`Firestore` settings host `localhost:8080`, `Storage.storage().useEmulator`
port 9199). Uploads to `videos/...` trigger the function and the set doc
updates in the Emulator UI.

Run the analyzer service alone:

```bash
cd backend
pip install -r analyzer/requirements.txt
uvicorn analyzer.server:app --port 8081
```

Analyse a local file from Python:

```python
from analyzer.pipeline import analyze_video
analyze_video("set.mov", {"exerciseId": "squat", "loggedWeightKg": "100", "plannedReps": "5"})
```

## Tests

The tests feed synthetic landmark sequences (stick figures built from joint
angles) through features → classify → reps → form → load → pipeline. They
need only numpy and pytest, no MediaPipe or OpenCV:

```bash
cd backend
python3 -m pip install numpy pytest
python3 -m pytest
```

## Limitations

- **One camera, 2D.** Angles are measured in the image plane. A **side view**
  with the whole body in frame is recommended and is what most checks
  assume. Knee valgus, hip shift, elbow flare and left/right asymmetry need a
  **frontal view** and are only checked when one is detected. Rotation of the
  joints out of the image plane distorts angles.
- **Weight is not seen in the video.** `estimatedWeightKg` is the logged
  weight; for pull-ups and push-ups with `bodyMassKg` it is body mass × the
  fraction moved (1.0 / 0.64) plus any logged added weight. Plate or dumbbell
  detection is not implemented: `load.estimate_load_from_frames` is a
  marked hook that returns `None`.
- **RPE is a heuristic.** It maps velocity loss (slowdown of the concentric
  phase's joint angular velocity, a proxy for bar speed, not a calibrated
  m/s value) to RPE: about 10 % → 7, 20 % → 8, 30 % → 9, 40 %+ → 10. A rep left
  unfinished at the end (outside deadlifts and presses, where ending at the
  bottom is normal) is treated as failure (RPE 10).
- **Back rounding** cannot be seen with 33 landmarks; it is flagged as
  *possible* when the shoulder-hip distance shrinks noticeably.
- **Classification** is rule-based. Similar movements (squat vs. deadlift
  with a lot of knee bend, curl vs. row when upright) can be confused; the
  app's `exerciseId` prior resolves most of these. Exercises outside the
  list come back as `unknown`, with reps counted on the joint that moves most.
- Pose quality drops with poor lighting, baggy clothing, heavy occlusion by
  the bar or rack, or more than one person in frame (only one pose is tracked).
- Thresholds are tuned on synthetic sequences and common coaching cues, not a
  labelled dataset; treat scores as guidance.
