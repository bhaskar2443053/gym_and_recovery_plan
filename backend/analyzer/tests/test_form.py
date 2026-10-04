from analyzer.exercises import SPECS
from analyzer.features import compute_features
from analyzer.form import check_form
from analyzer.reps import count_reps
from analyzer.tests import synth


def _run(pose_fn, exercise, **kw):
    f = compute_features(synth.make_set(pose_fn, **kw))
    rr = count_reps(f.t, f[SPECS[exercise].signal], SPECS[exercise])
    return check_form(f, exercise, rr)


def codes(issues):
    return {i["code"] for i in issues}


def test_deep_upright_squat_scores_high():
    issues, score = _run(lambda w: synth.squat_pose(w, depth_knee=75, lean_bottom=35), "squat")
    assert "insufficient_depth" not in codes(issues)
    assert "excessive_lean" not in codes(issues)
    assert score >= 85


def test_shallow_squat_flags_depth():
    issues, score = _run(lambda w: synth.squat_pose(w, depth_knee=125, lean_bottom=25), "squat")
    depth = [i for i in issues if i["code"] == "insufficient_depth"]
    assert depth and depth[0]["severity"] in ("medium", "high")
    assert isinstance(depth[0]["atSec"], float)
    assert score < 90


def test_forward_lean_flagged():
    issues, _ = _run(lambda w: synth.squat_pose(w, depth_knee=75, lean_bottom=65), "squat")
    assert "excessive_lean" in codes(issues)


def test_shallow_push_up_and_partial_lockout():
    def shallow(w):
        return synth.push_up_pose(w * 0.4)
    issues, _ = _run(shallow, "push_up")
    assert "insufficient_depth" in codes(issues)


def test_issue_shape():
    issues, score = _run(lambda w: synth.squat_pose(w, depth_knee=130, lean_bottom=60), "squat")
    assert 0 <= score <= 100
    for i in issues:
        assert set(i) == {"code", "severity", "message", "atSec"}
        assert i["severity"] in ("low", "medium", "high")
        assert isinstance(i["message"], str) and i["message"]


def test_no_reps_gives_zero_score():
    issues, score = _run(lambda w: synth.squat_pose(0.0), "squat", reps=3)
    assert score == 0
    assert "no_reps_detected" in codes(issues)
