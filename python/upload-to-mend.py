#!/bin/sh
''':'
if command -v uv >/dev/null 2>&1; then
  exec uv run --script "$0" "$@"
else
  exec python3 "$0" "$@"
fi
':'''
# /// script
# dependencies = [
#   "requests",
# ]
# ///
"""Upload a Syft-generated CycloneDX SBOM to Mend via REST API.

Two uploads per run:
  1. Historical — new project per scan using the full timestamped image name.
  2. Latest     — upsert using the simple image name (timestamp stripped).

Required environment variables:
  MEND_EMAIL                          User email for authentication
  MEND_AUTH_KEY                       User key (secret)
  MEND_APP_UUID_MACHINE_IMAGES        App UUID for the historical application
  MEND_APP_UUID_MACHINE_IMAGES_LATEST App UUID for the rolling-latest application
  MEND_CLOUD                          Cloud provider prefix: aws, gcp, or az
  SBOM_FILE                           Path to the CycloneDX JSON file
  SHORT_ARCH                          Architecture prefix: x86 or arm
"""

import json
import logging
import os
import re
import time
from pathlib import Path

import requests

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)

MEND_BASE_URL = "https://api-saas-eu.mend.io/api/v3.0"

POLL_INTERVAL_SEC = 15
POLL_MAX_ATTEMPTS = 10  # ~2.5 minutes per scan

def _require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Required environment variable {name!r} is not set")
    return value


def _auth_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _extract(body: dict, *key_paths: str) -> str:
    """Walk dot-separated key paths and return the first non-empty string found."""
    for key_path in key_paths:
        obj: object = body
        for k in key_path.split("."):
            if not isinstance(obj, dict):
                break
            obj = obj.get(k, "")
        if isinstance(obj, str) and obj:
            return obj
    return ""


def login(email: str, user_key: str) -> tuple[str, str]:
    """Authenticate with Mend. Returns (access_token, org_uuid).

    Two-step flow:
      1. POST /login          → refresh token  (in response.refreshToken)
      2. POST /login/accessToken  (wss-refresh-token header) → access token (in response.jwtToken)
                                                              + org UUID    (in response.orgUuid)
    """
    resp = requests.post(
        f"{MEND_BASE_URL}/login",
        json={"email": email, "userKey": user_key},
        timeout=30,
    )
    resp.raise_for_status()
    refresh_token = _extract(resp.json(), "response.refreshToken")
    if not refresh_token:
        keys = list(resp.json().get("response", resp.json()).keys())
        raise RuntimeError(f"No refreshToken in login response (keys: {keys}): {resp.text[:500]}")

    resp2 = requests.post(
        f"{MEND_BASE_URL}/login/accessToken",
        headers={"wss-refresh-token": refresh_token},
        timeout=30,
    )
    resp2.raise_for_status()
    access_token = _extract(resp2.json(), "response.jwtToken")
    if not access_token:
        keys = list(resp2.json().get("response", resp2.json()).keys())
        raise RuntimeError(f"No jwtToken in accessToken response (keys: {keys}): {resp2.text[:500]}")
    org_uuid = _extract(resp2.json(), "response.orgUuid")
    if not org_uuid:
        keys = list(resp2.json().get("response", resp2.json()).keys())
        raise RuntimeError(f"No orgUuid in accessToken response (keys: {keys}): {resp2.text[:500]}")
    return access_token, org_uuid


def upload_new_project(
    token: str,
    app_uuid: str,
    project_name: str,
    sbom_path: Path,
) -> tuple[str, str]:
    """Create a new Mend project and import the SBOM. Returns (project_uuid, scan_uuid)."""
    with sbom_path.open("rb") as f:
        resp = requests.post(
            f"{MEND_BASE_URL}/applications/{app_uuid}/dependencies/projects/importSbom",
            headers=_auth_headers(token),
            data={"projectName": project_name},
            files={"sbomFile": (sbom_path.name, f, "application/json")},
            timeout=120,
        )
    if not resp.ok:
        log.error("importSbom failed (status=%d): %s", resp.status_code, resp.text[:1000])
    resp.raise_for_status()
    body = resp.json()
    project_uuid = _extract(body, "response.project.uuid", "retVal.project.uuid", "project.uuid")
    scan_uuid = _extract(
        body,
        "response.scan.scanUuid",
        "response.scanUuid",
        "retVal.scan.scanUuid",
        "scan.scanUuid",
        "retVal.scanUuid",
        "scanUuid",
    )
    log.info("Created project %r (project=%s scan=%s)", project_name, project_uuid, scan_uuid)
    return project_uuid, scan_uuid


def find_project_uuid(token: str, org_uuid: str, app_uuid: str, project_name: str) -> str | None:
    """Return the UUID of the named project in the application, or None if not found.

    Follows cursor-based pagination until the project is found or all pages are exhausted.
    Projects are fetched at org scope and filtered by both name and applicationUuid.
    """
    url = f"{MEND_BASE_URL}/orgs/{org_uuid}/projects"
    while True:
        resp = requests.get(url, headers=_auth_headers(token), timeout=30)
        resp.raise_for_status()
        body = resp.json()
        projects: list = body.get("response") or []
        for p in projects:
            if p.get("name") == project_name and p.get("applicationUuid") == app_uuid:
                return p.get("uuid") or p.get("projectUuid")
        next_url: str = body.get("additionalData", {}).get("paging", {}).get("next", "")
        if not next_url:
            return None
        url = next_url


def update_project(token: str, project_uuid: str, sbom_path: Path) -> tuple[str, str]:
    """Re-import the SBOM into an existing project. Returns (project_uuid, scan_uuid)."""
    with sbom_path.open("rb") as f:
        resp = requests.post(
            f"{MEND_BASE_URL}/projects/{project_uuid}/dependencies/importSbom",
            headers=_auth_headers(token),
            files={"sbomFile": (sbom_path.name, f, "application/json")},
            timeout=120,
        )
    if not resp.ok:
        log.error("importSbom (update) failed (status=%d): %s", resp.status_code, resp.text[:1000])
    resp.raise_for_status()
    body = resp.json()
    scan_uuid = _extract(
        body,
        "response.scan.scanUuid",
        "response.scanUuid",
        "retVal.scan.scanUuid",
        "scan.scanUuid",
        "retVal.scanUuid",
        "scanUuid",
    )
    log.info("Updated project %s (scan=%s)", project_uuid, scan_uuid)
    return project_uuid, scan_uuid


def poll_scan_log(token: str, project_uuid: str, scan_uuid: str, label: str) -> None:
    """Best-effort: wait for the scan to finish and print its log. Never raises."""
    if not project_uuid or not scan_uuid:
        log.warning("[%s] Missing project/scan UUID — skipping log retrieval", label)
        return

    url = (
        f"{MEND_BASE_URL}/projects/{project_uuid}"
        f"/scans/{scan_uuid}/dependencies/SBOM/logs"
    )
    for attempt in range(1, POLL_MAX_ATTEMPTS + 1):
        try:
            resp = requests.get(url, headers=_auth_headers(token), timeout=30)
            if resp.status_code == 200:
                log.info("[%s] Scan log:\n%s", label, resp.text[:2000])
                return
            log.debug(
                "[%s] Scan not ready yet (status=%d, attempt=%d/%d)",
                label, resp.status_code, attempt, POLL_MAX_ATTEMPTS,
            )
        except requests.RequestException as exc:
            log.warning("[%s] Error polling log (attempt %d): %s", label, attempt, exc)
        time.sleep(POLL_INTERVAL_SEC)

    log.warning(
        "[%s] Scan log unavailable after %d attempts — skipping", label, POLL_MAX_ATTEMPTS
    )


def main() -> None:
    email = _require_env("MEND_EMAIL")
    user_key = _require_env("MEND_AUTH_KEY")
    app_uuid_historical = _require_env("MEND_APP_UUID_MACHINE_IMAGES")
    app_uuid_latest = _require_env("MEND_APP_UUID_MACHINE_IMAGES_LATEST")
    cloud = _require_env("MEND_CLOUD")
    arch = _require_env("SHORT_ARCH")
    sbom_path = Path(_require_env("SBOM_FILE"))

    if not sbom_path.is_file():
        raise FileNotFoundError(f"SBOM file not found: {sbom_path}")

    # Syft embeds --source-name into metadata.component.name of the CycloneDX JSON.
    sbom_data = json.loads(sbom_path.read_text())
    image_name: str = sbom_data["metadata"]["component"]["name"]
    image_simple = re.sub(r"-\d{14}$", "", image_name)

    # Project names are prefixed with <cloud>-<arch>- for cross-cloud/arch disambiguation.
    prefix = f"{cloud}-{arch}"
    full_name = f"{prefix}-{image_name}"
    simple_name = f"{prefix}-{image_simple}"
    log.info("Image: %s  →  projects: %s / %s", image_name, full_name, simple_name)

    log.info("Authenticating with Mend...")
    token, org_uuid = login(email, user_key)

    # Upload 1 — historical (new project per scan, full timestamped name)
    log.info("--- Upload 1/2: historical ---")
    hist_project_uuid, hist_scan_uuid = upload_new_project(
        token, app_uuid_historical, full_name, sbom_path
    )

    # Upload 2 — latest (upsert, simple name without timestamp)
    log.info("--- Upload 2/2: latest ---")
    existing_uuid = find_project_uuid(token, org_uuid, app_uuid_latest, simple_name)
    if existing_uuid:
        log.info("Project exists (%s) — updating", existing_uuid)
        latest_project_uuid, latest_scan_uuid = update_project(token, existing_uuid, sbom_path)
    else:
        log.info("Project not found — creating")
        latest_project_uuid, latest_scan_uuid = upload_new_project(
            token, app_uuid_latest, simple_name, sbom_path
        )

    # Optional log retrieval (best-effort, non-blocking)
    log.info("--- Polling scan logs (best-effort) ---")
    poll_scan_log(token, hist_project_uuid, hist_scan_uuid, "historical")
    poll_scan_log(token, latest_project_uuid, latest_scan_uuid, "latest")

    log.info("Both uploads complete.")


if __name__ == "__main__":
    main()
