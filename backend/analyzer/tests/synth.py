"""Synthetic BlazePose landmark sequences for tests (no video, no MediaPipe).

A 2D stick figure is built from segment angles in a math frame (y up, the
athlete faces +x), optionally rotated as a whole (lying / push-up), then
converted to normalised image coordinates (y down). Both body sides share
the same 2D points, as in a side view; the far side gets lower visibility.
"""

from __future__ import annotations

import numpy as np

from analyzer.pose import (
    L_ANKLE, L_ELBOW, L_HIP, L_KNEE, L_SHOULDER, L_WRIST, NOSE, NUM_LANDMARKS,
    R_ANKLE, R_ELBOW, R_HIP, R_KNEE, R_SHOULDER, R_WRIST, PoseSequence,
)

SHIN, THIGH, TORSO, UPPER_ARM, FOREARM = 0.20, 0.21, 0.25, 0.14, 0.13


def _rot(v, deg):
    r = np.radians(deg)
    c, s = np.cos(r), np.sin(r)
    return np.array([c * v[0] - s * v[1], s * v[0] + c * v[1]])


def _unit(deg_from_up_toward_forward):
    """Direction at an angle from straight up, tilted toward +x (forward)."""
    r = np.radians(deg_from_up_toward_forward)
    return np.array([np.sin(r), np.cos(r)])


def skeleton(shin=0.0, thigh=0.0, lean=0.0, arm=0.0, elbow=180.0, arm_abs=None,
             body_rot=0.0):
    """Return dict of 2D points (math frame) for one pose.

    shin:  forward tilt of the shin from vertical (deg).
    thigh: backward tilt of the thigh from vertical (deg).
    lean:  forward tilt of the torso from vertical (deg).
    arm:   shoulder flexion: 0 = arm along torso pointing to hips, 90 = forward,
           180 = overhead (relative to the torso).
    elbow: elbow angle (180 = straight); the forearm folds forward/up.
    arm_abs: if given, absolute arm direction in degrees from straight *down*
           toward forward (overrides ``arm``), e.g. 0 = hanging under gravity.
    body_rot: rotate the whole figure about the ankle (deg, CCW positive).
    """
    A = np.zeros(2)
    K = A + SHIN * _unit(shin)
    H = K + THIGH * _unit(-thigh)
    torso_dir = _unit(lean)
    S = H + TORSO * torso_dir
    if arm_abs is not None:
        arm_dir = _rot(np.array([0.0, -1.0]), arm_abs)
    else:
        arm_dir = _rot(-torso_dir, arm)
    E = S + UPPER_ARM * arm_dir
    W = E + FOREARM * _rot(arm_dir, 180.0 - elbow)
    N = S + 0.09 * torso_dir + 0.03 * _rot(torso_dir, -90)
    pts = {"ankle": A, "knee": K, "hip": H, "shoulder": S, "elbow": E, "wrist": W, "nose": N}
    if body_rot:
        pts = {k: _rot(v, body_rot) for k, v in pts.items()}
    return pts


def frames_to_sequence(poses, fps=15.0, origin=(0.5, 0.9), noise=0.0, seed=0,
                       far_side_visibility=0.6, frontal_width=0.0):
    """Turn a list of skeleton dicts into a PoseSequence.

    frontal_width > 0 offsets left/right points horizontally (a crude frontal
    view) so that shoulder width is visible.
    """
    rng = np.random.default_rng(seed)
    T = len(poses)
    lm = np.zeros((T, NUM_LANDMARKS, 4))
    lm[:, :, 3] = 0.2
    pairs = {
        "shoulder": (L_SHOULDER, R_SHOULDER), "elbow": (L_ELBOW, R_ELBOW),
        "wrist": (L_WRIST, R_WRIST), "hip": (L_HIP, R_HIP),
        "knee": (L_KNEE, R_KNEE), "ankle": (L_ANKLE, R_ANKLE),
    }
    for i, p in enumerate(poses):
        for name, (li, ri) in pairs.items():
            x, y = origin[0] + p[name][0], origin[1] - p[name][1]
            half = frontal_width / 2
            lm[i, li] = (x - half, y, 0.0, 0.95)
            lm[i, ri] = (x + half, y, 0.1, far_side_visibility if not frontal_width else 0.95)
        x, y = origin[0] + p["nose"][0], origin[1] - p["nose"][1]
        lm[i, NOSE] = (x, y, 0.0, 0.95)
        # fill the remaining landmarks with something finite
        for j in range(NUM_LANDMARKS):
            if lm[i, j, 3] == 0.2:
                lm[i, j, :3] = lm[i, NOSE, :3]
    if noise:
        lm[:, :, :2] += rng.normal(0, noise, size=(T, NUM_LANDMARKS, 2))
    t = np.arange(T) / fps
    return PoseSequence(landmarks=lm, timestamps=t, aspect=1.0, duration=float(t[-1]))


def rep_wave(reps, fps=15.0, rep_sec=2.0, idle_start=1.0, idle_end=1.0,
             depths=None, ecc_frac=0.5):
    """Phase signal in [0, 1]: 0 = rest, 1 = rep event, one bump per rep.

    ecc_frac: fraction of each rep spent going 0 -> 1 (the rest 1 -> 0).
    depths: optional per-rep amplitude (partial reps < 1).
    """
    depths = depths if depths is not None else [1.0] * reps
    segs = [np.zeros(int(round(idle_start * fps)))]
    for d, sec in zip(depths, rep_sec if np.ndim(rep_sec) else [rep_sec] * len(depths)):
        n = int(round(sec * fps))
        n_down = max(2, int(round(n * ecc_frac)))
        n_up = max(2, n - n_down)
        down = (1 - np.cos(np.linspace(0, np.pi, n_down, endpoint=False))) / 2
        up = (1 + np.cos(np.linspace(0, np.pi, n_up, endpoint=False))) / 2
        segs.append(d * np.concatenate([down, up]))
    segs.append(np.zeros(int(round(idle_end * fps))))
    return np.concatenate(segs)


def lerp(a, b, w):
    return a + (b - a) * w


# --------------------------------------------------------------------------- #
# Exercise generators: phase w in [0,1] -> skeleton
# --------------------------------------------------------------------------- #

def squat_pose(w, depth_knee=70.0, lean_bottom=40.0):
    # knee angle = 180 - shin - thigh. Bottom: thigh ~ 70 % of the bend.
    bend = (180.0 - depth_knee) * w
    shin, thigh = 0.38 * bend, 0.62 * bend
    return skeleton(shin=shin, thigh=thigh, lean=lerp(8, lean_bottom, w), arm=150, elbow=40)


def deadlift_pose(w):
    # w = 0 standing tall, 1 = bar on the floor
    return skeleton(shin=lerp(0, 22, w), thigh=lerp(0, 45, w), lean=lerp(3, 75, w), arm_abs=0)


def rdl_pose(w):
    return skeleton(shin=8, thigh=lerp(5, 12, w), lean=lerp(3, 75, w), arm_abs=0)


def curl_pose(w):
    return skeleton(arm=5, elbow=lerp(165, 45, w), lean=3)


def row_pose(w):
    return skeleton(shin=12, thigh=25, lean=60, arm_abs=lerp(0, -35, w), elbow=lerp(170, 75, w))


def ohp_pose(w):
    # w = 0 locked out overhead, 1 = bar at the shoulders
    return skeleton(arm=lerp(175, 75, w), elbow=lerp(175, 55, w), lean=4)


def pull_up_pose(w):
    p = skeleton(arm=lerp(175, 165, w), elbow=lerp(170, 60, w), shin=0, thigh=10, lean=-5)
    # Keep the wrists fixed on the bar: translate the body.
    ref = skeleton(arm=175, elbow=170, thigh=10, lean=-5)["wrist"]
    shift = ref - p["wrist"]
    return {k: v + shift for k, v in p.items()}


def bench_pose(w):
    # supine: rotate CCW 90 so the chest faces up; arms point "forward" = up
    return skeleton(arm=lerp(88, 70, w), elbow=lerp(170, 75, w), body_rot=90)


def push_up_pose(w):
    # prone, body inclined: rotate CW so the chest faces the floor
    return skeleton(arm=lerp(85, 60, w), elbow=lerp(170, 80, w), body_rot=-lerp(78, 86, w))


def make_set(pose_fn, reps=5, fps=15.0, noise=0.0, depths=None, rep_sec=2.0,
             ecc_frac=0.5, idle_start=1.0, idle_end=1.0, **seq_kw):
    w = rep_wave(reps, fps, rep_sec, idle_start, idle_end, depths, ecc_frac)
    poses = [pose_fn(x) for x in w]
    return frames_to_sequence(poses, fps=fps, noise=noise, **seq_kw)
