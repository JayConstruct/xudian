#!/usr/bin/env python3
"""Render the Xudian SVG master into Android and Windows icon resources."""

from __future__ import annotations

import io
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
BRAND = ROOT / "assets" / "brand"
MASTER = BRAND / "icon.svg"
ANDROID_RES = ROOT / "client" / "android" / "app" / "src" / "main" / "res"
WINDOWS_ICON = ROOT / "client" / "windows" / "runner" / "resources" / "app_icon.ico"
LEGACY_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE_SIZES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def render(svg: bytes) -> Image.Image:
    result = subprocess.run(
        ["rsvg-convert", "--width", "1024", "--height", "1024"],
        input=svg,
        stdout=subprocess.PIPE,
        check=True,
    )
    return Image.open(io.BytesIO(result.stdout)).convert("RGBA")


def save_sizes(image: Image.Image, sizes: dict[str, int], folder: str, filename: str) -> None:
    for density, size in sizes.items():
        target = ANDROID_RES / f"{folder}-{density}" / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        image.resize((size, size), Image.Resampling.LANCZOS).save(target)


def foreground_svg() -> bytes:
    ET.register_namespace("", "http://www.w3.org/2000/svg")
    root = ET.fromstring(MASTER.read_bytes())
    for child in list(root):
        if child.get("id") in {"background-shape", "ambient-orb"}:
            root.remove(child)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def main() -> None:
    icon = render(MASTER.read_bytes())
    foreground = render(foreground_svg())
    icon.save(BRAND / "icon_preview.png")
    save_sizes(icon, LEGACY_SIZES, "mipmap", "ic_launcher.png")
    save_sizes(foreground, ADAPTIVE_SIZES, "drawable", "ic_launcher_foreground.png")
    WINDOWS_ICON.parent.mkdir(parents=True, exist_ok=True)
    icon.save(WINDOWS_ICON, format="ICO", sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)])
    print("Generated Android icons, Windows icon, and preview from", MASTER)


if __name__ == "__main__":
    main()
