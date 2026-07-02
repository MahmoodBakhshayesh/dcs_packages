from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "images" / "icons"

DEVICE_TYPES = {
    "bp": "BP",
    "bt": "BT",
    "bc": "BC",
    "be": "BE",
    "oc": "OC",
    "ms": "MS",
    "pr": "PR",
    "bg": "BG",
    "dd": "DD",
    "zl": "ZL",
    "zi": "ZI",
}

STATUSES = {
    "natural": {"bg": "#7fcdae", "badge": "#95a5a6", "label": "IDLE"},
    "active": {"bg": "#7fcdae", "badge": "#2ecc71", "label": "OK"},
    "disconnect": {"bg": "#bfc7cf", "badge": "#e74c3c", "label": "OFF"},
    "in": {"bg": "#f3c36b", "badge": "#f39c12", "label": "INIT"},
    "locked": {"bg": "#7fcdae", "badge": "#34495e", "label": "LOCK"},
    "data_available": {"bg": "#7fcdae", "badge": "#3498db", "label": "DATA"},
    "printing": {"bg": "#7fcdae", "badge": "#9b59b6", "label": "PRINT"},
    "configuring": {"bg": "#f3c36b", "badge": "#8e44ad", "label": "CFG"},
    "inuse": {"bg": "#f3c36b", "badge": "#d35400", "label": "USE"},
    "jammed": {"bg": "#e6a19b", "badge": "#c0392b", "label": "JAM"},
    "open": {"bg": "#e6c27f", "badge": "#e67e22", "label": "OPEN"},
    "paper_out": {"bg": "#e6a19b", "badge": "#e74c3c", "label": "PAPER"},
    "failed": {"bg": "#e6a19b", "badge": "#c0392b", "label": "ERR"},
}

PRINTERS = {"bp", "bt", "pr"}
READERS = {"bc", "bg", "be", "oc", "ms"}
DISPLAYS = {"dd", "zl", "zi"}


def font(size: int):
    for name in ("arial.ttf", "Segoe UI.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def rounded(draw, xy, radius, fill):
    draw.rounded_rectangle(xy, radius=radius, fill=fill)


def text_center(draw, box, text, fill, size):
    f = font(size)
    left, top, right, bottom = box
    bbox = draw.textbbox((0, 0), text, font=f)
    w = bbox[2] - bbox[0]
    h = bbox[3] - bbox[1]
    draw.text((left + (right - left - w) / 2, top + (bottom - top - h) / 2 - 1), text, fill=fill, font=f)


def draw_shadow(draw):
    draw.polygon([(180, 108), (360, 288), (360, 360), (186, 360), (76, 250)], fill=(98, 166, 139, 105))


def draw_badge(draw, status):
    fill = STATUSES[status]["badge"]
    draw.ellipse((258, 34, 326, 102), fill=fill)
    if status == "locked":
        draw.arc((275, 50, 309, 84), 180, 360, fill="white", width=5)
        rounded(draw, (270, 69, 314, 96), 8, "white")
        rounded(draw, (284, 78, 300, 94), 3, fill)
    elif status in {"disconnect", "failed", "jammed"}:
        draw.line((278, 54, 306, 82), fill="white", width=7)
        draw.line((306, 54, 278, 82), fill="white", width=7)
    elif status == "active":
        draw.line((276, 72, 290, 87), fill="white", width=7)
        draw.line((290, 87, 311, 55), fill="white", width=7)
    else:
        text_center(draw, (262, 42, 322, 96), "!", "white", 36)


def draw_printer(draw, device, status):
    rounded(draw, (76, 108, 284, 230), 22, "#687480")
    draw.rectangle((116, 70, 244, 112), fill="#f7f7f7")
    draw.rectangle((108, 194, 252, 292), fill="#f7f7f7")
    draw.polygon([(108, 194), (98, 282), (122, 282)], fill="#49535d")
    draw.polygon([(252, 194), (262, 282), (238, 282)], fill="#49535d")
    draw.ellipse((94, 122, 112, 140), fill="#ffcc80")
    draw.ellipse((122, 122, 140, 140), fill="#ff5f6d")
    for y in (218, 236, 254):
        draw.rectangle((128, y, 232, y + 5), fill="#dedede")
    if status == "paper_out":
        draw.rectangle((126, 210, 234, 226), fill="#f4b4ad")
    if status == "open":
        draw.polygon([(116, 70), (244, 70), (232, 42), (128, 42)], fill="#ffffff")
    if status == "jammed":
        draw.line((124, 208, 236, 286), fill="#c0392b", width=7)
        draw.line((236, 208, 124, 286), fill="#c0392b", width=7)
    text_center(draw, (112, 145, 248, 184), DEVICE_TYPES[device], "#f7f7f7", 32)


def draw_reader(draw, device, status):
    rounded(draw, (76, 100, 284, 246), 22, "#687480")
    rounded(draw, (108, 132, 252, 168), 8, "#3f4850")
    draw.rectangle((118, 190, 242, 210), fill="#d9dee3")
    if status == "data_available":
        draw.polygon([(130, 174), (230, 174), (216, 238), (144, 238)], fill="#f7f7f7")
        for y in (190, 205, 220):
            draw.rectangle((152, y, 208, y + 4), fill="#dcdcdc")
    else:
        draw.arc((132, 176, 228, 272), 205, 335, fill="#ecf0f1", width=10)
    text_center(draw, (106, 56, 254, 96), DEVICE_TYPES[device], "#4b5963", 34)


def draw_display(draw, device, status):
    rounded(draw, (70, 82, 290, 232), 20, "#687480")
    rounded(draw, (92, 104, 268, 202), 8, "#f7f7f7")
    draw.rectangle((155, 232, 205, 266), fill="#4b5963")
    rounded(draw, (118, 266, 242, 284), 8, "#4b5963")
    if status == "active":
        draw.rectangle((118, 130, 242, 148), fill="#2ecc71")
        draw.rectangle((118, 160, 216, 170), fill="#e0e0e0")
    elif status in {"disconnect", "failed"}:
        draw.line((126, 124, 234, 184), fill="#e74c3c", width=8)
        draw.line((234, 124, 126, 184), fill="#e74c3c", width=8)
    else:
        draw.rectangle((118, 130, 242, 140), fill="#dcdcdc")
        draw.rectangle((118, 154, 218, 164), fill="#dcdcdc")
    text_center(draw, (106, 36, 254, 76), DEVICE_TYPES[device], "#4b5963", 34)


def draw_status_label(draw, status):
    label = STATUSES[status]["label"]
    rounded(draw, (90, 304, 270, 336), 16, (255, 255, 255, 205))
    text_center(draw, (90, 304, 270, 336), label, "#4b5963", 18)


def draw_icon(device, status):
    image = Image.new("RGBA", (360, 360), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image, "RGBA")
    bg = STATUSES[status]["bg"]
    draw.ellipse((0, 0, 360, 360), fill=bg)
    draw_shadow(draw)
    if device in PRINTERS:
        draw_printer(draw, device, status)
    elif device in READERS:
        draw_reader(draw, device, status)
    else:
        draw_display(draw, device, status)
    draw_badge(draw, status)
    draw_status_label(draw, status)
    return image


def main():
    for device in DEVICE_TYPES:
        target = OUT / device
        target.mkdir(parents=True, exist_ok=True)
        for status in STATUSES:
            draw_icon(device, status).save(target / f"{device}_{status}.png")

    unknown = Image.new("RGBA", (360, 360), (0, 0, 0, 0))
    draw = ImageDraw.Draw(unknown, "RGBA")
    draw.ellipse((0, 0, 360, 360), fill="#bfc7cf")
    draw_shadow(draw)
    rounded(draw, (86, 86, 274, 274), 36, "#687480")
    text_center(draw, (86, 104, 274, 214), "?", "#ffffff", 96)
    text_center(draw, (90, 224, 270, 260), "UNKNOWN", "#ffffff", 20)
    OUT.mkdir(parents=True, exist_ok=True)
    unknown.save(OUT / "unknown.png")


if __name__ == "__main__":
    main()
