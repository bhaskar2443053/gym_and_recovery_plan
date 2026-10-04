# Forge: gym and recovery plan

An iOS app (with Apple Watch companion) that plans your training, records a video of every set, analyses it in the cloud, and builds a recovery plan around what you actually did.

- **Plan**: weekly split, sets, reps, rest and working weights from your goal, experience and 1RMs.
- **Record**: one video per set, live pose skeleton and rep count, live heart rate from the Watch, rest timer.
- **Analyse** (cloud): exercise type, reps and partial reps, tempo, range of motion, form score and issues, estimated RPE from rep-speed loss, load, rest time.
- **Recover**: stretches for the muscles you loaded, protein/carb/water targets, and sauna, massage, meditation or similar based on readiness (HRV, resting HR, sleep) and session intensity.

| Folder | |
| --- | --- |
| [`ios/`](ios/README.md) | SwiftUI iPhone app + watchOS app (XcodeGen project) |
| [`backend/`](backend/README.md) | Firebase Storage trigger + Cloud Run pose-analysis service (MediaPipe) |
