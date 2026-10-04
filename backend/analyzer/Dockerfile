# Cloud Run image for the analyzer. Build context: backend/analyzer
#   gcloud run deploy set-analyzer --source backend/analyzer ...
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    POSE_MODEL_PATH=/models/pose_landmarker_full.task

# libgl/glib are needed by MediaPipe's native libs; ffmpeg-backed OpenCV
# wheels already bundle their codecs for .mov/.mp4 (H.264 / HEVC).
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 curl \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /models && curl -fsSL -o "$POSE_MODEL_PATH" \
    https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task

WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# The package must be importable as `analyzer`.
COPY . /app/analyzer

ENV PORT=8080
CMD exec uvicorn analyzer.server:app --host 0.0.0.0 --port ${PORT} --workers 1
