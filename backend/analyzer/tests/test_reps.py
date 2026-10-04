import numpy as np

from analyzer.exercises import SPECS
from analyzer.features import compute_features
from analyzer.reps import count_reps, rom_score
from analyzer.tests.synth import make_set, squat_pose


def knee_sinusoid(reps=5, fps=15.0, top=175.0, bottom=80.0, idle=1.0, noise=0.0, seed=0):
    rep_sec = 2.0
    t_active = np.arange(int(reps * rep_sec * fps)) / fps
    phase = (1 - np.cos(2 * np.pi * t_active / rep_sec)) / 2
    knee = np.concatenate([
        np.full(int(idle * fps), top),
        top - (top - bottom) * phase,
        np.full(int(idle * fps), top),
    ])
    rng = np.random.default_rng(seed)
    knee = knee + rng.normal(0, noise, len(knee))
    t = np.arange(len(knee)) / fps
    return t, knee


def test_five_rep_sinusoid():
    t, knee = knee_sinusoid(5)
    rr = count_reps(t, knee, SPECS["squat"])
    assert len(rr.full_reps) == 5
    assert len(rr.partial_reps) == 0
    expected = 1.0 + 1.0 + 2.0 * np.arange(5)   # idle + half a rep + period
    np.testing.assert_allclose(rr.rep_timestamps, expected, atol=0.1)
    tempo = rr.tempo()
    assert abs(tempo["eccentricSec"] - 1.0) < 0.25
    assert abs(tempo["concentricSec"] - 1.0) < 0.25
    assert abs(rr.avg_rep_duration() - 2.0) < 0.3


def test_noisy_sinusoid_after_smoothing_still_counts_five():
    from analyzer.features import savgol_smooth
    t, knee = knee_sinusoid(5, noise=4.0, seed=3)
    rr = count_reps(t, savgol_smooth(knee, 7, 2), SPECS["squat"])
    assert len(rr.full_reps) == 5


def test_partial_reps_are_separated():
    seq = make_set(lambda w: squat_pose(w, depth_knee=75), reps=6,
                   depths=[1, 1, 1, 1, 0.45, 0.45])
    f = compute_features(seq)
    rr = count_reps(f.t, f["knee"], SPECS["squat"])
    assert len(rr.full_reps) == 4
    assert len(rr.partial_reps) == 2


def test_tempo_asymmetric_eccentric():
    seq = make_set(squat_pose, reps=4, rep_sec=3.0, ecc_frac=2 / 3)
    f = compute_features(seq)
    rr = count_reps(f.t, f["knee"], SPECS["squat"])
    tempo = rr.tempo()
    assert len(rr.full_reps) == 4
    assert tempo["eccentricSec"] > tempo["concentricSec"] * 1.4


def test_flat_signal_has_no_reps():
    t = np.arange(60) / 15
    rr = count_reps(t, np.full(60, 170.0) + np.random.default_rng(1).normal(0, 1, 60), SPECS["squat"])
    assert rr.reps == []
    assert rom_score(rr, SPECS["squat"]) == 0


def test_set_starting_at_bottom_counts_all_reps():
    # Deadlift-like: video starts with the bar on the floor (hip flexed)
    fps = 15
    period = 2.0
    t = np.arange(int(5 * period * fps)) / fps
    hip = 120 - 55 * np.cos(2 * np.pi * t / period)  # starts at 65 deg (bottom)
    rr = count_reps(t, hip, SPECS["deadlift"])
    assert len(rr.full_reps) == 5
