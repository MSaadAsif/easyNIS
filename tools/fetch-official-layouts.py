"""Retrieve public NIS reference response bytes; never update annual registries."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
from urllib.parse import urlsplit


HOSTS = ("hcup-us.ahrq.gov", "hcup-ts.ahrq.gov")


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def fetch(url, directory, stem):
    body = directory / (stem + ".body")
    headers = directory / (stem + ".headers")
    receipt = {"requested_url": url, "started_utc": utc_now()}
    result = subprocess.run(
        ["curl", "--silent", "--show-error", "--location", "--max-redirs", "5",
         "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "5",
         "--max-time", "20", "--dump-header", str(headers), "--output", str(body),
         "--write-out", "%{http_code}\n%{url_effective}\n%{content_type}", url],
        capture_output=True, text=True, check=False,
    )
    fields = result.stdout.split("\n")
    status, final_url, content_type = (fields + [""] * 3)[:3]
    final = urlsplit(final_url)
    trusted = final.scheme == "https" and final.hostname in HOSTS
    outcome = ("transport_error" if result.returncode else
               "http_error" if status != "200" else
               "untrusted_redirect" if not trusted else "downloaded")
    receipt.update(completed_utc=utc_now(), curl_exit=result.returncode,
                   http_status=status, final_url=final_url, content_type=content_type,
                   outcome=outcome, error=result.stderr)
    for kind, path in (("body", body), ("headers", headers)):
        if path.exists():
            data = path.read_bytes()
            receipt[kind] = {"file": path.name, "bytes": len(data),
                             "sha256": hashlib.sha256(data).hexdigest()}
    return receipt


def source_requests(profile):
    if profile not in ("core", "all"):
        raise ValueError("Choose the core or all reference profile.")
    sources = []
    if profile == "all":
        sources.append({"year": None, "component": "index", "kind": "index",
                        "cache_filename": "nisfilespecs.jsp",
                        "path": "/db/nation/nis/nisfilespecs.jsp"})
    for year in range(2017, 2023):
        suffix = "_V2" if year in (2019, 2020) else ""
        components = ("Core",) if profile == "core" else ("Core", "Hospital", "Severity", "DX_PR_GRPS")
        for component in components:
            if year == 2017 and component == "DX_PR_GRPS":
                continue
            for kind in (("layout",) if profile == "core" else ("layout", "sas")):
                if kind == "layout":
                    filename = f"FileSpecifications_NIS_{year}_{component}{suffix}.TXT"
                    path = f"/db/nation/nis/tools/stats/{filename}"
                else:
                    filename = f"SASLoad_NIS_{year}_{component}{suffix}.SAS"
                    path = f"/db/nation/nis/tools/pgms/{filename}"
                sources.append({"year": year, "component": component, "kind": kind,
                                "cache_filename": filename, "path": path})
    return sources


def acquire(directory, profile="core"):
    sources = source_requests(profile)
    directory.mkdir(parents=True, exist_ok=False)
    scope = ("public 2017-2022 NIS Core specifications only" if profile == "core" else
             "public 2017-2022 NIS references and official specification index")
    manifest = {"scope": scope,
                "profile": profile,
                "created_utc": utc_now(), "attempts": [],
                "limitation": "Response bytes require source-specific validation and human review; "
                              "no annual support or conversion history is established."}
    manifest_path = directory / "manifest.json"
    for source in sources:
        for host in HOSTS:
            url = f"https://{host}{source['path']}"
            stem = (f"{source['year']}-{host}" if profile == "core" else
                    f"{source['year']}-{source['component']}-{source['kind']}-{host}")
            receipt = fetch(url, directory, stem)
            receipt.update({key: value for key, value in source.items() if key != "path"})
            manifest["attempts"].append(receipt)
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
            print(f"{source['cache_filename']} {host}: {receipt['outcome']}", flush=True)
            if receipt["outcome"] == "downloaded":
                break
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new ignored output directory")
    parser.add_argument("--profile", choices=("core", "all"), default="core")
    args = parser.parse_args()
    acquire(args.output, args.profile)
