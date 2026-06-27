#\!/usr/bin/env python3
"""SpriteFlow CLI: chroma key, slice spritesheets, emit diagnostics and UrhoX Sprite2D XML."""
from __future__ import annotations

import argparse
import json
import math
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Optional, Tuple
from xml.sax.saxutils import escape

try:
    from PIL import Image
except ImportError as exc:
    raise SystemExit("Pillow is required. Install with: python3 -m pip install Pillow") from exc


@dataclass
class Rect:
    x: int
    y: int
    w: int
    h: int


@dataclass
class FrameDiagnostic:
    index: int
    rect: Rect
    content: Optional[Rect]
    occupancy: float
    centerOffsetX: float
    centerOffsetY: float
    warnings: list[str]


def parse_color(value: Optional[str]) -> Optional[Tuple[int, int, int]]:
    if not value:
        return None
    s = value.strip()
    if s.startswith("#"):
        s = s[1:]
    if len(s) == 3:
        s = "".join(ch * 2 for ch in s)
    if not re.fullmatch(r"[0-9a-fA-F]{6}", s):
        raise SystemExit(f"Invalid color: {value}")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


def key_background(img: Image.Image, key: Tuple[int, int, int], tolerance: int) -> Image.Image:
    rgba = img.convert("RGBA")
    px = rgba.load()
    tol2 = tolerance * tolerance * 3
    kr, kg, kb = key
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            d2 = (r - kr) ** 2 + (g - kg) ** 2 + (b - kb) ** 2
            if d2 <= tol2:
                px[x, y] = (r, g, b, 0)
    return rgba


def content_bounds(img: Image.Image, rect: Rect, alpha_cutoff: int = 24) -> Optional[Rect]:
    bounds, _ = content_bounds_and_count(img, rect, alpha_cutoff)
    return bounds


def content_bounds_and_count(img: Image.Image, rect: Rect, alpha_cutoff: int = 24) -> tuple[Optional[Rect], int]:
    rgba = img.convert("RGBA")
    px = rgba.load()
    min_x, min_y = 10**9, 10**9
    max_x, max_y = -1, -1
    count = 0
    x0 = max(0, rect.x)
    y0 = max(0, rect.y)
    x1 = min(rgba.width, rect.x + rect.w)
    y1 = min(rgba.height, rect.y + rect.h)
    for y in range(y0, y1):
        for x in range(x0, x1):
            if px[x, y][3] > alpha_cutoff:
                count += 1
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if count < 4 or max_x < min_x or max_y < min_y:
        return None, count
    return Rect(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1), count


def detect_content_band(img: Image.Image, pad_ratio: float = 0.02) -> Rect:
    bounds = content_bounds(img, Rect(0, 0, img.width, img.height))
    if not bounds:
        return Rect(0, 0, img.width, img.height)
    pad = max(6, round(img.height * pad_ratio))
    y = max(0, bounds.y - pad)
    bottom = min(img.height, bounds.y + bounds.h + pad)
    # Match the original SpriteFlow behavior: for single-row sheets, trim only
    # the vertical content band. Keep the full sheet width so columns remain
    # aligned to the model's intended 1xN grid.
    return Rect(0, y, img.width, max(1, bottom - y))


def frame_rects(img: Image.Image, rows: int, cols: int, frame_count: int, content_band: bool) -> list[Rect]:
    area = detect_content_band(img) if content_band and rows == 1 else Rect(0, 0, img.width, img.height)
    cell_w = area.w / cols
    cell_h = area.h / rows
    rects: list[Rect] = []
    total = min(frame_count, rows * cols)
    for i in range(total):
        row = i // cols
        col = i % cols
        x = round(area.x + col * cell_w)
        y = round(area.y + row * cell_h)
        x2 = round(area.x + (col + 1) * cell_w)
        y2 = round(area.y + (row + 1) * cell_h)
        rects.append(Rect(x, y, max(1, x2 - x), max(1, y2 - y)))
    return rects


def diagnose_frame(img: Image.Image, rect: Rect, index: int) -> FrameDiagnostic:
    content, pixel_count = content_bounds_and_count(img, rect)
    warnings: list[str] = []
    if content is None:
        warnings.append("empty-frame")
        return FrameDiagnostic(index, rect, None, 0.0, 0.0, 0.0, warnings)
    occupancy = pixel_count / max(1, rect.w * rect.h)
    rect_cx = rect.x + rect.w * 0.5
    rect_cy = rect.y + rect.h * 0.5
    content_cx = content.x + content.w * 0.5
    content_cy = content.y + content.h * 0.5
    off_x = (content_cx - rect_cx) / max(1, rect.w)
    off_y = (content_cy - rect_cy) / max(1, rect.h)
    if occupancy < 0.04:
        warnings.append("very-low-occupancy")
    if abs(off_x) > 0.18 or abs(off_y) > 0.18:
        warnings.append("large-center-offset")
    return FrameDiagnostic(index, rect, content, round(occupancy, 4), round(off_x, 4), round(off_y, 4), warnings)


def write_sprite_xml(path: Path, image_rel: str, rect: Rect, hot_spot=(0.5, 0.5)) -> None:
    xml = f'''<sprite>
  <texture name="{escape(image_rel)}" />
  <rectangle x="{rect.x}" y="{rect.y}" width="{rect.w}" height="{rect.h}" />
  <hotspot x="{hot_spot[0]}" y="{hot_spot[1]}" />
</sprite>
'''
    path.write_text(xml, encoding="utf-8")


def rel_resource_path(path: Path) -> str:
    parts = path.as_posix().split("/assets/", 1)
    if len(parts) == 2:
        return parts[1]
    return path.as_posix().lstrip("/")


def main() -> None:
    p = argparse.ArgumentParser(description="SpriteFlow spritesheet slicer for UrhoX")
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--action", default="Idle")
    p.add_argument("--layout", choices=["row", "square"], default="row")
    p.add_argument("--cols", type=int, default=4)
    p.add_argument("--rows", type=int, default=1)
    p.add_argument("--frame-count", type=int)
    p.add_argument("--key-color")
    p.add_argument("--tolerance", type=int, default=36)
    p.add_argument("--content-band", action="store_true")
    p.add_argument("--make-xml", action="store_true")
    args = p.parse_args()

    input_path = Path(args.input)
    output_dir = Path(args.output)
    frames_dir = output_dir / "frames"
    output_dir.mkdir(parents=True, exist_ok=True)
    frames_dir.mkdir(parents=True, exist_ok=True)

    img = Image.open(input_path).convert("RGBA")
    key = parse_color(args.key_color)
    if key:
        img = key_background(img, key, args.tolerance)

    sheet_path = output_dir / "sheet.png"
    img.save(sheet_path)

    rows = args.rows
    cols = args.cols
    if args.layout == "square" and args.rows == 1:
        rows = cols
    frame_count = args.frame_count or (rows * cols)
    rects = frame_rects(img, rows, cols, frame_count, args.content_band)

    diagnostics: list[FrameDiagnostic] = []
    xml_paths: list[str] = []
    frame_paths: list[str] = []
    for i, rect in enumerate(rects, start=1):
        frame = img.crop((rect.x, rect.y, rect.x + rect.w, rect.y + rect.h))
        frame_name = f"{args.name}_{args.action}_{i:02d}.png"
        frame_path = frames_dir / frame_name
        frame.save(frame_path)
        frame_paths.append(frame_path.as_posix())
        diagnostics.append(diagnose_frame(img, rect, i))

        if args.make_xml:
            xml_path = output_dir / f"{args.name}_{args.action}_{i:02d}.xml"
            write_sprite_xml(xml_path, rel_resource_path(frame_path), Rect(0, 0, rect.w, rect.h))
            xml_paths.append(xml_path.as_posix())

    summary = {
        "input": input_path.as_posix(),
        "sheet": sheet_path.as_posix(),
        "name": args.name,
        "action": args.action,
        "rows": rows,
        "cols": cols,
        "frameCount": len(rects),
        "frameWidth": rects[0].w if rects else 0,
        "frameHeight": rects[0].h if rects else 0,
        "frames": frame_paths,
        "xml": xml_paths,
        "diagnostics": [asdict(d) for d in diagnostics],
        "warnings": sorted({w for d in diagnostics for w in d.warnings}),
    }
    (output_dir / "diagnostic.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
