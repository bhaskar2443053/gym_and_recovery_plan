"""Pose-based analysis of per-set workout videos.

The pure-numpy modules (features, classify, reps, form, load, pipeline) import
without MediaPipe or OpenCV; only ``analyzer.pose`` needs them, and it imports
them lazily.
"""

__version__ = "1.0.0"
