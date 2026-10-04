"""Cloud Run service: ``POST /analyze {bucket, path}`` -> ``{"analysis": {...}}``.

Deploy with ``--no-allow-unauthenticated``; the Cloud Function calls it with a
Google-signed ID token whose audience is the service URL. The service only
analyses: the function owns the Firestore writes.
"""

from __future__ import annotations

import logging
import re

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from .gcs import analyze_gcs_object
from .pipeline import AnalysisError

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("analyzer")

VIDEO_PATH = re.compile(r"^videos/[^/]+/[^/]+/[^/]+\.(mov|mp4)$", re.IGNORECASE)

app = FastAPI(title="Set video analyzer")


class AnalyzeRequest(BaseModel):
    bucket: str
    path: str


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}


@app.post("/analyze")
def analyze(req: AnalyzeRequest) -> dict:
    if not VIDEO_PATH.match(req.path):
        raise HTTPException(status_code=400, detail="path must be videos/{uid}/{sessionId}/{setId}.mov|mp4")
    try:
        analysis = analyze_gcs_object(req.bucket, req.path)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except AnalysisError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"analysis": analysis}
