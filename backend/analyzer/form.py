"""Per-exercise form checks producing ``formIssues`` and a ``formScore``.

All checks are 2D heuristics on the smoothed joint angles. Checks that need a
particular camera angle (knee valgus, hip shift and L/R asymmetry need a
frontal view) only run when that view was detected. Thresholds are deliberately
conservative: a missed cue is better than nagging about a good rep.
"""

from __future__ import annotations

from typing import Callable

import numpy as np

from .features import Features
from .reps import Rep, RepResult

SEVERITY_PENALTY = {"low": 6, "medium": 14, "high": 25}
SEVERITY_RANK = {"low": 0, "medium": 1, "high": 2}

TIPS = {
    "insufficient_depth": "Use the full range of motion on every rep, even if that means a lighter load.",
    "excessive_lean": "Keep your torso steadier; brace your core and avoid swinging or folding over.",
    "knee_valgus": "Push your knees out over your toes as you descend and drive up.",
    "back_rounding": "Keep a neutral spine: brace hard and keep your chest up before you pull.",
    "elbow_flare": "Tuck your elbows to about 45 degrees from your torso to protect your shoulders.",
    "hip_shift": "Keep your weight centred; film from the front and watch for one hip dropping.",
    "lockout_incomplete": "Finish every rep with a full lockout before starting the next.",
    "asymmetry": "Both sides are moving differently; slow down and match left and right.",
    "hip_sag": "Squeeze your glutes and keep a straight line from shoulders to ankles.",
    "elbow_drift": "Pin your elbows to your sides so the biceps do the work.",
    "partial_reps": "Some reps were cut short; reduce the load until every rep is full range.",
    "fast_eccentric": "Control the lowering phase for about two seconds instead of dropping the weight.",
    "low_visibility": "Film from the side with your whole body in frame and good lighting for better analysis.",
    "no_reps_detected": "No reps were detected; make sure your whole body is in frame and the camera is still.",
}


def issue(code: str, severity: str, message: str, at_sec: float | None = None) -> dict:
    return {
        "code": code,
        "severity": severity,
        "message": message,
        "atSec": None if at_sec is None else round(float(at_sec), 2),
    }


def _values_at(f: Features, name: str, reps: list[Rep], where: str = "event") -> np.ndarray:
    x = f[name]
    idx = [getattr(r, f"{where}_idx") for r in reps]
    return np.array([x[i] for i in idx], dtype=float)


def _window_extreme(f: Features, name: str, reps: list[Rep], fn: Callable) -> np.ndarray:
    x = f[name]
    return np.array([fn(x[r.start_idx:r.end_idx + 1]) for r in reps], dtype=float)


def _threshold_issue(values: np.ndarray, reps: list[Rep], code: str, *, above: bool,
                     medium: float, high: float | None, low: float | None,
                     message: str) -> dict | None:
    """Flag when the median rep crosses a threshold; atSec = worst rep."""
    vals = values[np.isfinite(values)]
    if len(vals) == 0:
        return None
    med = float(np.median(vals))
    worst_i = int(np.nanargmax(values) if above else np.nanargmin(values))
    beyond = (lambda v, th: v > th) if above else (lambda v, th: v < th)
    sev = None
    if high is not None and beyond(med, high):
        sev = "high"
    elif beyond(med, medium):
        sev = "medium"
    elif low is not None and beyond(med, low):
        sev = "low"
    if sev is None:
        return None
    return issue(code, sev, message.format(v=med), reps[worst_i].event_t)


# --------------------------------------------------------------------------- #
# Exercise-specific rules. Each returns a list of issues.
# --------------------------------------------------------------------------- #

def _squat_like(f: Features, reps: list[Rep], depth_med: float, depth_high: float,
                lean_med: float) -> list[dict]:
    out = [
        _threshold_issue(_values_at(f, "knee", reps), reps, "insufficient_depth", above=True,
                         medium=depth_med, high=depth_high, low=None,
                         message="Knee only bends to about {v:.0f} degrees at the bottom; aim for thighs at least parallel."),
        _threshold_issue(_values_at(f, "trunk_lean", reps), reps, "excessive_lean", above=True,
                         medium=lean_med, high=lean_med + 12, low=None,
                         message="Torso leans about {v:.0f} degrees forward at the bottom."),
        _threshold_issue(_window_extreme(f, "knee", reps, np.max), reps, "lockout_incomplete",
                         above=False, medium=150, high=None, low=160,
                         message="Knees reach only about {v:.0f} degrees at the top; stand all the way up."),
    ]
    if f.view == "frontal":
        out.append(_threshold_issue(_values_at(f, "knee_ankle_width_ratio", reps), reps,
                                    "knee_valgus", above=False, medium=0.85, high=0.7, low=None,
                                    message="Knees cave inward at the bottom (knee width {v:.0%} of ankle width)."))
        shift = np.abs(_values_at(f, "hip_shift", reps))
        out.append(_threshold_issue(shift, reps, "hip_shift", above=True, medium=0.12,
                                    high=0.2, low=None,
                                    message="Hips shift to one side at the bottom."))
    return out


def _squat(f, reps):
    return _squat_like(f, reps, depth_med=105, depth_high=125, lean_med=50)


def _lunge(f, reps):
    return _squat_like(f, reps, depth_med=115, depth_high=135, lean_med=30)


def _back_rounding(f: Features, reps: list[Rep]) -> dict | None:
    # Proxy: the shoulder-hip distance shrinks in a side view when the spine
    # flexes. It cannot see the spine itself, so it says "possible".
    return _threshold_issue(_window_extreme(f, "torso_len_rel", reps, np.min), reps,
                            "back_rounding", above=False, medium=0.88, high=0.8, low=None,
                            message="Possible back rounding: torso shortens to {v:.0%} of its standing length.")


def _deadlift(f, reps):
    return [
        _back_rounding(f, reps),
        _threshold_issue(_window_extreme(f, "hip", reps, np.max), reps, "lockout_incomplete",
                         above=False, medium=160, high=145, low=None,
                         message="Hips reach only about {v:.0f} degrees at the top; finish with glutes, standing tall."),
    ]


def _rdl(f, reps):
    return [
        _back_rounding(f, reps),
        _threshold_issue(_values_at(f, "hip", reps), reps, "insufficient_depth", above=True,
                         medium=135, high=None, low=120,
                         message="Hip hinge only reaches about {v:.0f} degrees; push the hips further back."),
    ]


def _hip_thrust(f, reps):
    return [
        _threshold_issue(_values_at(f, "hip", reps), reps, "lockout_incomplete", above=False,
                         medium=160, high=145, low=None,
                         message="Hips extend to only about {v:.0f} degrees at the top; squeeze to full extension."),
    ]


def _press_depth_lockout(f, reps, depth: float, lockout: float, depth_msg: str, lock_msg: str):
    return [
        _threshold_issue(_values_at(f, "elbow", reps), reps, "insufficient_depth", above=True,
                         medium=depth, high=depth + 20, low=None, message=depth_msg),
        _threshold_issue(_window_extreme(f, "elbow", reps, np.max), reps, "lockout_incomplete",
                         above=False, medium=lockout, high=lockout - 20, low=None, message=lock_msg),
    ]


def _bench(f, reps):
    out = _press_depth_lockout(
        f, reps, 100, 150,
        "Elbows only bend to about {v:.0f} degrees; bring the bar to your chest.",
        "Elbows reach about {v:.0f} degrees at the top; lock out fully.")
    if f.view == "frontal":
        out.append(_threshold_issue(_values_at(f, "shoulder", reps), reps, "elbow_flare",
                                    above=True, medium=80, high=95, low=None,
                                    message="Upper arm opens to about {v:.0f} degrees from the torso at the bottom."))
    return out


def _push_up(f, reps):
    out = _press_depth_lockout(
        f, reps, 100, 150,
        "Elbows only bend to about {v:.0f} degrees; lower your chest closer to the floor.",
        "Elbows reach about {v:.0f} degrees at the top; push all the way up.")
    out.append(_threshold_issue(_window_extreme(f, "body_line", reps, np.min), reps, "hip_sag",
                                above=False, medium=160, high=145, low=None,
                                message="Body line bends to about {v:.0f} degrees; hips are sagging or piking."))
    return out


def _ohp(f, reps):
    return [
        _threshold_issue(_window_extreme(f, "elbow", reps, np.max), reps, "lockout_incomplete",
                         above=False, medium=160, high=140, low=None,
                         message="Elbows reach only about {v:.0f} degrees overhead; press to full lockout."),
        _threshold_issue(_window_extreme(f, "trunk_lean", reps, np.max), reps, "excessive_lean",
                         above=True, medium=15, high=25, low=None,
                         message="You lean back about {v:.0f} degrees while pressing; squeeze glutes and brace."),
    ]


def _swing(f: Features, reps: list[Rep], medium: float) -> dict | None:
    swing = _window_extreme(f, "trunk_lean", reps, lambda x: float(np.max(x) - np.min(x)))
    return _threshold_issue(swing, reps, "excessive_lean", above=True, medium=medium,
                            high=medium * 2, low=None,
                            message="Torso swings about {v:.0f} degrees per rep; use less momentum.")


def _row(f, reps):
    return [
        _swing(f, reps, 15),
        _threshold_issue(_values_at(f, "elbow", reps), reps, "insufficient_depth", above=True,
                         medium=110, high=None, low=95,
                         message="Elbows only bend to about {v:.0f} degrees; pull the bar to your lower ribs."),
    ]


def _pull_up(f, reps):
    return [
        _threshold_issue(_values_at(f, "elbow", reps), reps, "insufficient_depth", above=True,
                         medium=85, high=105, low=None,
                         message="Elbows only bend to about {v:.0f} degrees; get your chin over the bar."),
        _threshold_issue(_window_extreme(f, "elbow", reps, np.max), reps, "lockout_incomplete",
                         above=False, medium=150, high=130, low=None,
                         message="Arms extend to only about {v:.0f} degrees; return to a full dead hang."),
    ]


def _curl(f, reps):
    drift = _window_extreme(f, "shoulder", reps, lambda x: float(np.max(x) - np.min(x)))
    return [
        _swing(f, reps, 12),
        _threshold_issue(drift, reps, "elbow_drift", above=True, medium=35, high=55, low=None,
                         message="Upper arm swings about {v:.0f} degrees; keep elbows by your sides."),
        _threshold_issue(_window_extreme(f, "elbow", reps, np.max), reps, "lockout_incomplete",
                         above=False, medium=140, high=120, low=None,
                         message="Arms extend to only about {v:.0f} degrees at the bottom; straighten fully."),
    ]


def _lateral_raise(f, reps):
    return [
        _swing(f, reps, 12),
        _threshold_issue(_values_at(f, "shoulder", reps), reps, "insufficient_depth", above=False,
                         medium=70, high=50, low=None,
                         message="Arms rise to only about {v:.0f} degrees; lift to shoulder height."),
    ]


RULES: dict[str, Callable[[Features, list[Rep]], list]] = {
    "squat": _squat,
    "lunge": _lunge,
    "deadlift": _deadlift,
    "romanian_deadlift": _rdl,
    "hip_thrust": _hip_thrust,
    "bench_press": _bench,
    "push_up": _push_up,
    "overhead_press": _ohp,
    "barbell_row": _row,
    "pull_up": _pull_up,
    "bicep_curl": _curl,
    "lateral_raise": _lateral_raise,
}

ASYMMETRY_SIGNAL = {
    "squat": "knee", "deadlift": "hip", "romanian_deadlift": "hip", "hip_thrust": "hip",
    "bench_press": "elbow", "push_up": "elbow", "overhead_press": "elbow",
    "barbell_row": "elbow", "pull_up": "elbow", "bicep_curl": "elbow", "lateral_raise": "shoulder",
}


def _asymmetry(f: Features, exercise: str, reps: list[Rep]) -> dict | None:
    sig = ASYMMETRY_SIGNAL.get(exercise)
    if not sig or f.view != "frontal":
        return None
    diff = np.abs(_values_at(f, f"{sig}_l", reps) - _values_at(f, f"{sig}_r", reps))
    return _threshold_issue(diff, reps, "asymmetry", above=True, medium=15, high=25, low=None,
                            message="Left and right sides differ by about {v:.0f} degrees at the bottom of each rep.")


def check_form(f: Features, exercise: str, rep_result: RepResult) -> tuple[list[dict], int]:
    """Return (formIssues, formScore 0-100)."""
    reps = rep_result.reps
    issues: list[dict] = []
    vis = float(np.nanmean(f.visibility)) if len(f.visibility) else 0.0

    if not reps:
        issues.append(issue("no_reps_detected", "high",
                            "No complete reps were detected in the video."))
        if vis < 0.5:
            issues.append(issue("low_visibility", "medium",
                                f"Body landmarks were only {vis:.0%} visible on average."))
        return issues, 0

    rule = RULES.get(exercise)
    if rule:
        issues.extend(i for i in rule(f, reps) if i)
    asym = _asymmetry(f, exercise, reps)
    if asym:
        issues.append(asym)

    partial = rep_result.partial_reps
    if partial:
        sev = "medium" if len(partial) >= max(2, len(reps) // 3) else "low"
        issues.append(issue("partial_reps", sev,
                            f"{len(partial)} rep(s) used noticeably less range than your best reps.",
                            partial[0].event_t))

    full = rep_result.full_reps
    if full and exercise not in ("unknown",):
        ecc = float(np.mean([r.eccentric_sec for r in full]))
        if 0 < ecc < 0.4:
            issues.append(issue("fast_eccentric", "low",
                                f"The lowering phase averages {ecc:.1f}s; it looks uncontrolled."))

    if vis < 0.5:
        issues.append(issue("low_visibility", "low" if vis >= 0.35 else "medium",
                            f"Body landmarks were only {vis:.0%} visible on average; results may be less accurate."))

    # One issue per code, keeping the most severe.
    dedup: dict[str, dict] = {}
    for i in issues:
        cur = dedup.get(i["code"])
        if cur is None or SEVERITY_RANK[i["severity"]] > SEVERITY_RANK[cur["severity"]]:
            dedup[i["code"]] = i
    issues = sorted(dedup.values(), key=lambda i: -SEVERITY_RANK[i["severity"]])

    score = 100 - sum(SEVERITY_PENALTY[i["severity"]] for i in issues if i["code"] != "low_visibility")
    return issues, int(np.clip(score, 0, 100))


def tip_for(code: str) -> str:
    return TIPS.get(code, "")
