"""Load, effort and rest estimates.

Be clear about what this can and cannot do from one phone video:

* The weight comes from what the athlete logged (``loggedWeightKg``). For
  bodyweight exercises with a known ``bodyMassKg`` the effective load is
  body mass times the fraction moved, plus any logged added weight.
  Detecting plates or dumbbells in the frames is *not* implemented; the
  :func:`estimate_load_from_frames` hook exists for a future vision model and
  returns ``None``.
* RPE comes from velocity-based-training heuristics: the slowdown of the
  concentric phase across the set (velocity loss) correlates with how close
  to failure the set ended. Velocity here is the joint's angular velocity,
  a proxy for bar speed, not a calibrated m/s measurement.
"""

from __future__ import annotations

import logging
from datetime import datetime

import numpy as np

from .exercises import SPECS
from .reps import RepResult

log = logging.getLogger(__name__)

# (velocity loss %, RPE) anchor points. Roughly: <10 % loss means plenty in the
# tank, 20 % about two reps in reserve, 40 %+ about at failure.
VL_TO_RPE = ((0.0, 5.5), (10.0, 7.0), (20.0, 8.0), (30.0, 9.0), (40.0, 10.0))

# Exercises where ending the video mid-rep is normal (bar back on the floor /
# in the rack position), so an open excursion is not a failed rep.
OPEN_END_OK = {"deadlift", "overhead_press"}


def estimate_load_from_frames(frames=None, landmarks=None) -> float | None:
    """HOOK: visual load estimation (plate / dumbbell detection).

    Not implemented. Detecting plate sizes reliably needs a dedicated object
    detector and a known camera geometry; returning a guessed number would be
    worse than returning nothing. Keep returning None until a real model is
    plugged in here.
    """
    return None


def rep_velocities(rep_result: RepResult) -> list[float]:
    vals = [r.concentric_velocity for r in rep_result.full_reps]
    return [float(v) for v in vals if v is not None and np.isfinite(v) and v > 0]


def velocity_loss_pct(rep_result: RepResult) -> float | None:
    """(fastest of the first three reps - last rep) / fastest, in percent."""
    v = rep_velocities(rep_result)
    if len(v) < 3:
        return None
    best = max(v[:3])
    last = v[-1]
    if best <= 0:
        return None
    return round(float(np.clip((best - last) / best * 100.0, 0.0, 100.0)), 1)


def estimate_rpe(rep_result: RepResult, exercise: str, vl: float | None) -> float | None:
    failed = rep_result.unfinished is not None and exercise not in OPEN_END_OK
    if failed and rep_result.full_reps:
        return 10.0
    if vl is None:
        return None
    xs, ys = zip(*VL_TO_RPE)
    rpe = float(np.interp(vl, xs, ys))
    return round(rpe * 2) / 2  # nearest 0.5


def estimate_weight_kg(exercise: str, logged_weight_kg: float | None,
                       body_mass_kg: float | None) -> float | None:
    spec = SPECS.get(exercise)
    if spec and spec.bodyweight_fraction and body_mass_kg:
        return round(body_mass_kg * spec.bodyweight_fraction + (logged_weight_kg or 0.0), 1)
    if logged_weight_kg is not None:
        return round(float(logged_weight_kg), 2)
    return estimate_load_from_frames()


def velocity_sanity_check(rep_result: RepResult, logged_weight_kg: float | None,
                          planned_reps: int | None) -> str | None:
    """Flag sets whose speed profile disagrees with the logged numbers.

    Only produces a note for logging / debugging; it never changes the weight.
    """
    vl = velocity_loss_pct(rep_result)
    n = len(rep_result.full_reps)
    if logged_weight_kg and vl is not None and vl < 5 and n >= 12:
        return "high rep count with almost no slowdown: logged weight may be light for this set"
    if planned_reps and n and n < planned_reps and vl is not None and vl < 10:
        return "fewer reps than planned without slowing down: set may have been cut short"
    return None


def parse_iso8601(value: str | None) -> datetime | None:
    if not value or not isinstance(value, str):
        return None
    s = value.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def seconds_between(later: str | None, earlier: str | None) -> float | None:
    a, b = parse_iso8601(later), parse_iso8601(earlier)
    if a is None or b is None:
        return None
    if (a.tzinfo is None) != (b.tzinfo is None):
        return None
    return (a - b).total_seconds()


def rest_before_sec(started_at: str | None, previous_set_ended_at: str | None) -> float | None:
    d = seconds_between(started_at, previous_set_ended_at)
    if d is None or d < 0:
        return None
    return round(d, 1)
