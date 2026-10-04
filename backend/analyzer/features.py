"""Joint angles and normalised positions from a :class:`PoseSequence`.

numpy only. Angles are in degrees and computed in the image plane (2D): the
MediaPipe z coordinate is too noisy for single-camera depth, and a side view
puts the joints that matter for most lifts in that plane anyway.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .pose import (
    L_ANKLE, L_ELBOW, L_HIP, L_KNEE, L_SHOULDER, L_WRIST, NOSE,
    R_ANKLE, R_ELBOW, R_HIP, R_KNEE, R_SHOULDER, R_WRIST,
    PoseSequence,
)

MIN_LANDMARK_VISIBILITY = 0.3
KEY_LANDMARKS = (
    L_SHOULDER, R_SHOULDER, L_ELBOW, R_ELBOW, L_WRIST, R_WRIST,
    L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE,
)
LEFT_CHAIN = (L_SHOULDER, L_ELBOW, L_WRIST, L_HIP, L_KNEE, L_ANKLE)
RIGHT_CHAIN = (R_SHOULDER, R_ELBOW, R_WRIST, R_HIP, R_KNEE, R_ANKLE)


# --------------------------------------------------------------------------- #
# Signal helpers
# --------------------------------------------------------------------------- #

def fill_nans(x: np.ndarray) -> np.ndarray:
    """Linear interpolation over NaNs, edge values held. All-NaN stays NaN."""
    x = np.asarray(x, dtype=float).copy()
    bad = ~np.isfinite(x)
    if not bad.any() or bad.all():
        return x
    idx = np.arange(len(x))
    x[bad] = np.interp(idx[bad], idx[~bad], x[~bad])
    return x


def savgol_coeffs(window: int, order: int) -> np.ndarray:
    """Savitzky-Golay smoothing coefficients (centre point, 0th derivative)."""
    if window % 2 == 0 or window < 3:
        raise ValueError("window must be odd and >= 3")
    if order >= window:
        raise ValueError("order must be < window")
    half = window // 2
    pos = np.arange(-half, half + 1, dtype=float)
    vander = np.vander(pos, order + 1, increasing=True)  # (window, order+1)
    return np.linalg.pinv(vander)[0]


def savgol_smooth(x: np.ndarray, window: int = 7, order: int = 2) -> np.ndarray:
    """Savitzky-Golay filter with reflected edges; NaNs are interpolated first."""
    x = fill_nans(x)
    n = len(x)
    if n == 0 or not np.isfinite(x).any():
        return x
    window = min(window, n if n % 2 == 1 else n - 1)
    if window < 3:
        return x
    order = min(order, window - 1)
    half = window // 2
    padded = np.concatenate([x[half:0:-1], x, x[-2:-half - 2:-1]])
    return np.convolve(padded, savgol_coeffs(window, order)[::-1], mode="valid")


def moving_average(x: np.ndarray, window: int = 5) -> np.ndarray:
    x = fill_nans(x)
    if window <= 1 or len(x) < window:
        return x
    kernel = np.ones(window) / window
    half = window // 2
    padded = np.pad(x, (half, window - 1 - half), mode="edge")
    return np.convolve(padded, kernel, mode="valid")


def smoothing_window(fps: float, seconds: float = 0.35) -> int:
    w = int(round(fps * seconds))
    w = max(5, w)
    return w if w % 2 == 1 else w + 1


def joint_angle(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> np.ndarray:
    """Angle ABC in degrees for arrays of 2D points shaped (T, 2)."""
    ba = a - b
    bc = c - b
    dot = np.sum(ba * bc, axis=-1)
    norm = np.linalg.norm(ba, axis=-1) * np.linalg.norm(bc, axis=-1)
    with np.errstate(invalid="ignore", divide="ignore"):
        cos = np.clip(dot / norm, -1.0, 1.0)
    return np.degrees(np.arccos(cos))


def angle_from_vertical(top: np.ndarray, bottom: np.ndarray) -> np.ndarray:
    """Angle of the bottom->top vector from straight up (image y points down).

    0 = upright, 90 = horizontal, 180 = upside down.
    """
    v = top - bottom
    up = np.array([0.0, -1.0])
    norm = np.linalg.norm(v, axis=-1)
    with np.errstate(invalid="ignore", divide="ignore"):
        cos = np.clip((v @ up) / norm, -1.0, 1.0)
    return np.degrees(np.arccos(cos))


# --------------------------------------------------------------------------- #
# Feature extraction
# --------------------------------------------------------------------------- #

@dataclass
class Features:
    t: np.ndarray
    fps: float
    visibility: np.ndarray            # per-frame mean visibility of key joints
    side: str                         # "left" / "right": camera-facing side
    view: str                         # "side" / "frontal"
    torso_len: float                  # median shoulder-hip distance (image units)
    series: dict[str, np.ndarray] = field(default_factory=dict)

    def __getitem__(self, name: str) -> np.ndarray:
        return self.series[name]

    def __contains__(self, name: str) -> bool:
        return name in self.series

    @property
    def n(self) -> int:
        return len(self.t)

    def rom(self, name: str, lo: float = 5, hi: float = 95) -> float:
        """Robust range of a series (percentile spread)."""
        x = self.series[name]
        x = x[np.isfinite(x)]
        if len(x) == 0:
            return 0.0
        return float(np.percentile(x, hi) - np.percentile(x, lo))

    def median(self, name: str) -> float:
        x = self.series[name]
        x = x[np.isfinite(x)]
        return float(np.median(x)) if len(x) else float("nan")


def _points(lm: np.ndarray, idx: int, aspect: float) -> np.ndarray:
    """(T, 2) points with x rescaled by aspect so x and y share units."""
    p = lm[:, idx, :2].copy()
    p[:, 0] *= aspect
    vis = lm[:, idx, 3]
    p[~(vis >= MIN_LANDMARK_VISIBILITY)] = np.nan
    return p


def _mid(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Midpoint, falling back to whichever point is present."""
    out = np.where(np.isfinite(a), a, b)
    both = np.isfinite(a) & np.isfinite(b)
    out[both] = (a[both] + b[both]) / 2
    return out


def compute_features(seq: PoseSequence, smooth: bool = True) -> Features:
    lm = seq.landmarks
    t = seq.timestamps
    n = len(t)
    fps = float((n - 1) / (t[-1] - t[0])) if n > 1 and t[-1] > t[0] else 15.0
    a = seq.aspect

    vis = np.nan_to_num(lm[:, :, 3], nan=0.0)
    frame_vis = vis[:, KEY_LANDMARKS].mean(axis=1)
    left_vis = float(vis[:, LEFT_CHAIN].mean())
    right_vis = float(vis[:, RIGHT_CHAIN].mean())
    side = "left" if left_vis >= right_vis else "right"

    P = {i: _points(lm, i, a) for i in (*KEY_LANDMARKS, NOSE)}

    def chain(prefix: str):
        if prefix == "l":
            return L_SHOULDER, L_ELBOW, L_WRIST, L_HIP, L_KNEE, L_ANKLE
        return R_SHOULDER, R_ELBOW, R_WRIST, R_HIP, R_KNEE, R_ANKLE

    raw: dict[str, np.ndarray] = {}
    for s in ("l", "r"):
        sh, el, wr, hp, kn, an = chain(s)
        raw[f"knee_{s}"] = joint_angle(P[hp], P[kn], P[an])
        raw[f"hip_{s}"] = joint_angle(P[sh], P[hp], P[kn])
        raw[f"elbow_{s}"] = joint_angle(P[sh], P[el], P[wr])
        raw[f"shoulder_{s}"] = joint_angle(P[hp], P[sh], P[el])
        raw[f"body_line_{s}"] = joint_angle(P[sh], P[hp], P[an])

    primary = "l" if side == "left" else "r"
    for name in ("knee", "hip", "elbow", "shoulder", "body_line"):
        raw[name] = raw[f"{name}_{primary}"].copy()
        # If the primary side drops out on a frame, borrow the other side.
        other = raw[f"{name}_{'r' if primary == 'l' else 'l'}"]
        missing = ~np.isfinite(raw[name])
        raw[name][missing] = other[missing]

    shoulder_mid = _mid(P[L_SHOULDER], P[R_SHOULDER])
    hip_mid = _mid(P[L_HIP], P[R_HIP])
    ankle_mid = _mid(P[L_ANKLE], P[R_ANKLE])
    knee_mid = _mid(P[L_KNEE], P[R_KNEE])
    wrist_mid = _mid(P[L_WRIST], P[R_WRIST])

    torso_vec = shoulder_mid - hip_mid
    torso_series = np.linalg.norm(torso_vec, axis=-1)
    finite_torso = torso_series[np.isfinite(torso_series)]
    torso_len = float(np.median(finite_torso)) if len(finite_torso) else float("nan")
    if not np.isfinite(torso_len) or torso_len <= 1e-6:
        torso_len = 1.0

    shoulder_width = np.abs(P[L_SHOULDER][:, 0] - P[R_SHOULDER][:, 0])
    sw = shoulder_width[np.isfinite(shoulder_width)]
    width_ratio = float(np.median(sw)) / torso_len if len(sw) else 0.0
    view = "frontal" if width_ratio > 0.45 else "side"

    raw["trunk_lean"] = angle_from_vertical(shoulder_mid, hip_mid)
    raw["torso_len_rel"] = torso_series / torso_len

    for name, pts in (
        ("shoulder", shoulder_mid), ("hip", hip_mid), ("ankle", ankle_mid),
        ("knee", knee_mid), ("wrist", wrist_mid), ("nose", P[NOSE]),
    ):
        raw[f"{name}_x"] = pts[:, 0] / torso_len
        raw[f"{name}_y"] = pts[:, 1] / torso_len

    raw["ankle_sep"] = np.abs(P[L_ANKLE][:, 0] - P[R_ANKLE][:, 0]) / torso_len
    raw["shoulder_width"] = shoulder_width / torso_len
    knee_w = np.abs(P[L_KNEE][:, 0] - P[R_KNEE][:, 0])
    ankle_w = np.abs(P[L_ANKLE][:, 0] - P[R_ANKLE][:, 0])
    with np.errstate(invalid="ignore", divide="ignore"):
        raw["knee_ankle_width_ratio"] = np.where(ankle_w > 1e-6, knee_w / ankle_w, np.nan)
    raw["hip_shift"] = (hip_mid[:, 0] - ankle_mid[:, 0]) / torso_len

    series: dict[str, np.ndarray] = {}
    window = smoothing_window(fps)
    for name, x in raw.items():
        series[name] = savgol_smooth(x, window, 2) if smooth else fill_nans(x)

    return Features(
        t=t, fps=fps, visibility=frame_vis, side=side, view=view,
        torso_len=torso_len, series=series,
    )
