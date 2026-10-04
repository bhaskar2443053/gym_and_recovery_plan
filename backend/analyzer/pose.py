"""Pose estimation over a video file.

The rest of the analyzer only sees :class:`PoseSequence`: an array of
``(frames, 33, 4)`` landmarks in MediaPipe's BlazePose topology
(x, y normalised to the image, z relative depth, visibility 0-1). Any other
estimator (MoveNet, a Core ML model, ...) can be plugged in by implementing
:class:`PoseEstimator` and mapping its keypoints onto those 33 indices.

MediaPipe and OpenCV are imported lazily so that the pure-numpy modules and
their tests run without them.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import Protocol

import numpy as np

log = logging.getLogger(__name__)

NUM_LANDMARKS = 33
DEFAULT_TARGET_FPS = 15.0

# BlazePose landmark indices used by the analyzer.
NOSE = 0
L_SHOULDER, R_SHOULDER = 11, 12
L_ELBOW, R_ELBOW = 13, 14
L_WRIST, R_WRIST = 15, 16
L_HIP, R_HIP = 23, 24
L_KNEE, R_KNEE = 25, 26
L_ANKLE, R_ANKLE = 27, 28


@dataclass
class PoseSequence:
    """Landmarks for the sampled frames of one video.

    landmarks:  float array (T, 33, 4): x, y in [0, 1] of width / height,
                z (relative), visibility in [0, 1]. Frames with no detected
                person are NaN with visibility 0.
    timestamps: float array (T,), seconds from the start of the video.
    aspect:     width / height of the frames, so x can be rescaled to the
                same units as y before computing angles.
    duration:   video duration in seconds.
    """

    landmarks: np.ndarray
    timestamps: np.ndarray
    aspect: float = 1.0
    duration: float | None = None

    def __post_init__(self) -> None:
        self.landmarks = np.asarray(self.landmarks, dtype=float)
        self.timestamps = np.asarray(self.timestamps, dtype=float)
        if self.landmarks.ndim != 3 or self.landmarks.shape[1:] != (NUM_LANDMARKS, 4):
            raise ValueError(f"landmarks must be (T, 33, 4), got {self.landmarks.shape}")
        if len(self.timestamps) != len(self.landmarks):
            raise ValueError("timestamps and landmarks length differ")
        if self.duration is None:
            self.duration = float(self.timestamps[-1]) if len(self.timestamps) else 0.0

    @property
    def num_frames(self) -> int:
        return int(self.landmarks.shape[0])


class PoseEstimator(Protocol):
    def estimate(self, video_path: str, target_fps: float = DEFAULT_TARGET_FPS) -> PoseSequence:
        ...


def _iter_frames(video_path: str, target_fps: float):
    """Yield (timestamp_sec, rgb_frame) sampled at ~target_fps, plus metadata.

    OpenCV >= 4.5 applies the rotation stored in iPhone .mov files by default
    (CAP_PROP_ORIENTATION_AUTO), so portrait videos come out upright.
    """
    import cv2  # lazy

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"cannot open video {video_path}")
    try:
        src_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        if not np.isfinite(src_fps) or src_fps <= 1:
            src_fps = 30.0
        step = max(1, int(round(src_fps / target_fps)))
        idx = 0
        while True:
            ok = cap.grab()
            if not ok:
                break
            if idx % step == 0:
                ok, frame = cap.retrieve()
                if not ok:
                    break
                pos_ms = cap.get(cv2.CAP_PROP_POS_MSEC)
                t = pos_ms / 1000.0 if pos_ms and pos_ms > 0 else idx / src_fps
                yield t, cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            idx += 1
    finally:
        cap.release()


class MediaPipePoseEstimator:
    """MediaPipe pose, Tasks API (PoseLandmarker) with legacy fallback.

    The Tasks API needs a ``.task`` model file; its path comes from the
    ``POSE_MODEL_PATH`` env var (the Dockerfile downloads
    ``pose_landmarker_full.task``). If it is missing, the legacy
    ``mediapipe.solutions.pose`` API is used when the installed MediaPipe
    still ships it.
    """

    def __init__(self, model_path: str | None = None, min_confidence: float = 0.5):
        self.model_path = model_path or os.environ.get("POSE_MODEL_PATH")
        self.min_confidence = min_confidence

    def estimate(self, video_path: str, target_fps: float = DEFAULT_TARGET_FPS) -> PoseSequence:
        import mediapipe as mp  # lazy

        times: list[float] = []
        frames: list[np.ndarray] = []
        shape: tuple[int, int] | None = None

        if self.model_path and os.path.exists(self.model_path):
            from mediapipe.tasks import python as mp_tasks
            from mediapipe.tasks.python import vision

            options = vision.PoseLandmarkerOptions(
                base_options=mp_tasks.BaseOptions(model_asset_path=self.model_path),
                running_mode=vision.RunningMode.VIDEO,
                num_poses=1,
                min_pose_detection_confidence=self.min_confidence,
                min_tracking_confidence=self.min_confidence,
            )
            last_ms = -1
            with vision.PoseLandmarker.create_from_options(options) as landmarker:
                for t, rgb in _iter_frames(video_path, target_fps):
                    shape = rgb.shape[:2]
                    ts_ms = max(int(t * 1000), last_ms + 1)  # must strictly increase
                    last_ms = ts_ms
                    image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
                    result = landmarker.detect_for_video(image, ts_ms)
                    times.append(t)
                    if result.pose_landmarks:
                        frames.append(_to_array(result.pose_landmarks[0]))
                    else:
                        frames.append(_empty())
        else:
            solutions = getattr(mp, "solutions", None)
            if solutions is None:
                raise RuntimeError(
                    "MediaPipe legacy solutions unavailable; set POSE_MODEL_PATH "
                    "to a pose_landmarker .task model"
                )
            with solutions.pose.Pose(
                static_image_mode=False,
                model_complexity=1,
                min_detection_confidence=self.min_confidence,
                min_tracking_confidence=self.min_confidence,
            ) as pose:
                for t, rgb in _iter_frames(video_path, target_fps):
                    shape = rgb.shape[:2]
                    result = pose.process(rgb)
                    times.append(t)
                    if result.pose_landmarks:
                        frames.append(_to_array(result.pose_landmarks.landmark))
                    else:
                        frames.append(_empty())

        if not frames:
            raise RuntimeError("video contained no decodable frames")
        h, w = shape if shape else (1, 1)
        return PoseSequence(
            landmarks=np.stack(frames),
            timestamps=np.asarray(times),
            aspect=float(w) / float(h),
            duration=float(times[-1]) if times else 0.0,
        )


def _to_array(landmarks) -> np.ndarray:
    out = np.empty((NUM_LANDMARKS, 4))
    for i, lm in enumerate(list(landmarks)[:NUM_LANDMARKS]):
        vis = getattr(lm, "visibility", None)
        out[i] = (lm.x, lm.y, lm.z, 1.0 if vis is None else vis)
    return out


def _empty() -> np.ndarray:
    out = np.full((NUM_LANDMARKS, 4), np.nan)
    out[:, 3] = 0.0
    return out


def default_estimator() -> PoseEstimator:
    return MediaPipePoseEstimator()
