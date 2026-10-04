"""Rule-based exercise classifier.

Two cues decide the exercise:

1. Body orientation: standing (legs roughly vertical), lying supine / prone
   (torso and thighs near horizontal), or hanging (wrists above the head the
   whole set).
2. Which joint angles move the most (robust 5-95th percentile range), and how
   the hands and shoulders travel.

Each exercise gets a fuzzy score in [0, 1] built from ramp memberships, so the
rules degrade gracefully rather than flipping on a hard threshold. When the
app supplies the planned exercise it is mixed in as a strong prior; the
detected label can still differ if the video clearly shows something else.
"""

from __future__ import annotations

import numpy as np

from .exercises import SPECS, normalize_exercise_id
from .features import Features

PRIOR_WEIGHT = 0.3
MIN_SCORE = 0.15


def ramp(x: float, a: float, b: float) -> float:
    """0 at a, 1 at b, linear between (works for a > b as a falling ramp)."""
    if not np.isfinite(x):
        return 0.0
    if a == b:
        return float(x >= b)
    return float(np.clip((x - a) / (b - a), 0.0, 1.0))


def _frac(mask: np.ndarray) -> float:
    return float(np.mean(mask)) if len(mask) else 0.0


def orientation_stats(f: Features) -> dict[str, float]:
    knee_below_hip = f.median("knee_y") - f.median("hip_y")  # torso units, + = below
    wrist_minus_shoulder = f.median("wrist_y") - f.median("shoulder_y")  # + = wrist lower
    wrist_y, nose_y = f["wrist_y"], f["nose_y"]
    shoulder_y = f["shoulder_y"]
    ok = np.isfinite(wrist_y) & np.isfinite(nose_y)
    stats = {
        "lean": f.median("trunk_lean"),
        "lean_rom": f.rom("trunk_lean"),
        "knee_below_hip": knee_below_hip,
        "wrist_minus_shoulder": wrist_minus_shoulder,
        "wrist_above_nose": _frac(wrist_y[ok] < nose_y[ok]) if ok.any() else 0.0,
        "wrist_above_shoulder": _frac(wrist_y < shoulder_y - 0.1),
        "rom_knee": f.rom("knee"),
        "rom_hip": f.rom("hip"),
        "rom_elbow": f.rom("elbow"),
        "rom_shoulder": f.rom("shoulder"),
        "rom_shoulder_y": f.rom("shoulder_y"),
        "rom_wrist_y": f.rom("wrist_y"),
        "hands_below_hip": f.median("wrist_y") - f.median("hip_y"),
        "stance": f.median("ankle_sep"),
    }
    return stats


def orientation(f: Features) -> str:
    s = orientation_stats(f)
    lying = _lying(s)
    if lying >= 0.5:
        return "supine" if s["wrist_minus_shoulder"] < 0 else "prone"
    if s["wrist_above_nose"] > 0.8 and s["rom_shoulder_y"] > s["rom_wrist_y"]:
        return "hanging"
    return "standing"


def _lying(s: dict[str, float]) -> float:
    return ramp(s["knee_below_hip"], 0.5, 0.2) * ramp(s["lean"], 45, 65)


def exercise_scores(f: Features) -> dict[str, float]:
    s = orientation_stats(f)
    lying = _lying(s)
    standing = 1.0 - lying
    shoulder_travel = s["rom_shoulder_y"] - s["rom_wrist_y"]
    # Hanging = hands above the head all set long AND the body (not the hands)
    # is what moves; an overhead press also keeps the hands high but moves them.
    hanging = ramp(s["wrist_above_nose"], 0.7, 0.95) * ramp(shoulder_travel, -0.1, 0.2)
    overhead = ramp(s["wrist_above_nose"], 0.12, 0.35)
    knee_hip_ratio = s["rom_knee"] / max(s["rom_hip"], 1.0)
    hands_low = ramp(s["hands_below_hip"], -0.3, 0.2)
    split = ramp(s["stance"], 0.5, 0.9) if f.view == "side" else 0.2
    supine = ramp(-s["wrist_minus_shoulder"], 0.15, 0.4)
    prone = ramp(s["wrist_minus_shoulder"], 0.15, 0.4)
    upright = ramp(s["lean"], 25, 10)

    scores = {
        "squat": standing * (1 - hanging) * ramp(s["rom_knee"], 30, 60)
        * ramp(knee_hip_ratio, 0.55, 0.85) * (0.6 + 0.4 * (1 - hands_low)) * (1 - split),
        "lunge": standing * (1 - hanging) * ramp(s["rom_knee"], 30, 55) * split,
        "deadlift": standing * (1 - hanging) * ramp(s["rom_hip"], 35, 60)
        * ramp(s["rom_knee"], 12, 30) * ramp(knee_hip_ratio, 0.95, 0.6) * (0.5 + 0.5 * hands_low),
        "romanian_deadlift": standing * (1 - hanging) * ramp(s["rom_hip"], 30, 50)
        * ramp(s["rom_knee"], 30, 12) * (0.5 + 0.5 * hands_low),
        "barbell_row": standing * (1 - hanging) * ramp(s["lean"], 25, 45)
        * ramp(s["rom_elbow"], 30, 60) * ramp(s["rom_hip"], 30, 15),
        "bicep_curl": standing * (1 - hanging) * (1 - overhead) * upright
        * ramp(s["rom_elbow"], 50, 80) * ramp(s["rom_shoulder"], 60, 30) * ramp(s["rom_knee"], 30, 15),
        "lateral_raise": standing * (1 - hanging) * (1 - overhead) * upright
        * ramp(s["rom_shoulder"], 40, 65) * ramp(s["rom_elbow"], 40, 20),
        "overhead_press": standing * (1 - hanging) * overhead * upright
        * ramp(s["rom_elbow"], 40, 70) * ramp(-shoulder_travel, 0.1, 0.4),
        "pull_up": standing * hanging * ramp(s["rom_elbow"], 40, 70),
        "bench_press": lying * supine * ramp(s["rom_elbow"], 35, 60) * ramp(s["rom_hip"], 40, 20),
        "push_up": lying * prone * ramp(s["rom_elbow"], 35, 60) * ramp(s["rom_hip"], 40, 20),
        "hip_thrust": lying * ramp(s["rom_hip"], 30, 55) * ramp(s["rom_elbow"], 30, 15),
    }
    return {k: float(np.clip(v, 0.0, 1.0)) for k, v in scores.items()}


def classify_detailed(f: Features, planned: str | None = None) -> dict:
    scores = exercise_scores(f)
    planned_id = normalize_exercise_id(planned)
    combined = {
        k: (1 - PRIOR_WEIGHT) * v + (PRIOR_WEIGHT if k == planned_id else 0.0)
        for k, v in scores.items()
    }
    ranked = sorted(combined.items(), key=lambda kv: kv[1], reverse=True)
    best, best_score = ranked[0]
    second_score = ranked[1][1] if len(ranked) > 1 else 0.0

    vis = float(np.nanmean(f.visibility)) if len(f.visibility) else 0.0
    vis_factor = float(np.clip(vis / 0.6, 0.3, 1.0))

    if scores[best] < MIN_SCORE and best != planned_id:
        exercise, confidence = "unknown", 0.0
    else:
        margin = (best_score - second_score) / max(best_score, 1e-6)
        # Normalise by the best achievable combined score (1.0 with a prior
        # that matches, 1 - PRIOR_WEIGHT without one).
        ceiling = 1.0 if planned_id else (1 - PRIOR_WEIGHT)
        confidence = (best_score / ceiling) * (0.6 + 0.4 * margin) * vis_factor
        exercise = best
    return {
        "exercise": exercise,
        "confidence": round(float(np.clip(confidence, 0.0, 1.0)), 3),
        "scores": scores,
        "planned": planned_id,
        "orientation": orientation(f),
    }


def classify(f: Features, planned: str | None = None) -> tuple[str, float]:
    """Return (exercise_id, confidence 0-1)."""
    d = classify_detailed(f, planned)
    return d["exercise"], d["confidence"]


def dominant_signal(f: Features) -> str:
    """Joint angle with the largest range; used when the exercise is unknown."""
    return max(("knee", "hip", "elbow", "shoulder"), key=f.rom)


__all__ = ["classify", "classify_detailed", "exercise_scores", "orientation", "dominant_signal", "SPECS"]
