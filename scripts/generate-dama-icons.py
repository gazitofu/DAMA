#!/usr/bin/env python3
"""Render DAMA's approved SVGs directly at each size; package native macOS assets.

Dependencies: Python 3.9+, CairoSVG 2.8.2, Pillow 11.3.0, macOS iconutil.
No network, image generation, screenshots, or user-library writes.
"""
import hashlib
import io
import json
import ctypes.util
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / ".build/icon-tools"))
# Apple's system Python strips DYLD_* variables. Resolve Homebrew Cairo explicitly
# for this import only; do not alter the machine's loader configuration.
find_library = ctypes.util.find_library
local_cairo = next((p for p in [Path("/opt/homebrew/lib/libcairo.2.dylib"), Path("/usr/local/lib/libcairo.2.dylib")] if p.exists()), None)
if local_cairo:
    ctypes.util.find_library = lambda name: str(local_cairo) if name in ("cairo", "cairo-2", "libcairo-2") else find_library(name)
try:
    import cairosvg
finally:
    ctypes.util.find_library = find_library
from PIL import Image, ImageDraw, ImageFont

ASSETS = ROOT / "assets/dama-icons"
CATALOG = ROOT / "Resources/Assets.xcassets"


def render(name, size, alpha=False, color=None):
    source = (ASSETS / "source" / (name + ".svg")).read_bytes()
    if color is not None:
        source = source.replace(b"#000000", color.encode("ascii"))
    result = Image.open(io.BytesIO(cairosvg.svg2png(bytestring=source, output_width=size, output_height=size))).copy()
    assert result.size == (size, size)
    return result.convert("RGBA" if alpha else "RGB")


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False)


def contents(folder, images=None, **extra):
    folder.mkdir(parents=True, exist_ok=True)
    value = {"info": {"author": "xcode", "version": 1}, **extra}
    if images is not None:
        value["images"] = images
    (folder / "Contents.json").write_text(json.dumps(value, indent=2) + "\n")


def rounded_icon(size):
    # The mask is exclusively for the contact sheet, never packaged in the app.
    icon = render("dama-app", size).convert("RGBA")
    mask = Image.new("L", (size * 4, size * 4))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=size * 0.22 * 4, fill=255)
    icon.putalpha(mask.resize((size, size), Image.Resampling.LANCZOS))
    return icon


def preview():
    canvas = Image.new("RGB", (1000, 820), "#F2F3F7")
    draw = ImageDraw.Draw(canvas)
    font_path = "/System/Library/Fonts/Supplemental/Arial.ttf"
    title = ImageFont.truetype(font_path, 27)
    label = ImageFont.truetype(font_path, 16)
    small = ImageFont.truetype(font_path, 13)
    draw.text((36, 28), "DAMA / 01", fill="#131A40", font=title)
    draw.text((36, 69), "Distinguish Audio Memo Application", fill="#565C70", font=label)
    for size, x, y in [(280, 36, 116), (120, 368, 150), (60, 548, 180)]:
        icon = rounded_icon(size)
        canvas.paste(icon, (x, y), icon)
        draw.text((x, y + size + 12), str(size) + " px / preview mask", fill="#565C70", font=small)
    draw.text((700, 146), "NAVY", fill="#565C70", font=small)
    draw.text((700, 170), "#1C2457 > #131A40", fill="#131A40", font=label)
    draw.text((700, 218), "MINT  #35D7C9", fill="#131A40", font=label)
    draw.text((700, 258), "REC    #F53426", fill="#131A40", font=label)
    for y, background, text_color, idle in [(460, "#FFFFFF", "#262626", "#262626"), (638, "#202127", "#FFFFFF", "#FFFFFF")]:
        draw.rounded_rectangle((28, y, 972, y + 150), radius=12, fill=background)
        draw.text((48, y + 15), "MENU BAR / 22 px actual", fill=text_color, font=label)
        for x, name, state in [(70, "dama-menubar-idle", "Idle"), (190, "dama-menubar-recording", "Recording")]:
            icon = render(name, 22, alpha=True, color=idle if state == "Idle" else None)
            canvas.paste(icon, (x, y + 56), icon)
            draw.text((x, y + 98), state, fill=text_color, font=small)
        draw.text((364, y + 15), "4x pixel inspection", fill=text_color, font=label)
        for x, name in [(390, "dama-menubar-idle"), (550, "dama-menubar-recording")]:
            icon = render(name, 22, alpha=True, color=idle if name.endswith("idle") else None)
            icon = icon.resize((88, 88), Image.Resampling.NEAREST)
            canvas.paste(icon, (x, y + 45), icon)
        draw.text((726, y + 53), "Same canvas & position", fill=text_color, font=small)
        draw.text((726, y + 82), "Recording adds a dot", fill=text_color, font=small)
    save(canvas, ASSETS / "preview/dama-icons-preview.png")


def verify():
    master = Image.open(ASSETS / "app/dama-app-1024.png")
    assert master.mode == "RGB" and master.size == (1024, 1024)
    assert master.getpixel((502, 512)) == (53, 215, 201)
    assert master.getpixel((750, 512)) == (255, 255, 255)
    # Detect missing/reversed gradients instead of accepting a blank dark rectangle.
    assert all(abs(a - b) <= 2 for a, b in zip(master.getpixel((0, 0)), (28, 36, 87)))
    assert all(abs(a - b) <= 2 for a, b in zip(master.getpixel((1023, 1023)), (19, 26, 64)))
    for scale in [1, 2]:
        suffix = "@2x" if scale == 2 else ""
        idle = Image.open(ASSETS / f"menubar/dama-menubar-idle{suffix}.png")
        rec = Image.open(ASSETS / f"menubar/dama-menubar-recording{suffix}.png")
        assert idle.mode == rec.mode == "RGBA" and idle.size == rec.size == (22 * scale, 22 * scale)
        assert idle.getbbox() == rec.getbbox()
        assert idle.getpixel((0, 0))[3] == rec.getpixel((0, 0))[3] == 0
        assert idle.getpixel((11 * scale, 11 * scale))[3] == 0
        assert rec.getpixel((11 * scale, 11 * scale)) == (245, 52, 38, 255)
        # The recording dot does not touch the C-shaped mark at 1x or 2x.
        assert rec.getpixel((7 * scale, 11 * scale))[3] == 0
    files = [p for folder in [ASSETS, CATALOG] for p in folder.rglob("*") if p.is_file() and p.suffix in [".png", ".svg", ".icns"]]
    report = {}
    for path in sorted(files):
        entry = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        if path.suffix == ".png":
            with Image.open(path) as image:
                entry.update(size=list(image.size), mode=image.mode)
        report[str(path.relative_to(ROOT))] = entry
    (ASSETS / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(files)} SVG/PNG/ICNS files; dimensions, alpha, color, gradient, state geometry")


def main():
    contents(CATALOG)
    for size in [1024, 512, 256, 180, 120, 60]:
        save(render("dama-app", size), ASSETS / f"app/dama-app-{size}.png")
    slots = []
    iconset = ASSETS / "app/DAMA.iconset"
    for size in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            filename = f"icon_{size}x{size}" + ("@2x" if scale == 2 else "") + ".png"
            icon = render("dama-app", size * scale)
            save(icon, iconset / filename)
            save(icon, CATALOG / "AppIcon.appiconset" / filename)
            slots.append({"filename": filename, "idiom": "mac", "size": f"{size}x{size}", "scale": f"{scale}x"})
    contents(CATALOG / "AppIcon.appiconset", slots)
    for state in ["idle", "recording"]:
        slots = []
        for scale in [1, 2]:
            name = f"dama-menubar-{state}" + ("@2x" if scale == 2 else "") + ".png"
            icon = render(f"dama-menubar-{state}", 22 * scale, alpha=True)
            save(icon, ASSETS / "menubar" / name)
            save(icon, CATALOG / ("DamaMenu" + state.title() + ".imageset") / name)
            slots.append({"filename": name, "idiom": "mac", "scale": f"{scale}x"})
        contents(CATALOG / ("DamaMenu" + state.title() + ".imageset"), slots,
                 properties={"template-rendering-intent": "template" if state == "idle" else "original"})
    preview()
    verify()
    if "--png-only" not in sys.argv:
        subprocess.run(["/usr/bin/iconutil", "-c", "icns", str(iconset), "-o", str(ASSETS / "app/DAMA.icns")], check=True)
        verify()


if __name__ == "__main__":
    verify() if "--verify" in sys.argv else main()
