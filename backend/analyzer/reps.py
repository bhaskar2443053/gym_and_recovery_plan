"""Rep counting, partial reps and tempo from a single joint-angle signal.

Each exercise has a primary signal (e.g. knee angle for squats) and an event
direction (the rep's key moment is a valley or a peak of that signal). The
signal is turned into a *depth* (degrees away from the rest position) and a
hysteresis state machine finds excursions: an excursion opens when depth
rises above ``enter`` and closes when it falls below ``exit``. Each closed
excursion is a rep; reps whose range of motion is clearly short of the set's
best reps (or of the exercise's expected range) are counted as partial.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .exercises import ExerciseSpec
from .features import fill_nans

ENTER_FRAC = 0.35       # of the set's signal range
EXIT_FRAC = 0.15
MIN_ROM_FRAC_OF_EXPECTED = 0.25   # excursions smaller than this are noise
PARTIAL_FRAC_OF_BEST = 0.75       # rep ROM below this x best reps -> partial
PARTIAL_FRAC_OF_EXPECTED = 0.5    # rep ROM below this x expected ROM -> partial
MIN_REP_SEC = 0.3
REST_FRAC = 0.08                  # phase boundaries: depth within 8% of rest


@dataclass
class Rep:
    start_idx: int
    event_idx: int
    end_idx: int
    start_t: float
    event_t: float
    end_t: float
    rom_deg: float
    full: bool
    eccentric_sec: float
    concentric_sec: float

    @property
    def duration(self) -> float:
        return self.end_t - self.start_t

    @property
    def concentric_velocity(self) -> float | None:
        """Mean angular velocity of the concentric phase, deg/s."""
        if self.concentric_sec <= 0:
            return None
        return self.rom_deg / self.concentric_sec


@dataclass
class RepResult:
    reps: list[Rep] = field(default_factory=list)
    signal_range: float = 0.0
    unfinished: Rep | None = None   # excursion still open when the video ends

    @property
    def full_reps(self) -> list[Rep]:
        return [r for r in self.reps if r.full]

    @property
    def partial_reps(self) -> list[Rep]:
        return [r for r in self.reps if not r.full]

    @property
    def rep_timestamps(self) -> list[float]:
        return [round(r.event_t, 3) for r in self.full_reps]

    def tempo(self) -> dict[str, float]:
        full = self.full_reps or self.reps
        if not full:
            return {"eccentricSec": 0.0, "concentricSec": 0.0}
        return {
            "eccentricSec": round(float(np.mean([r.eccentric_sec for r in full])), 2),
            "concentricSec": round(float(np.mean([r.concentric_sec for r in full])), 2),
        }

    def avg_rep_duration(self) -> float:
        full = self.full_reps or self.reps
        return round(float(np.mean([r.duration for r in full])), 2) if full else 0.0

    def active_bounds(self) -> tuple[float, float] | None:
        if not self.reps:
            return None
        return self.reps[0].start_t, self.reps[-1].end_t


def _depth(signal: np.ndarray, event: str) -> tuple[np.ndarray, float]:
    x = fill_nans(signal)
    if not np.isfinite(x).any():
        return np.zeros_like(x), 0.0
    y = x if event == "valley" else -x
    top = float(np.percentile(y, 90))
    bottom = float(np.percentile(y, 3))
    return top - y, top - bottom


def count_reps(t: np.ndarray, signal: np.ndarray, spec: ExerciseSpec) -> RepResult:
    t = np.asarray(t, dtype=float)
    depth, rng = _depth(signal, spec.event)
    n = len(depth)
    min_abs = max(10.0, MIN_ROM_FRAC_OF_EXPECTED * spec.expected_rom)
    if n < 3 or rng < min_abs:
        return RepResult(signal_range=float(rng))

    enter = max(ENTER_FRAC * rng, min_abs)
    exit_ = max(EXIT_FRAC * rng, 0.4 * min_abs)
    rest_level = REST_FRAC * rng

    excursions: list[tuple[int, int, int]] = []   # (open_idx, event_idx, close_idx)
    open_idx: int | None = None
    peak_idx = 0
    for i in range(n):
        if open_idx is None:
            if depth[i] > enter:
                open_idx, peak_idx = i, i
        else:
            if depth[i] > depth[peak_idx]:
                peak_idx = i
            if depth[i] < exit_:
                excursions.append((open_idx, peak_idx, i))
                open_idx = None
    unfinished_raw = (open_idx, peak_idx, n - 1) if open_idx is not None else None

    result = RepResult(signal_range=float(rng))
    prev_end = 0
    raw_reps: list[Rep] = []
    for k, (o, e, c) in enumerate(excursions):
        next_open = excursions[k + 1][0] if k + 1 < len(excursions) else (
            unfinished_raw[0] if unfinished_raw else n - 1)
        rep = _build_rep(t, depth, o, e, c, prev_end, next_open, rest_level, spec)
        prev_end = rep.end_idx
        if rep.duration < MIN_REP_SEC or rep.rom_deg < min_abs:
            continue
        raw_reps.append(rep)

    if raw_reps:
        best = float(np.percentile([r.rom_deg for r in raw_reps], 90))
        for r in raw_reps:
            r.full = (r.rom_deg >= PARTIAL_FRAC_OF_BEST * best
                      and r.rom_deg >= PARTIAL_FRAC_OF_EXPECTED * spec.expected_rom)
    result.reps = raw_reps

    if unfinished_raw is not None:
        o, e, c = unfinished_raw
        rep = _build_rep(t, depth, o, e, c, prev_end, n - 1, rest_level, spec)
        if depth[e] > 0.5 * rng and rep.duration >= MIN_REP_SEC:
            rep.full = False
            result.unfinished = rep
    return result


def _build_rep(t, depth, o, e, c, lo, hi, rest_level, spec: ExerciseSpec) -> Rep:
    s = o
    while s > lo and depth[s - 1] < depth[s] and depth[s] > rest_level:
        s -= 1
    f = c
    while f < hi and depth[f + 1] < depth[f] and depth[f] > rest_level:
        f += 1
    pre = float(t[e] - t[s])
    post = float(t[f] - t[e])
    ecc, con = (pre, post) if spec.event_ends_eccentric else (post, pre)
    return Rep(
        start_idx=int(s), event_idx=int(e), end_idx=int(f),
        start_t=float(t[s]), event_t=float(t[e]), end_t=float(t[f]),
        rom_deg=float(depth[e]), full=True,
        eccentric_sec=round(ecc, 3), concentric_sec=round(con, 3),
    )


def rom_score(result: RepResult, spec: ExerciseSpec) -> int:
    """0-100: average rep range of motion relative to the exercise's full ROM."""
    if not result.reps:
        return 0
    ratios = [min(1.0, r.rom_deg / spec.expected_rom) for r in result.reps]
    return int(round(100 * float(np.mean(ratios))))
