import json
import sys

import pytest

from analyzer.pipeline import ANALYSIS_KEYS, AnalysisError, SetMetadata, analyze_pose_sequence
from analyzer.tests import synth

EXERCISES = {
    "squat", "deadlift", "bench_press", "overhead_press", "barbell_row", "pull_up", "push_up",
    "lunge", "bicep_curl", "romanian_deadlift", "hip_thrust", "lateral_raise", "unknown",
}

META = {
    "exerciseId": "squat",
    "exerciseName": "Back Squat",
    "plannedReps": "5",
    "loggedWeightKg": "100",
    "setIndex": "2",
    "startedAt": "2026-10-04T10:03:00Z",
    "endedAt": "2026-10-04T10:03:13Z",
    "previousSetEndedAt": "2026-10-04T10:00:30Z",
    "bodyMassKg": "82.5",
    "heartRateAvg": "121",
    "heartRateMax": "",
}


def check_contract(a):
    assert tuple(a.keys()) == ANALYSIS_KEYS
    assert a["detectedExercise"] in EXERCISES
    assert 0.0 <= a["exerciseConfidence"] <= 1.0
    assert isinstance(a["reps"], int) and isinstance(a["partialReps"], int)
    assert all(isinstance(x, float) for x in a["repTimestamps"])
    assert isinstance(a["avgRepDurationSec"], float)
    assert set(a["tempo"]) == {"eccentricSec", "concentricSec"}
    assert all(isinstance(v, float) for v in a["tempo"].values())
    assert isinstance(a["rangeOfMotionScore"], int) and 0 <= a["rangeOfMotionScore"] <= 100
    assert isinstance(a["formScore"], int) and 0 <= a["formScore"] <= 100
    for i in a["formIssues"]:
        assert set(i) == {"code", "severity", "message", "atSec"}
        assert i["severity"] in ("low", "medium", "high")
        assert i["atSec"] is None or isinstance(i["atSec"], float)
    for k in ("estimatedWeightKg", "estimatedRPE", "velocityLossPct", "restBeforeSec"):
        assert a[k] is None or isinstance(a[k], float)
    assert isinstance(a["idleSecInVideo"], float)
    assert isinstance(a["setDurationSec"], float)
    assert isinstance(a["framesAnalyzed"], int)
    assert 0.0 <= a["poseVisibility"] <= 1.0
    assert isinstance(a["coachingTip"], str) and a["coachingTip"]
    json.dumps(a)  # plain types only


def test_squat_end_to_end():
    seq = synth.make_set(synth.squat_pose, reps=5, noise=0.002, idle_start=1.5, idle_end=1.0)
    a = analyze_pose_sequence(seq, META)
    check_contract(a)
    assert a["detectedExercise"] == "squat"
    assert a["reps"] == 5
    assert a["partialReps"] == 0
    assert len(a["repTimestamps"]) == 5
    assert a["estimatedWeightKg"] == 100.0
    assert a["restBeforeSec"] == 150.0
    assert a["setDurationSec"] == 13.0
    assert 1.5 < a["idleSecInVideo"] < 3.5
    assert a["framesAnalyzed"] == seq.num_frames
    assert a["rangeOfMotionScore"] >= 90


def test_without_metadata():
    a = analyze_pose_sequence(synth.make_set(synth.curl_pose, reps=8))
    check_contract(a)
    assert a["detectedExercise"] == "bicep_curl"
    assert a["reps"] == 8
    assert a["estimatedWeightKg"] is None
    assert a["restBeforeSec"] is None


def test_metadata_parsing_is_lenient():
    m = SetMetadata.from_custom_metadata({"plannedReps": "x", "loggedWeightKg": " 62.5 ",
                                          "previousSetEndedAt": ""})
    assert m.planned_reps is None and m.logged_weight_kg == 62.5
    assert m.previous_set_ended_at is None


def test_invisible_person_raises():
    seq = synth.make_set(synth.squat_pose, reps=2)
    seq.landmarks[:, :, 3] = 0.0
    with pytest.raises(AnalysisError):
        analyze_pose_sequence(seq, META)


def test_pure_modules_do_not_import_heavy_deps():
    import analyzer.pipeline  # noqa: F401
    assert "mediapipe" not in sys.modules
    assert "cv2" not in sys.modules
