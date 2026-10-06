"""Generate the Debate Cloud app icon and deploy it to every platform.

Design: two overlapping speech bubbles (a nod to the in-app forum mark) on
the brand teal gradient, drawn with Pillow at 4x supersampling for clean
anti-aliasing. All geometry lives in a 1024x1024 design space.

Usage:
    python design/icon/generate_icon.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

# ── 品牌色,镜像 lib/app/app_design.dart 的 AppPalette ─────────────────
TEAL_200 = (0x8F, 0xD3, 0xC7)
TEAL_500 = (0x0F, 0x76, 0x6E)
TEAL_700 = (0x09, 0x4A, 0x45)
TEAL_900 = (0x04, 0x29, 0x25)
WHITE = (0xFF, 0xFF, 0xFF)

BASE = 1024            # 设计空间边长
SS = 4                 # 超采样倍数
CANVAS = BASE * SS     # 实际绘制画布 4096
CORNER_RADIUS = 0.225  # 圆角变体的圆角占比(贴近 macOS 风格)

# ── 图形几何(1024 设计空间坐标)─────────────────────────────────────
# 前景白色大气泡:圆角矩形 + 指向左下的尾巴 + 三个青色圆点
FRONT_RECT = (190, 455, 600, 735)
FRONT_RADIUS = 64
FRONT_TAIL = dict(base=(295, 700), direction=(-0.487, 0.873),
                  half_width=44, length=150, bow_out=0.55, bow_in=-0.15)
DOTS = [(310, 595), (395, 595), (480, 595)]
DOT_RADIUS = 26

# 背景浅青小气泡:圆角矩形 + 指向右上的尾巴
BACK_RECT = (520, 275, 820, 495)
BACK_RADIUS = 56
BACK_TAIL = dict(base=(742, 330), direction=(0.46, -0.89),
                 half_width=40, length=158, bow_out=0.55, bow_in=-0.15)

GAP = 18  # 两气泡之间的镂空间距(由背景色透出)

ROOT = Path(__file__).resolve().parents[2]


# ── 基础绘制 ──────────────────────────────────────────────────────────
def transform(point, scale=1.0):
    """设计空间坐标 → 画布坐标(绕画布中心缩放后 × 超采样)。"""
    cx, cy = BASE / 2, BASE / 2
    x = cx + (point[0] - cx) * scale
    y = cy + (point[1] - cy) * scale
    return (x * SS, y * SS)


def _quad_points(p0, p1, p2, n=28):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1])
            for t in (i / n for i in range(n + 1))]


def tail_polygon(base, direction, half_width, length, bow_out, bow_in,
                 expand=0.0):
    """气泡尾巴:外缘(b→tip)微凸、内缘(tip→a)微凹,收成尖角。

    expand 用于把尾巴向外扩出镂空间距。
    """
    bx, by = base
    ux, uy = direction
    px, py = -uy, ux  # 垂直方向
    hw = half_width + expand
    ln = length + expand
    tip = (bx + ux * ln, by + uy * ln)
    a = (bx - px * hw, by - py * hw)   # 内侧 attach 点
    b = (bx + px * hw, by + py * hw)   # 外侧 attach 点
    ctrl_out = (bx + ux * ln * 0.52 + px * hw * bow_out,
                by + uy * ln * 0.52 + py * hw * bow_out)
    ctrl_in = (bx + ux * ln * 0.60 + px * hw * bow_in,
               by + uy * ln * 0.60 + py * hw * bow_in)
    return _quad_points(b, ctrl_out, tip) + _quad_points(tip, ctrl_in, a)[1:]


def bubble_mask(rect, radius, tail, scale=1.0, expand=0.0):
    """单个气泡(圆角矩形 ∪ 尾巴)的 alpha 蒙版。"""
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    d = ImageDraw.Draw(mask)
    x0, y0, x1, y1 = rect
    cx = cy = BASE / 2
    # 与 transform() 一致:绕画布中心缩放后再 × 超采样
    box = tuple((c + (v - c) * scale) * SS
                for v, c in zip((x0 - expand, y0 - expand,
                                 x1 + expand, y1 + expand), (cx, cy, cx, cy)))
    d.rounded_rectangle(box, radius=(radius + expand) * scale * SS, fill=255)
    pts = tail_polygon(**tail, expand=expand)
    d.polygon([transform(p, scale) for p in pts], fill=255)
    return mask


def glyph_layer(scale=1.0):
    """双气泡 + 圆点,画在透明层上;气泡间留出镂空。"""
    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    back = bubble_mask(BACK_RECT, BACK_RADIUS, BACK_TAIL, scale)
    punch = bubble_mask(FRONT_RECT, FRONT_RADIUS, FRONT_TAIL, scale, expand=GAP)
    back_alpha = ImageChops.subtract(back, punch)
    back_color = Image.new("RGBA", (CANVAS, CANVAS), TEAL_200 + (255,))
    back_color.putalpha(back_alpha)
    layer.alpha_composite(back_color)

    front = bubble_mask(FRONT_RECT, FRONT_RADIUS, FRONT_TAIL, scale)
    front_color = Image.new("RGBA", (CANVAS, CANVAS), WHITE + (255,))
    front_color.putalpha(front)
    layer.alpha_composite(front_color)

    dots = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    for (x, y) in DOTS:
        cx, cy = transform((x, y), scale)
        r = DOT_RADIUS * scale * SS
        dd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=TEAL_500 + (255,))
    layer.alpha_composite(dots)
    return layer


def background(rounded=False):
    """品牌青绿渐变底 + 左上高光 + 底部压暗;rounded=True 时切圆角。"""
    grad = Image.new("RGB", (1, CANVAS))
    for y in range(CANVAS):
        t = y / (CANVAS - 1)
        grad.putpixel((0, y), tuple(int(a + (b - a) * t)
                                    for a, b in zip(TEAL_500, TEAL_700)))
    bg = grad.resize((CANVAS, CANVAS)).convert("RGBA")

    def radial(color, center, radius, max_alpha):
        # 画布预填 255:重映射后 255 → alpha 0,保证粘贴区之外不受影响
        m = Image.new("L", (CANVAS, CANVAS), 255)
        g = Image.radial_gradient("L").resize((radius * 2, radius * 2))
        # 径向渐变源在内切圆边缘处并未到 255,直接线性映射会在粘贴
        # 边界留下 alpha 突变的接缝;以圆边缘处的实际值为基准重映射,
        # 让 alpha 恰好在半径处衰减到 0。
        v_edge = g.getpixel((radius, 0))
        m.paste(g, (center[0] - radius, center[1] - radius))
        overlay = Image.new("RGBA", (CANVAS, CANVAS), color + (255,))
        overlay.putalpha(m.point(
            lambda v: max(0, int((v_edge - v) * max_alpha * 255 / v_edge))))
        return overlay

    bg.alpha_composite(radial(WHITE, (int(0.30 * CANVAS), int(0.24 * CANVAS)),
                              int(0.85 * CANVAS), 0.10))
    bg.alpha_composite(radial(TEAL_900, (int(0.55 * CANVAS), int(1.10 * CANVAS)),
                              int(0.95 * CANVAS), 0.30))

    if rounded:
        m = Image.new("L", (CANVAS, CANVAS), 0)
        ImageDraw.Draw(m).rounded_rectangle(
            (0, 0, CANVAS - 1, CANVAS - 1),
            radius=CORNER_RADIUS * CANVAS, fill=255)
        bg.putalpha(m)
    return bg


def compose(rounded=False, glyph_scale=1.0, transparent_bg=False):
    img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0)) if transparent_bg \
        else background(rounded)
    img.alpha_composite(glyph_layer(glyph_scale))
    return img


# ── 输出 ─────────────────────────────────────────────────────────────
written = []


def save(img, size, path, rgb=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    out = img.resize((size, size), Image.LANCZOS)
    if rgb:
        out = out.convert("RGB")
    out.save(path)
    written.append((path, size))


def main():
    full = compose(rounded=False)                      # iOS / Android 传统 / maskable
    rounded = compose(rounded=True)                    # Windows / macOS / Web
    maskable = compose(rounded=False, glyph_scale=0.72)  # PWA maskable 安全区
    foreground = compose(glyph_scale=0.62, transparent_bg=True)  # Android 自适应前景

    icon_dir = ROOT / "design" / "icon"
    save(full, BASE, icon_dir / "icon_master_full.png")
    save(rounded, BASE, icon_dir / "icon_master_rounded.png")
    save(maskable, BASE, icon_dir / "icon_master_maskable.png")
    save(foreground, BASE, icon_dir / "icon_master_foreground.png")

    # Windows .ico(多尺寸嵌入)
    ico_path = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    ico_path.parent.mkdir(parents=True, exist_ok=True)
    rounded.resize((256, 256), Image.LANCZOS).save(
        ico_path, format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
               (64, 64), (128, 128), (256, 256)],
        bitmap_format="png")
    written.append((ico_path, "16-256"))

    # Android 传统图标 + 自适应图标前景
    android_res = ROOT / "android" / "app" / "src" / "main" / "res"
    for dpi, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                      ("xxhdpi", 144), ("xxxhdpi", 192)]:
        save(full, size, android_res / f"mipmap-{dpi}" / "ic_launcher.png")
        # 自适应图标画布为 108dp(传统图标 48dp 基准 × 2.25)
        save(foreground, int(size * 2.25),
             android_res / f"mipmap-{dpi}" / "ic_launcher_foreground.png")

    (android_res / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
    (android_res / "mipmap-anydpi-v26" / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n', encoding="utf-8")
    written.append((android_res / "mipmap-anydpi-v26" / "ic_launcher.xml", "-"))

    (android_res / "drawable").mkdir(parents=True, exist_ok=True)
    (android_res / "drawable" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <gradient android:angle="270"\n'
        '        android:startColor="#0F766E"\n'
        '        android:endColor="#094A45"/>\n'
        '</shape>\n', encoding="utf-8")
    written.append((android_res / "drawable" / "ic_launcher_background.xml", "-"))

    # iOS(全出血方角;App Store 1024 需无 alpha → RGB)
    ios_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    ios_sizes = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60, "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120, "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180, "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152, "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, size in ios_sizes.items():
        save(full, size, ios_dir / name, rgb=True)

    # macOS(圆角)
    mac_dir = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for name, size in [("app_icon_16.png", 16), ("app_icon_32.png", 32),
                       ("app_icon_64.png", 64), ("app_icon_128.png", 128),
                       ("app_icon_256.png", 256), ("app_icon_512.png", 512),
                       ("app_icon_1024.png", 1024)]:
        save(rounded, size, mac_dir / name)

    # Web
    web_dir = ROOT / "web"
    save(rounded, 32, web_dir / "favicon.png")
    save(rounded, 192, web_dir / "icons" / "Icon-192.png")
    save(rounded, 512, web_dir / "icons" / "Icon-512.png")
    save(maskable, 192, web_dir / "icons" / "Icon-maskable-192.png")
    save(maskable, 512, web_dir / "icons" / "Icon-maskable-512.png")

    # 预览图:亮/暗两种底色上排列常用尺寸,便于人工检查小尺寸辨识度
    sizes = [256, 128, 96, 64, 48, 32, 16]
    preview = Image.new("RGB", (1160, 380), (0, 0, 0))
    light = Image.new("RGB", (1160, 190), (0xF3, 0xF4, 0xF6))
    dark = Image.new("RGB", (1160, 190), (0x04, 0x29, 0x25))
    preview.paste(light, (0, 0))
    preview.paste(dark, (0, 190))
    x = 24
    for size in sizes:
        for y in [(190 - size) // 2, 190 + (190 - size) // 2]:
            im = rounded.resize((size, size), Image.LANCZOS)
            preview.paste(im, (x, y), im)
        x += size + 40
    preview.save(icon_dir / "preview.png")
    written.append((icon_dir / "preview.png", "montage"))

    print(f"共写入 {len(written)} 个文件:")
    for path, size in written:
        print(f"  {path.relative_to(ROOT)}  [{size}]")


if __name__ == "__main__":
    main()
