#!/usr/bin/env python3
"""Reproducible demo artwork, test fixtures and icon; Pillow + NumPy required.
The three bundled landscapes are procedural illustrations, not photographs.
"""
from pathlib import Path
import json
import math
import numpy as np
from PIL import Image, ImageDraw, ImageCms, TiffImagePlugin

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "Seeply" / "Resources"


def landscape(name, sky_top, sky_bottom, layers, seed):
    w, h = 2400, 1600
    y = np.linspace(0, 1, h)[:, None, None]
    top = np.array(sky_top, dtype=np.float64)[None, None, :]
    bottom = np.array(sky_bottom, dtype=np.float64)[None, None, :]
    color = np.broadcast_to(top * (1 - y) + bottom * y, (h, w, 3)).copy()
    rng = np.random.default_rng(seed)
    color += rng.normal(0, 0.65, (h, w, 1))
    image = Image.fromarray(np.uint8(np.clip(color, 0, 255)))
    draw = ImageDraw.Draw(image)
    for base, amplitude, phase, slope, fill in layers:
        path = []
        for x in range(-10, w + 11, 4):
            normalized = x / w
            height = base + amplitude * math.sin(normalized * math.pi * 1.4 + phase) + slope * (normalized - 0.5)
            path.append((x, int(height * h)))
        draw.polygon(path + [(w + 10, h + 10), (-10, h + 10)], fill=fill)
    arr = np.asarray(image).astype(np.float64)
    arr += rng.normal(0, 0.9, (h, w, 1))
    image = Image.fromarray(np.uint8(np.clip(arr, 0, 255)))
    path = RES / "Samples" / (name + ".jpg")
    path.parent.mkdir(parents=True, exist_ok=True)
    exif = Image.Exif()
    # Original generator provenance is retained across the Seeply rename.
    exif[270] = "Luma demo: procedurally generated landscape illustration. Not a camera photograph."
    exif[305] = "Luma Demo Generator"
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    image.save(path, quality=94, subsampling=0, icc_profile=profile, exif=exif)


def main():
    landscape("Dune", (126, 145, 153), (224, 212, 183), [
        (.48, .08, .2, -.12, (173, 161, 134)),
        (.61, .17, 1.5, .05, (208, 178, 133)),
        (.77, .19, 2.9, -.10, (116, 96, 74)),
        (.93, .13, .4, -.35, (177, 143, 103)),
    ], 11)
    landscape("Coast", (151, 175, 181), (216, 213, 191), [
        (.47, .005, 0, 0, (112, 143, 148)),
        (.62, .018, 2, 0, (132, 161, 160)),
        (.76, .09, 2, -.1, (205, 194, 162)),
        (.90, .13, 3.3, -.15, (83, 98, 97)),
    ], 22)
    landscape("Ridge", (125, 140, 150), (196, 189, 175), [
        (.56, .13, 1.4, -.25, (116, 128, 128)),
        (.68, .18, 3.3, -.12, (77, 95, 96)),
        (.82, .18, .6, .13, (44, 66, 69)),
    ], 33)

    catalog = RES / "Assets.xcassets"
    (catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    accent = catalog / "AccentColor.colorset"
    accent.mkdir(exist_ok=True)
    (accent / "Contents.json").write_text(json.dumps({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "0.84", "green": "0.74", "blue": "0.56", "alpha": "1.0"}}}], "info": {"author": "xcode", "version": 1}}, indent=2))
    size = 2048
    icon = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(icon)
    draw.rounded_rectangle((100, 100, 1948, 1948), radius=425, fill=(28, 30, 34), outline=(60, 62, 66), width=4)
    draw.ellipse((604, 604, 1444, 1444), fill=(41, 42, 43))
    draw.ellipse((777, 777, 1271, 1271), fill=(214, 189, 143))
    for x, y, dx, dy in [(480, 480, 1, 1), (1568, 480, -1, 1), (480, 1568, 1, -1), (1568, 1568, -1, -1)]:
        draw.line([(x, y + dy * 240), (x, y), (x + dx * 240, y)], fill=(227, 224, 213), width=38, joint="curve")
    appicon = catalog / "AppIcon.appiconset"
    appicon.mkdir(exist_ok=True)
    images = []
    for logical in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = logical * scale
            name = f"icon_{logical}x{logical}@{scale}x.png"
            icon.resize((pixels, pixels), Image.Resampling.LANCZOS).save(appicon / name)
            images.append({"idiom": "mac", "size": f"{logical}x{logical}", "scale": f"{scale}x", "filename": name})
    (appicon / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2))

    fixtures = ROOT / "SeeplyTests" / "Fixtures"
    fixtures.mkdir(exist_ok=True)
    fixture = Image.new("RGB", (80, 40), (50, 90, 180))
    ImageDraw.Draw(fixture).rectangle((0, 0, 39, 39), fill=(220, 70, 60))
    exif = Image.Exif()
    rational = TiffImagePlugin.IFDRational
    # Fixture metadata is test data, not the application display name.
    exif[271] = "Luma Test"
    exif[272] = "Fixture Camera"
    exif[274] = 6
    exif[34665] = {33434: rational(1, 250), 33437: rational(14, 10), 34855: 100,
                   36867: "2026:01:02 03:04:05", 36881: "+09:00", 37386: rational(35, 1), 42036: "Fixture 35 mm"}
    exif[34853] = {1: "N", 2: (rational(25), rational(2), rational(0)),
                   3: "E", 4: (rational(121), rational(33), rational(0))}
    fixture.save(fixtures / "orientation6.jpg", quality=95, exif=exif,
                 icc_profile=ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes())
    Image.new("RGB", (32, 24), (100, 120, 140)).save(fixtures / "plain.png")
    (fixtures / "broken.jpg").write_bytes(b"Not a JPEG file; intentionally corrupt test fixture.\n")
    print("Generated 3 demo illustrations, 10 app icons, and 3 ImageIO test fixtures")


if __name__ == "__main__":
    main()
