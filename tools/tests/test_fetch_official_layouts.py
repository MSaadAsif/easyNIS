"""Offline public-response fixtures; no annual metadata is authenticated."""

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "fetch_layouts", Path(__file__).resolve().parents[1] / "fetch-official-layouts.py")
fetch_layouts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetch_layouts)


class FetchTests(unittest.TestCase):
    def response(self, args, **kwargs):
        self.assertFalse(kwargs["check"])
        self.assertIn("--max-time", args)
        self.assertIn("--proto-redir", args)
        Path(args[args.index("--output") + 1]).write_bytes(b"invented\r\n\xff\x00\n")
        Path(args[args.index("--dump-header") + 1]).write_bytes(b"HTTP/2 200\r\n\r\n")
        return subprocess.CompletedProcess(args, 0, "200\n" + args[-1] + "\ntext/plain", "")

    def test_exact_bytes_and_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            url = "https://hcup-us.ahrq.gov/invented"
            with patch.object(fetch_layouts.subprocess, "run", side_effect=self.response):
                receipt = fetch_layouts.fetch(url, directory, "invented")
            self.assertEqual(receipt["outcome"], "downloaded")
            self.assertEqual(receipt["requested_url"], url)
            self.assertEqual(receipt["final_url"], url)
            self.assertEqual(receipt["body"]["bytes"], 13)
            self.assertEqual(receipt["body"]["sha256"], hashlib.sha256(b"invented\r\n\xff\x00\n").hexdigest())
            self.assertEqual((directory / "invented.body").read_bytes(), b"invented\r\n\xff\x00\n")
            self.assertIn("+00:00", receipt["completed_utc"])
            self.assertIn("sha256", receipt["headers"])

    def test_transport_http_and_redirect_failures(self):
        cases = [(28, "000\nhttps://hcup-us.ahrq.gov/x\n", "transport_error"),
                 (0, "502\nhttps://hcup-us.ahrq.gov/x\ntext/html", "http_error"),
                 (0, "200\nhttps://example.org/x\ntext/plain", "untrusted_redirect"),
                 (0, "200\nhttp://hcup-us.ahrq.gov/x\ntext/plain", "untrusted_redirect")]
        with tempfile.TemporaryDirectory() as temporary:
            for code, stdout, outcome in cases:
                with self.subTest(outcome=outcome, stdout=stdout):
                    result = subprocess.CompletedProcess([], code, stdout, "invented error")
                    with patch.object(fetch_layouts.subprocess, "run", return_value=result):
                        receipt = fetch_layouts.fetch("https://hcup-us.ahrq.gov/x", Path(temporary), "failure")
                    self.assertEqual(receipt["outcome"], outcome)
                    self.assertEqual(receipt["error"], "invented error")
                    self.assertNotIn("body", receipt)

    def test_batch_fallback_manifest_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "new"
            attempts = []

            def fake_fetch(url, output, stem):
                attempts.append(url)
                return {"outcome": "transport_error" if "hcup-us" in url else "downloaded"}

            with patch.object(fetch_layouts, "fetch", side_effect=fake_fetch):
                manifest = fetch_layouts.acquire(directory)
                with self.assertRaises(FileExistsError):
                    fetch_layouts.acquire(directory)
            self.assertEqual(len(attempts), 12)
            self.assertEqual(json.loads((directory / "manifest.json").read_text()), manifest)
            for receipt in manifest["attempts"]:
                year = receipt["year"]
                suffix = "_V2" if year in (2019, 2020) else ""
                self.assertEqual(receipt["cache_filename"], f"FileSpecifications_NIS_{year}_Core{suffix}.TXT")

    def test_success_does_not_retry_alternate_host(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(fetch_layouts, "fetch", side_effect=lambda *args: {"outcome": "downloaded"}) as mock:
                manifest = fetch_layouts.acquire(Path(temporary) / "new")
            self.assertEqual(mock.call_count, 6)
            self.assertEqual(len(manifest["attempts"]), 6)
            self.assertEqual([row["year"] for row in manifest["attempts"]], list(range(2017, 2023)))

    def test_partial_failure_bytes_are_retained_as_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)

            def partial(args, **kwargs):
                self.response(args, **kwargs)
                return subprocess.CompletedProcess(args, 28, "200\n" + args[-1] + "\ntext/plain", "timeout")

            with patch.object(fetch_layouts.subprocess, "run", side_effect=partial):
                receipt = fetch_layouts.fetch("https://hcup-us.ahrq.gov/x", directory, "partial")
            self.assertEqual(receipt["outcome"], "transport_error")
            self.assertEqual(receipt["curl_exit"], 28)
            self.assertEqual(receipt["body"]["sha256"], hashlib.sha256((directory / "partial.body").read_bytes()).hexdigest())

    def test_all_failure_manifest_contains_every_attempt(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(fetch_layouts, "fetch", side_effect=lambda *args: {"outcome": "http_error"}):
                manifest = fetch_layouts.acquire(Path(temporary) / "new")
            self.assertEqual(len(manifest["attempts"]), 12)
            self.assertTrue(all(row["outcome"] == "http_error" for row in manifest["attempts"]))


if __name__ == "__main__":
    unittest.main()
