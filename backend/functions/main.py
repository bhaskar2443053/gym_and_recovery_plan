"""Cloud Function: analyse each uploaded set video.

Trigger: object finalized in the default Storage bucket under
``videos/{uid}/{sessionId}/{setId}.mov|.mp4``.

1. Marks ``users/{uid}/sessions/{sessionId}/sets/{setId}`` as
   ``status: "processing"``.
2. Runs the analysis, either on the Cloud Run analyzer (``ANALYZER_URL`` set;
   authenticated with a Google-signed ID token) or, when ``ANALYZER_URL`` is
   unset, in-process by importing ``backend/analyzer`` (local emulator).
3. Writes ``status: "done"`` + ``analysis`` + ``analyzedAt``, or
   ``status: "failed"`` + ``error``.
"""

from __future__ import annotations

import logging
import os
import re
import sys
from pathlib import Path

from firebase_admin import firestore, initialize_app
from firebase_functions import options, storage_fn
from google.cloud.firestore import SERVER_TIMESTAMP

initialize_app()
log = logging.getLogger("analyze_set_video")

VIDEO_PATH = re.compile(r"^videos/([^/]+)/([^/]+)/([^/]+)\.(mov|mp4)$", re.IGNORECASE)
ANALYZER_TIMEOUT_SEC = 500


def parse_video_path(name: str | None) -> tuple[str, str, str] | None:
    """Return (uid, sessionId, setId) for a contract path, else None."""
    m = VIDEO_PATH.match(name or "")
    if not m:
        return None
    uid, session_id, set_id, _ext = m.groups()
    return uid, session_id, set_id


def set_doc(uid: str, session_id: str, set_id: str):
    return (firestore.client().collection("users").document(uid)
            .collection("sessions").document(session_id)
            .collection("sets").document(set_id))


def run_remote(analyzer_url: str, bucket: str, path: str) -> dict:
    import google.auth.transport.requests
    import google.oauth2.id_token
    import requests

    base = analyzer_url.rstrip("/")
    token = google.oauth2.id_token.fetch_id_token(google.auth.transport.requests.Request(), base)
    resp = requests.post(
        f"{base}/analyze",
        json={"bucket": bucket, "path": path},
        headers={"Authorization": f"Bearer {token}"},
        timeout=ANALYZER_TIMEOUT_SEC,
    )
    if resp.status_code != 200:
        try:
            detail = resp.json().get("detail")
        except ValueError:
            detail = resp.text[:300]
        raise RuntimeError(f"analyzer returned {resp.status_code}: {detail}")
    return resp.json()["analysis"]


def run_in_process(bucket: str, path: str) -> dict:
    try:
        from analyzer.gcs import analyze_gcs_object
    except ImportError:
        # Local emulator: functions/ and analyzer/ are siblings under backend/.
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
        from analyzer.gcs import analyze_gcs_object
    return analyze_gcs_object(bucket, path)


@storage_fn.on_object_finalized(
    timeout_sec=540,
    # The heavy lifting runs on Cloud Run; the in-process fallback is for the
    # emulator, which does not enforce memory limits.
    memory=options.MemoryOption.MB_512,
)
def analyze_set_video(event: storage_fn.CloudEvent[storage_fn.StorageObjectData]) -> None:
    obj = event.data
    ids = parse_video_path(obj.name)
    if ids is None:
        return  # not a set video
    uid, session_id, set_id = ids
    doc = set_doc(uid, session_id, set_id)
    doc.set({"status": "processing", "error": None}, merge=True)

    analyzer_url = os.environ.get("ANALYZER_URL", "").strip()
    try:
        if analyzer_url:
            analysis = run_remote(analyzer_url, obj.bucket, obj.name)
        else:
            analysis = run_in_process(obj.bucket, obj.name)
    except Exception as exc:  # report every failure to the app
        log.exception("analysis failed for %s", obj.name)
        doc.set({
            "status": "failed",
            "error": str(exc)[:500] or exc.__class__.__name__,
            "analyzedAt": SERVER_TIMESTAMP,
        }, merge=True)
        return

    # Plain set (not merge) for the map so stale keys from a previous upload of
    # the same set never linger; other fields on the doc are kept by merge.
    doc.set({
        "status": "done",
        "error": None,
        "analyzedAt": SERVER_TIMESTAMP,
        "analysis": analysis,
    }, merge=["status", "error", "analyzedAt", "analysis"])
