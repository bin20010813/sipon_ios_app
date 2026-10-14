"""Resize approved dark artwork for iOS/HarmonyOS (requires Pillow).

Run with --check to verify packaged images without changing any files.
Android keeps its existing icon in both system appearances.
"""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / "assets/branding"
IOS_SET = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
IOS_CONTENTS = {
    "images": [
        {
            "filename": "Icon-App-1024x1024@1x.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        },
        {
            "appearances": [{"appearance": "luminosity", "value": "dark"}],
            "filename": "Icon-App-Dark-1024x1024.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        },
    ],
    "info": {"version": 1, "author": "xcode"},
}


def resize_icon(source, size):
    with Image.open(source) as image:
        if image.width != image.height:
            raise ValueError(f"Icon source must be square: {source}")
        if "A" in image.getbands() and image.getchannel("A").getextrema() != (255, 255):
            raise ValueError(f"Flattened icon must be opaque: {source}")
        return image.convert("RGB").resize((size, size), Image.Resampling.LANCZOS)


def outputs():
    dark = BRANDING / "app_icon_dark_a_source.png"
    yield BRANDING / "app_icon_dark.png", dark, 1024
    yield IOS_SET / "Icon-App-Dark-1024x1024.png", dark, 1024
    # App metadata, launcher ability and native launch window reference these names.
    yield ROOT / "ohos/AppScope/resources/dark/media/app_icon.png", dark, 216
    yield ROOT / "ohos/entry/src/main/resources/dark/media/icon.png", dark, 216


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    android_res = ROOT / "android/app/src/main/res"
    if any(android_res.glob("mipmap-night-*/ic_launcher.*")):
        raise ValueError("Remove obsolete Android night launcher icons; Android keeps its original icon")
    count = 0
    for destination, source, size in outputs():
        expected = resize_icon(source, size)
        if args.check:
            with Image.open(destination) as actual:
                if actual.mode != "RGB" or actual.size != expected.size:
                    raise ValueError(f"Incorrect format or size: {destination}")
                if ImageChops.difference(actual, expected).getbbox():
                    raise ValueError(f"Icon does not match approved A artwork: {destination}")
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            expected.save(destination, optimize=True)
        count += 1
    contents = IOS_SET / "Contents.json"
    if args.check:
        if json.loads(contents.read_text(encoding="utf-8")) != IOS_CONTENTS:
            raise ValueError("iOS Any/Dark icon appearances are not configured correctly")
        light = resize_icon(BRANDING / "app_icon_light.png", 1024)
        with Image.open(IOS_SET / IOS_CONTENTS["images"][0]["filename"]) as actual:
            if ImageChops.difference(actual.convert("RGB"), light).getbbox():
                raise ValueError("The existing iOS light icon changed")
    else:
        contents.write_text(json.dumps(IOS_CONTENTS, indent=2) + "\n", encoding="utf-8")
    print(f"{'Verified' if args.check else 'Generated'} {count} dark icon images and iOS Any/Dark appearances.")


if __name__ == "__main__":
    main()
