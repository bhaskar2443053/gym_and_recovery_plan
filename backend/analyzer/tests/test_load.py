from analyzer.load import (
    estimate_load_from_frames, estimate_rpe, estimate_weight_kg, rest_before_sec,
    seconds_between, velocity_loss_pct,
)
from analyzer.reps import Rep, RepResult


def make_result(concentric_secs, rom=90.0):
    reps, t = [], 0.0
    for c in concentric_secs:
        reps.append(Rep(0, 0, 0, t, t + 1.0, t + 1.0 + c, rom, True, 1.0, c))
        t += 1.0 + c + 0.5
    return RepResult(reps=reps, signal_range=rom)


def test_velocity_loss_and_rpe_increase_with_slowdown():
    easy = make_result([0.8, 0.8, 0.82, 0.83, 0.84])
    hard = make_result([0.8, 0.85, 0.95, 1.1, 1.4])
    vl_easy, vl_hard = velocity_loss_pct(easy), velocity_loss_pct(hard)
    assert vl_easy < 10 < 30 < vl_hard
    rpe_easy = estimate_rpe(easy, "squat", vl_easy)
    rpe_hard = estimate_rpe(hard, "squat", vl_hard)
    assert rpe_easy < rpe_hard <= 10
    assert rpe_hard * 2 == int(rpe_hard * 2)  # rounded to 0.5


def test_too_few_reps_no_velocity_loss():
    r = make_result([0.8, 0.9])
    assert velocity_loss_pct(r) is None
    assert estimate_rpe(r, "squat", None) is None


def test_unfinished_rep_means_failure():
    r = make_result([0.8, 0.9, 1.0])
    r.unfinished = Rep(0, 0, 0, 10, 11, 12, 60, False, 1, 1)
    assert estimate_rpe(r, "squat", velocity_loss_pct(r)) == 10.0
    assert estimate_rpe(r, "deadlift", velocity_loss_pct(r)) != 10.0


def test_weight_estimates():
    assert estimate_weight_kg("squat", 100.0, 80.0) == 100.0
    assert estimate_weight_kg("pull_up", 10.0, 80.0) == 90.0
    assert estimate_weight_kg("push_up", None, 80.0) == 51.2
    assert estimate_weight_kg("squat", None, None) is None
    assert estimate_load_from_frames() is None


def test_rest_before():
    assert rest_before_sec("2026-10-04T10:02:30Z", "2026-10-04T10:00:00Z") == 150.0
    assert rest_before_sec("2026-10-04T10:02:30+00:00", "") is None
    assert rest_before_sec("2026-10-04T10:00:00Z", "2026-10-04T10:02:30Z") is None
    assert seconds_between("2026-10-04T10:00:40.500Z", "2026-10-04T10:00:00Z") == 40.5
