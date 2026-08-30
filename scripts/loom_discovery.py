#!/usr/bin/env python3
"""Discover the first Loom `_loom._tcp` service advertised over mDNS."""

import os
import subprocess
import sys
import tempfile
import time
from typing import Optional


def _url_from_zone(text: str) -> Optional[str]:
    for line in text.splitlines():
        fields = line.split()
        if "SRV" not in fields:
            continue
        index = fields.index("SRV")
        if index < 1 or not fields[0].endswith("._loom._tcp") or len(fields) <= index + 4:
            continue
        port = fields[index + 3]
        host = fields[index + 4].rstrip(".")
        if port.isdigit() and host:
            return f"http://{host}:{port}"
    return None


def discover_loom(timeout: float = 5.0) -> str:
    with tempfile.TemporaryFile(mode="w+") as output:
        process = subprocess.Popen(
            ["dns-sd", "-Z", "_loom._tcp", "local."],
            stdout=output,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                text = os.pread(output.fileno(), 65536, 0).decode(errors="replace")
                if url := _url_from_zone(text):
                    return url
                if process.poll() is not None:
                    break
                time.sleep(0.1)
            raise RuntimeError("no Loom service found over mDNS")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    try:
        print(discover_loom())
    except (OSError, RuntimeError) as error:
        print(f"loom discovery failed: {error}", file=sys.stderr)
        raise SystemExit(1)
