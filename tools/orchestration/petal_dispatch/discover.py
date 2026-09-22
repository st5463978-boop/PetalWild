"""Probe this machine for a Hailo NPU and a local genai endpoint.

A closed port or a missing PCI id is an absence, not a model.
"""

from __future__ import annotations

import os
import shutil
import socket
from pathlib import Path
from urllib.parse import urlparse

HAILO_VENDOR = "0x1e60"
PREFERRED_MODELS = (
    "Qwen3-1.7B-Instruct",
    "Qwen2-1.5B-Instruct-FC",
)
HEF_DIRS = (
    Path("/usr/share/hailo"),
    Path("/opt/hailo"),
    Path("/opt/hailo-apps"),
    Path.home() / ".hailo",
    Path.home() / "hailo",
)


def _pci() -> list[dict]:
    root = Path("/sys/bus/pci/devices")
    found = []
    if not root.is_dir():
        return found
    for dev in sorted(root.iterdir()):
        vendor_path = dev / "vendor"
        if not vendor_path.is_file():
            continue
        vendor = vendor_path.read_text().strip().lower()
        if vendor not in (HAILO_VENDOR, "1e60"):
            continue
        device = (dev / "device").read_text().strip() if (dev / "device").is_file() else ""
        found.append({"slot": dev.name, "vendor": vendor, "device": device})
    return found


def _device_node() -> str:
    for node in ("/dev/hailo0", "/dev/hailo1"):
        if Path(node).exists():
            return node
    return ""


def _hefs() -> list[str]:
    found = []
    for directory in HEF_DIRS:
        if not directory.is_dir():
            continue
        found.extend(str(path) for path in directory.rglob("*.hef"))
    extra = os.environ.get("HAILO_MODEL_DIR", "")
    if extra:
        root = Path(extra)
        if root.is_dir():
            found.extend(str(path) for path in root.rglob("*.hef"))
    return found


def _endpoint_open(url: str) -> bool:
    parsed = urlparse(url)
    host = parsed.hostname or ""
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    if not host:
        return False
    sock = socket.socket()
    sock.settimeout(0.3)
    try:
        return sock.connect_ex((host, port)) == 0
    except OSError:
        return False
    finally:
        sock.close()


def candidate_urls() -> list[str]:
    urls = []
    env_url = os.environ.get("HAILO_GENAI_URL", "").strip()
    if env_url:
        urls.append(env_url.rstrip("/"))
    urls.extend(("http://127.0.0.1:8000", "http://127.0.0.1:11434"))
    seen = []
    for url in urls:
        if url not in seen:
            seen.append(url)
    return seen


def discover() -> dict:
    pci = _pci()
    node = _device_node()
    hefs = _hefs()
    endpoints = [url for url in candidate_urls() if _endpoint_open(url)]
    hardware = bool(pci or node)
    # An HTTP genai server is only treated as Hailo when the chip is also here.
    # A random local model server is not this NPU.
    available = hardware and bool(endpoints)
    return {
        "hardware": hardware,
        "pci": pci,
        "device_node": node,
        "hailortcli": shutil.which("hailortcli") or "",
        "hef": hefs,
        "endpoints": endpoints,
        "preferred_models": list(PREFERRED_MODELS),
        "available": available,
        "reason": "" if available else _reason(hardware, endpoints, hefs),
    }


def _reason(hardware: bool, endpoints: list[str], hefs: list[str]) -> str:
    if not hardware and not endpoints and not hefs:
        return "no_hailo_device"
    if not hardware:
        return "genai_port_without_hailo_hardware"
    if hefs and not endpoints:
        return "hef_present_no_genai_endpoint"
    return "hailo_present_no_genai_endpoint"
