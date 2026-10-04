import numpy as np

from analyzer.features import (
    angle_from_vertical, compute_features, fill_nans, joint_angle, moving_average, savgol_smooth,
)
from analyzer.tests.synth import make_set, squat_pose


def test_joint_angle_right_angle_and_straight():
    a = np.array([[0.0, 0.0], [0.0, 0.0]])
    b = np.array([[1.0, 0.0], [1.0, 0.0]])
    c = np.array([[1.0, 1.0], [2.0, 0.0]])
    np.testing.assert_allclose(joint_angle(a, b, c), [90.0, 180.0], atol=1e-9)


def test_angle_from_vertical_image_coords():
    hip = np.array([[0.5, 0.5], [0.5, 0.5]])
    shoulder = np.array([[0.5, 0.2], [0.8, 0.5]])  # upright, horizontal
    np.testing.assert_allclose(angle_from_vertical(shoulder, hip), [0.0, 90.0], atol=1e-9)


def test_fill_nans_interpolates_and_holds_edges():
    x = np.array([np.nan, 1.0, np.nan, 3.0, np.nan])
    np.testing.assert_allclose(fill_nans(x), [1, 1, 2, 3, 3])


def test_savgol_preserves_quadratic_and_reduces_noise():
    t = np.linspace(-1, 1, 101)
    q = 3 * t**2 - t + 2
    np.testing.assert_allclose(savgol_smooth(q, 9, 2)[5:-5], q[5:-5], atol=1e-9)
    rng = np.random.default_rng(0)
    noisy = np.sin(t * 3) + rng.normal(0, 0.1, len(t))
    assert np.std(savgol_smooth(noisy, 11, 2) - np.sin(t * 3)) < np.std(noisy - np.sin(t * 3))
    assert len(moving_average(noisy, 5)) == len(noisy)


def test_compute_features_squat_angles():
    seq = make_set(lambda w: squat_pose(w, depth_knee=70), reps=3)
    f = compute_features(seq)
    assert f.view == "side"
    assert f.side == "left"
    assert f["knee"].min() < 80
    assert f["knee"].max() > 170
    assert f.rom("knee") > 80
    assert f.median("trunk_lean") < 45
