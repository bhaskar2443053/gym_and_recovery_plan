# Forge iOS + watchOS

SwiftUI app (iOS 17+) with a watchOS 10 companion.

## Run it

```sh
brew install xcodegen
cd ios
xcodegen generate
open Forge.xcodeproj
```

Set your team under Signing for the `Forge` and `ForgeWatch` targets, then run on a device (the camera and HealthKit don't work in the simulator).

Without a `GoogleService-Info.plist` the app uses `MockAnalysisBackend`, which fakes an analysis two seconds after each set. To use the real cloud pipeline, create a Firebase project (see `../backend/README.md`), download `GoogleService-Info.plist` and drop it into `ios/Forge/Resources/` (it is git-ignored).

## Layout

| Path | What it does |
| --- | --- |
| `Forge/Models` | Exercises, plans, set records, cloud analysis (`SetAnalysis` mirrors the backend contract), recovery plans |
| `Forge/Services/PlanGenerator.swift` | Builds the weekly split, sets, reps, rest and working weights from goal, experience and 1RMs, with weekly progression and a deload every 4th week |
| `Forge/Services/RecoveryPlanner.swift` | Workout-specific stretches from muscle load, protein and carb targets from body mass and volume, and relaxation (sauna, massage, meditation, yoga nidra, walk, cold plunge) based on readiness and session intensity |
| `Forge/Services/SetVideoRecorder.swift` | AVCaptureSession + AVAssetWriter per-set recording (HEVC 1080p) with on-device Vision pose for the live skeleton and live rep count |
| `Forge/Services/FirebaseAnalysisBackend.swift` | Uploads each set to Storage with metadata, then listens to the Firestore doc for the analysis |
| `Forge/Services/HealthKitManager.swift` | Readiness (HRV, resting HR, sleep vs 30-day baseline), body mass, and heart rate for each set's time window |
| `Forge/Services/PhoneWatchConnector.swift` | WatchConnectivity: set start/end to the Watch, live heart rate and "Set done" taps back |
| `ForgeWatch` | HKWorkoutSession (traditional strength training), live HR and zones, rest timer with haptics, "Set done" button |
| `Shared/WatchMessage.swift` | Message schema shared by both apps |

## How a set flows

1. Today tab → **Record set**. The phone tells the Watch which set is starting; the Watch starts a strength workout if needed.
2. Recording runs until you tap stop on the phone or **Set done** on the Watch.
3. The set's heart rate (avg/max) is read from HealthKit for that time window, then the video uploads to `videos/{uid}/{sessionId}/{setId}.mov`.
4. The backend writes `status` and `analysis` to `users/{uid}/sessions/{sessionId}/sets/{setId}`; the rest screen and Insights update live.
5. **Finish workout** builds the recovery plan from the session's muscle load, estimated RPE, peak heart rate and readiness.

## Tests

`ForgeTests` covers plan generation, the recovery planner, and the app ↔ backend contract. CI (`.github/workflows/ios.yml`) generates the project and runs them on an iOS simulator.
