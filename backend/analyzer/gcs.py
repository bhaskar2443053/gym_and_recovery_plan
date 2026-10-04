"""Download a set video from Cloud Storage and analyse it.

Shared by the Cloud Run service (``server.py``) and the Cloud Function's
in-process fallback, so both paths behave identically.
"""

from __future__ import annotations

import logging
import os
import tempfile

from .pipeline import analyze_video

log = logging.getLogger(__name__)


def _default_client():
    from google.cloud import storage  # lazy: not needed by the tests

    fb_emulator = os.environ.get("FIREBASE_STORAGE_EMULATOR_HOST")
    if fb_emulator and not os.environ.get("STORAGE_EMULATOR_HOST"):
        host = fb_emulator if fb_emulator.startswith("http") else f"http://{fb_emulator}"
        os.environ["STORAGE_EMULATOR_HOST"] = host
    if os.environ.get("STORAGE_EMULATOR_HOST"):
        from google.auth.credentials import AnonymousCredentials

        project = os.environ.get("GCLOUD_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT") or "demo-project"
        return storage.Client(project=project, credentials=AnonymousCredentials())
    return storage.Client()


def analyze_gcs_object(bucket_name: str, path: str, storage_client=None) -> dict:
    """Fetch ``gs://bucket/path`` with its custom metadata and analyse it.

    Honors ``STORAGE_EMULATOR_HOST`` (set by the Firebase emulator suite).
    """
    if storage_client is None:
        storage_client = _default_client()
    blob = storage_client.bucket(bucket_name).get_blob(path)
    if blob is None:
        raise FileNotFoundError(f"gs://{bucket_name}/{path} not found")
    metadata = dict(blob.metadata or {})
    suffix = os.path.splitext(path)[1] or ".mov"
    with tempfile.NamedTemporaryFile(suffix=suffix) as tmp:
        blob.download_to_filename(tmp.name)
        log.info("analysing gs://%s/%s (%d bytes)", bucket_name, path, blob.size or 0)
        return analyze_video(tmp.name, metadata)
