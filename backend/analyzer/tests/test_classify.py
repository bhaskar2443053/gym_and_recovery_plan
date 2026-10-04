import pytest

from analyzer.classify import classify, classify_detailed, orientation
from analyzer.features import compute_features
from analyzer.tests import synth


CASES = [
    ("squat", synth.squat_pose),
    ("deadlift", synth.deadlift_pose),
    ("romanian_deadlift", synth.rdl_pose),
    ("bicep_curl", synth.curl_pose),
    ("barbell_row", synth.row_pose),
    ("overhead_press", synth.ohp_pose),
    ("pull_up", synth.pull_up_pose),
    ("bench_press", synth.bench_pose),
    ("push_up", synth.push_up_pose),
]


@pytest.mark.parametrize("expected,pose_fn", CASES, ids=[c[0] for c in CASES])
def test_classifies_without_prior(expected, pose_fn):
    f = compute_features(synth.make_set(pose_fn, reps=5, noise=0.002))
    exercise, conf = classify(f)
    assert exercise == expected, classify_detailed(f)["scores"]
    assert 0.3 < conf <= 1.0


def test_orientations():
    assert orientation(compute_features(synth.make_set(synth.squat_pose))) == "standing"
    assert orientation(compute_features(synth.make_set(synth.bench_pose))) == "supine"
    assert orientation(compute_features(synth.make_set(synth.push_up_pose))) == "prone"
    assert orientation(compute_features(synth.make_set(synth.pull_up_pose))) == "hanging"


def test_prior_breaks_ties_but_not_clear_evidence():
    f = compute_features(synth.make_set(synth.squat_pose, reps=5))
    # Planned squat: confirmed, higher confidence than without prior.
    ex, conf_prior = classify(f, "squat")
    _, conf_plain = classify(f)
    assert ex == "squat" and conf_prior >= conf_plain
    # Planned bench press but the video clearly shows a squat.
    ex, _ = classify(f, "bench_press")
    assert ex == "squat"


def test_prior_used_for_alias_ids():
    f = compute_features(synth.make_set(synth.deadlift_pose))
    assert classify_detailed(f, "RDL")["planned"] == "romanian_deadlift"


def test_still_person_is_unknown():
    f = compute_features(synth.make_set(lambda w: synth.squat_pose(0.0), reps=3))
    assert classify(f)[0] == "unknown"
