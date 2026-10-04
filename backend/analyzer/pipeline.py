"""End-to-end analysis: video (or landmark sequence) + metadata -> analysis map.

The returned dict matches the ``analysis`` map of the Firestore contract
(``users/{uid}/sessions/{sessionId}/sets/{setId}``) exactly.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass
from typing import Any, Mapping

import numpy as np

from . import load as load_mod
from .classify import classify_detailed, dominant_signal
from .exercises import normalize_exercise_id, spec_for
from .features import compute_features
from .form import SEVERITY_RANK, check_form, tip_for
from .pose import DEFAULT_TARGET_FPS, PoseEstimator, PoseSequence
from .reps import count_reps, rom_score

log = logging.getLogger(__name__)

MIN_FRAMES = 10
MIN_VISIBILITY = 0.15

ANALYSIS_KEYS = (
    "detectedExercise", "exerciseConfidence", "reps", "repTimestamps", "partialReps",
    "avgRepDurationSec", "tempo", "rangeOfMotionScore", "formScore", "formIssues",
    "estimatedWeightKg", "estimatedRPE", "velocityLossPct", "restBeforeSec",
    "idleSecInVideo", "setDurationSec", "framesAnalyzed", "poseVisibility", "coachingTip",
)


class AnalysisError(Exception):
    """The video could not be analysed (no person, too short, unreadable)."""


@dataclass
class SetMetadata:
    exercise_id: str | None = None
    exercise_name: str | None = None
    planned_reps: int | None = None
    logged_weight_kg: float | None = None
    set_index: int | None = None
    started_at: str | None = None
    ended_at: str | None = None
    previous_set_ended_at: str | None = None
    body_mass_kg: float | None = None
    heart_rate_avg: float | None = None
    heart_rate_max: float | None = None

    @classmethod
    def from_custom_metadata(cls, meta: Mapping[str, Any] | None) -> "SetMetadata":
        """Parse Firebase Storage custom metadata (all values are strings)."""
        m = dict(meta or {})

        def s(key):
            v = m.get(key)
            if v is None:
                return None
            v = str(v).strip()
            return v or None

        def num(key):
            v = s(key)
            if v is None:
                return None
            try:
                x = float(v)
            except ValueError:
                return None
            return x if math.isfinite(x) else None

        def integer(key):
            x = num(key)
            return int(round(x)) if x is not None else None

        return cls(
            exercise_id=s("exerciseId"),
            exercise_name=s("exerciseName"),
            planned_reps=integer("plannedReps"),
            logged_weight_kg=num("loggedWeightKg"),
            set_index=integer("setIndex"),
            started_at=s("startedAt"),
            ended_at=s("endedAt"),
            previous_set_ended_at=s("previousSetEndedAt"),
            body_mass_kg=num("bodyMassKg"),
            heart_rate_avg=num("heartRateAvg"),
            heart_rate_max=num("heartRateMax"),
        )


def _as_metadata(metadata) -> SetMetadata:
    if isinstance(metadata, SetMetadata):
        return metadata
    return SetMetadata.from_custom_metadata(metadata)


def analyze_video(path: str, metadata: Mapping[str, Any] | SetMetadata | None = None,
                  estimator: PoseEstimator | None = None,
                  target_fps: float = DEFAULT_TARGET_FPS) -> dict:
    """Run pose estimation on ``path`` and return the analysis map."""
    if estimator is None:
        from .pose import default_estimator
        estimator = default_estimator()
    try:
        seq = estimator.estimate(path, target_fps)
    except Exception as exc:  # decoding / model errors
        raise AnalysisError(f"pose estimation failed: {exc}") from exc
    return analyze_pose_sequence(seq, metadata)


def analyze_pose_sequence(seq: PoseSequence,
                          metadata: Mapping[str, Any] | SetMetadata | None = None) -> dict:
    meta = _as_metadata(metadata)
    if seq.num_frames < MIN_FRAMES:
        raise AnalysisError(f"video too short: only {seq.num_frames} frames analysed")

    f = compute_features(seq)
    visibility = float(np.nanmean(f.visibility)) if f.n else 0.0
    if visibility < MIN_VISIBILITY:
        raise AnalysisError("no person detected in the video")

    planned = normalize_exercise_id(meta.exercise_id) or normalize_exercise_id(meta.exercise_name)
    cls = classify_detailed(f, planned)
    detected, confidence = cls["exercise"], cls["confidence"]
    working = detected if detected != "unknown" else (planned or "unknown")
    spec = spec_for(working, dominant_signal(f))

    rr = count_reps(f.t, f[spec.signal], spec)
    issues, form_score = check_form(f, working, rr)

    vl = load_mod.velocity_loss_pct(rr)
    rpe = load_mod.estimate_rpe(rr, working, vl)
    weight = load_mod.estimate_weight_kg(working, meta.logged_weight_kg, meta.body_mass_kg)
    note = load_mod.velocity_sanity_check(rr, meta.logged_weight_kg, meta.planned_reps)
    if note:
        log.info("velocity sanity check: %s", note)

    t0 = float(f.t[0]) if f.n else 0.0
    video_end = max(float(seq.duration or 0.0), float(f.t[-1]) if f.n else 0.0)
    video_len = video_end - t0
    bounds = rr.active_bounds()
    idle = video_len if bounds is None else (bounds[0] - t0) + (video_end - bounds[1])

    set_duration = load_mod.seconds_between(meta.ended_at, meta.started_at)
    if set_duration is None or set_duration <= 0:
        set_duration = video_len

    analysis = {
        "detectedExercise": detected,
        "exerciseConfidence": float(confidence),
        "reps": len(rr.full_reps),
        "repTimestamps": [float(x) for x in rr.rep_timestamps],
        "partialReps": len(rr.partial_reps),
        "avgRepDurationSec": float(rr.avg_rep_duration()),
        "tempo": rr.tempo(),
        "rangeOfMotionScore": int(rom_score(rr, spec)),
        "formScore": int(form_score),
        "formIssues": issues,
        "estimatedWeightKg": weight,
        "estimatedRPE": rpe,
        "velocityLossPct": vl,
        "restBeforeSec": load_mod.rest_before_sec(meta.started_at, meta.previous_set_ended_at),
        "idleSecInVideo": round(max(0.0, float(idle)), 2),
        "setDurationSec": round(float(set_duration), 2),
        "framesAnalyzed": int(f.n),
        "poseVisibility": round(float(np.clip(visibility, 0.0, 1.0)), 3),
        "coachingTip": coaching_tip(issues, rr, vl, rpe, meta.planned_reps),
    }
    return to_plain(analysis)


def coaching_tip(issues: list[dict], rr, vl: float | None, rpe: float | None,
                 planned_reps: int | None) -> str:
    ranked = sorted(issues, key=lambda i: -SEVERITY_RANK[i["severity"]])
    for i in ranked:
        if i["code"] == "low_visibility" and len(ranked) > 1:
            continue
        tip = tip_for(i["code"])
        if tip:
            return tip
    reps = len(rr.full_reps)
    if vl is not None and vl >= 30:
        return f"Bar speed dropped {vl:.0f}% by the last rep, so you were close to failure; keep this weight next set."
    if rpe is not None and rpe <= 7 and planned_reps and reps >= planned_reps:
        return "Fast, solid reps with plenty left in the tank; consider adding a little weight next set."
    return "Clean set; keep the same controlled tempo and full range of motion."


def to_plain(obj):
    """Convert numpy scalars / arrays to plain Python for JSON and Firestore."""
    if isinstance(obj, dict):
        return {str(k): to_plain(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [to_plain(v) for v in obj]
    if isinstance(obj, np.ndarray):
        return [to_plain(v) for v in obj.tolist()]
    if isinstance(obj, np.bool_):
        return bool(obj)
    if isinstance(obj, np.integer):
        return int(obj)
    if isinstance(obj, (np.floating, float)):
        x = float(obj)
        return x if math.isfinite(x) else None
    return obj
