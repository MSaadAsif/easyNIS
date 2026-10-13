"""Retrieve public Core specification response bytes; never update the registry."""

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


def acquire(directory):
    directory.mkdir(parents=True, exist_ok=False)
    manifest = {"scope": "public 2017-2022 NIS Core specifications only",
                "created_utc": utc_now(), "attempts": [],
                "limitation": "Response bytes require parser and human source review; "
                              "no annual support or conversion history is established."}
    manifest_path = directory / "manifest.json"
    for year in range(2017, 2023):
        suffix = "_V2" if year in (2019, 2020) else ""
        filename = f"FileSpecifications_NIS_{year}_Core{suffix}.TXT"
        for host in HOSTS:
            url = f"https://{host}/db/nation/nis/tools/stats/{filename}"
            receipt = fetch(url, directory, f"{year}-{host}")
            receipt.update(year=year, cache_filename=filename)
            manifest["attempts"].append(receipt)
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
            print(f"{year} {host}: {receipt['outcome']}", flush=True)
            if receipt["outcome"] == "downloaded":
                break
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new ignored output directory")
    acquire(parser.parse_args().output)
