"""Exercise catalogue shared by every analysis stage.

The ids are part of the app contract (``analysis.detectedExercise``).
"""

from __future__ import annotations

from dataclasses import dataclass

EXERCISE_IDS = (
    "squat",
    "deadlift",
    "bench_press",
    "overhead_press",
    "barbell_row",
    "pull_up",
    "push_up",
    "lunge",
    "bicep_curl",
    "romanian_deadlift",
    "hip_thrust",
    "lateral_raise",
    "unknown",
)


@dataclass(frozen=True)
class ExerciseSpec:
    """How to count and time reps for one exercise.

    signal:          feature series that tracks the movement (degrees).
    event:           "valley" if the rep's key moment (bottom / peak contraction)
                     is a minimum of the signal, "peak" if a maximum.
    expected_rom:    typical full range of motion of ``signal`` in degrees.
    event_ends_eccentric: True if the phase before the event is the eccentric
                     (lowering) one, e.g. squat; False if it is the concentric
                     one, e.g. pull-up (you pull up to the event).
    bodyweight_fraction: fraction of body mass moved, for bodyweight moves.
    """

    signal: str
    event: str
    expected_rom: float
    event_ends_eccentric: bool
    bodyweight_fraction: float | None = None


SPECS: dict[str, ExerciseSpec] = {
    "squat": ExerciseSpec("knee", "valley", 90.0, True),
    "lunge": ExerciseSpec("knee", "valley", 75.0, True),
    "deadlift": ExerciseSpec("hip", "valley", 80.0, True),
    "romanian_deadlift": ExerciseSpec("hip", "valley", 70.0, True),
    "hip_thrust": ExerciseSpec("hip", "peak", 70.0, False),
    "bench_press": ExerciseSpec("elbow", "valley", 85.0, True),
    "push_up": ExerciseSpec("elbow", "valley", 80.0, True, bodyweight_fraction=0.64),
    "overhead_press": ExerciseSpec("elbow", "valley", 90.0, True),
    "pull_up": ExerciseSpec("elbow", "valley", 90.0, False, bodyweight_fraction=1.0),
    "barbell_row": ExerciseSpec("elbow", "valley", 75.0, False),
    "bicep_curl": ExerciseSpec("elbow", "valley", 100.0, False),
    "lateral_raise": ExerciseSpec("shoulder", "peak", 70.0, False),
}

# Used when nothing could be classified: count on whichever joint moves most.
FALLBACK_SPEC = ExerciseSpec("knee", "valley", 60.0, True)


def spec_for(exercise: str, dominant_signal: str | None = None) -> ExerciseSpec:
    if exercise in SPECS:
        return SPECS[exercise]
    if dominant_signal:
        return ExerciseSpec(dominant_signal, "valley", 60.0, True)
    return FALLBACK_SPEC


def normalize_exercise_id(raw: str | None) -> str | None:
    """Map an app-supplied exerciseId onto a contract id (or None)."""
    if not raw:
        return None
    key = raw.strip().lower().replace("-", "_").replace(" ", "_")
    aliases = {
        "back_squat": "squat",
        "front_squat": "squat",
        "goblet_squat": "squat",
        "bench": "bench_press",
        "ohp": "overhead_press",
        "military_press": "overhead_press",
        "shoulder_press": "overhead_press",
        "row": "barbell_row",
        "bent_over_row": "barbell_row",
        "pullup": "pull_up",
        "chin_up": "pull_up",
        "chinup": "pull_up",
        "pushup": "push_up",
        "rdl": "romanian_deadlift",
        "curl": "bicep_curl",
        "biceps_curl": "bicep_curl",
        "dumbbell_curl": "bicep_curl",
        "lunges": "lunge",
        "walking_lunge": "lunge",
        "split_squat": "lunge",
        "glute_bridge": "hip_thrust",
        "lateral_raises": "lateral_raise",
        "side_raise": "lateral_raise",
    }
    key = aliases.get(key, key)
    return key if key in SPECS else None
