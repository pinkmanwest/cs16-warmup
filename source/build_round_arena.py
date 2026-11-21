from itertools import zip_longest
from math import cos, radians, sin
from pathlib import Path
import random
import struct

ROOT = Path(__file__).resolve().parent
NAME = "aim_warmup"
SIDES = 24
PALETTE = (
    (22, 29, 36), (31, 40, 49), (43, 54, 63), (49, 63, 73),
    (63, 79, 91), (75, 93, 105), (105, 124, 134), (128, 149, 153),
    (24, 65, 66), (32, 106, 104), (47, 180, 163), (160, 248, 222),
    (105, 67, 33), (153, 96, 40), (222, 150, 48), (249, 195, 83),
    (240, 249, 250),
    (80, 195, 205), (232, 187, 81), (232, 112, 88), (112, 158, 220),
)
GLYPHS = {
    "A": (14, 17, 17, 31, 17, 17, 17), "B": (30, 17, 17, 30, 17, 17, 30),
    "D": (30, 17, 17, 17, 17, 17, 30),
    "E": (31, 16, 16, 30, 16, 16, 31), "F": (31, 16, 16, 30, 16, 16, 16),
    "G": (14, 17, 16, 23, 17, 17, 14), "H": (17, 17, 17, 31, 17, 17, 17),
    "I": (14, 4, 4, 4, 4, 4, 14),
    "K": (17, 18, 20, 24, 20, 18, 17), "L": (16, 16, 16, 16, 16, 16, 31),
    "M": (17, 27, 21, 21, 17, 17, 17), "N": (17, 25, 21, 19, 17, 17, 17),
    "O": (14, 17, 17, 17, 17, 17, 14), "P": (30, 17, 17, 30, 16, 16, 16),
    "R": (30, 17, 17, 30, 20, 18, 17),
    "S": (15, 16, 16, 14, 1, 1, 30), "T": (31, 4, 4, 4, 4, 4, 4),
    "U": (17, 17, 17, 17, 17, 17, 14), "W": (17, 17, 17, 21, 21, 27, 17),
    "Y": (17, 17, 10, 4, 4, 4, 4),
    "0": (14, 17, 19, 21, 25, 17, 14), "1": (4, 12, 4, 4, 4, 4, 14),
    "4": (2, 6, 10, 18, 31, 2, 2), "6": (6, 8, 16, 30, 17, 17, 14),
    "7": (31, 1, 2, 4, 8, 8, 8), "-": (0, 0, 0, 31, 0, 0, 0),
    "+": (0, 4, 4, 31, 4, 4, 0),
    " ": (0, 0, 0, 0, 0, 0, 0),
    "a": (0, 0, 14, 1, 15, 17, 15), "b": (16, 16, 30, 17, 17, 17, 30),
    "c": (0, 0, 14, 16, 16, 16, 14), "e": (0, 0, 14, 17, 31, 16, 14),
    "g": (0, 0, 15, 17, 15, 1, 14), "h": (16, 16, 30, 17, 17, 17, 17),
    "i": (4, 0, 12, 4, 4, 4, 14), "k": (16, 16, 18, 20, 24, 20, 18),
    "m": (0, 0, 26, 21, 21, 21, 21), "n": (0, 0, 30, 17, 17, 17, 17),
    "o": (0, 0, 14, 17, 17, 17, 14), "p": (0, 0, 30, 17, 30, 16, 16),
    "s": (0, 0, 15, 16, 14, 1, 30), "t": (4, 4, 31, 4, 4, 4, 3),
    "u": (0, 0, 17, 17, 17, 19, 13), "w": (0, 0, 17, 17, 21, 21, 10),
    ".": (0, 0, 0, 0, 0, 0, 4), "/": (1, 1, 2, 4, 8, 16, 16),
}
WEAPONS = (
    ("AK47", "AK-47"), ("M4A1", "M4A1"), ("AWP", "AWP"),
    ("DEAGLE", "EAGLE"), ("USP", "USP"), ("FAMAS", "FAMAS"),
)
CONTROLS = (
    ("BOT_MINUS", "BOT -", 20, 139, 46), ("STAND", "STAND", 14, 49, 46),
    ("RUN", "RUN", 14, -41, 46), ("STRAFE", "STRAFE", 14, -131, 46),
    ("BOT_PLUS", "BOT +", 20, -221, 46),
    ("NEAR", "NEAR", 17, 184, 7), ("MID", "MID", 18, 94, 7),
    ("FAR", "FAR", 19, 4, 7), ("RANDOM", "RANDOM", 10, -86, 7),
    ("HEAD", "HS ONLY", 10, -176, 7), ("TEST", "60S TEST", 10, -266, 7),
)
INDICATORS = {"NEAR", "MID", "FAR", "RANDOM", "HEAD"}
DISTANCES = (
    (232, (18, 48, 78, 138, 198, 258, 318), "AW_NEAR"),
    (520, (0, 35, 64, 84, 107, 151, 191, 223, 263, 300, 343), "AW_MID"),
    (856, (8, 47, 94, 124, 166, 181, 212, 234, 274, 286, 312, 327, 354), "AW_FAR"),
)
rng = random.Random(16)


def label(text, border, width=64, height=64, *, bottom=False):
    scale = 2
    left = (width - (len(text) * 6 - 1) * scale) // 2
    top = height - 20 if bottom else (height - 7 * scale) // 2

    def pattern(x, y):
        if min(x, y, width - 1 - x, height - 1 - y) < 2:
            return border
        col, row = (x - left) // scale, (y - top) // scale
        index, pixel = divmod(col, 6)
        if 0 <= index < len(text) and 0 <= row < 7 and pixel < 5:
            if GLYPHS[text[index]][row] & (16 >> pixel):
                return 16
        return 2 if bottom and y < top - 3 else 1

    return pattern


def surface(name, pattern, width, height):
    pixels = bytearray()
    offsets = []
    for step in (1, 2, 4, 8):
        offsets.append(40 + len(pixels))
        for y in range(0, height, step):
            for x in range(0, width, step):
                pixels.append(pattern(x, y))
    header = struct.pack("<16s6I", name.encode(), width, height, *offsets)
    palette = bytes(channel for rgb in PALETTE for channel in rgb)
    return header + pixels + struct.pack("<H", 256) + palette.ljust(768, b"\0")


textures = {
    "AW_FLOOR": lambda x, y: 2 if x < 2 or y < 2 else rng.choice((3, 4, 4, 4, 5)),
    "AW_WALL": lambda x, y: 1 if y < 3 else 8 if 24 < y < 30 else rng.choice((4, 5, 5, 5, 6)),
    "AW_PANEL": lambda x, y: 8 if min(x, y, 63 - x, 63 - y) < 2 else 1,
    "AW_NEAR": lambda x, y: 17 if (x + y) % 32 < 14 else 8,
    "AW_MID": lambda x, y: 18 if (x + y) % 32 < 14 else 12,
    "AW_FAR": lambda x, y: 19 if (x + y) % 32 < 14 else 12,
    "AW_START": lambda x, y: 20 if min(x, y, 63 - x, 63 - y) < 3 else 3,
    "AW_LED": lambda x, y: 11,
    "SKY": lambda x, y: 20,
}
label_sizes = {}


def add_label(name, text, border, width=64, height=32, *, bottom=False):
    label_sizes[name] = (width, height)
    textures[name] = label(text, border, width, height, bottom=bottom)


add_label("AW_USE", "SHOOT", 10)
add_label("AW_CREDIT", "github.com/pinkmanwest", 10, 288, 32)
for name, text in WEAPONS:
    add_label(f"AW_{name}", text, 10, height=64, bottom=True)
for name, text, border, _, _ in CONTROLS:
    add_label(f"AW_{name}", text, border, 96 if len(text) > 5 else 64)

wad_body = bytearray()
directory = bytearray()
for name, pattern in textures.items():
    data = surface(name, pattern, *label_sizes.get(name, (16, 16) if name == "SKY" else (64, 64)))
    directory += struct.pack("<iiiBBBB16s", 12 + len(wad_body), len(data), len(data), 0x43, 0, 0, 0, name.encode())
    wad_body += data
(ROOT / f"{NAME}.wad").write_bytes(struct.pack("<4sii", b"WAD3", len(textures), 12 + len(wad_body)) + wad_body + directory)


def entity(classname, *, brushes=(), **fields):
    pairs = {"classname": classname, **fields}
    keys = "".join(f'"{key}" "{value}"\n' for key, value in pairs.items())
    return "{\n" + keys + "".join(brushes) + "}\n"


def prism(points, z0, z1, texture, overrides=None):
    bottom = [(x, y, z0) for x, y in points]
    top = [(x, y, z1) for x, y in points]
    faces = [tuple(bottom[:3]), (top[0], top[2], top[1])]
    for i in range(len(points)):
        faces.append((bottom[i], top[i], top[(i + 1) % len(points)]))
    lines = []
    for index, face in enumerate(faces):
        material = (overrides or {}).get(index, f"{texture} 0 0 0 1 1")
        lines.append(" ".join(f"( {x} {y} {z} )" for x, y, z in face) + f" {material}\n")
    return "{\n" + "".join(lines) + "}\n"


def box(x0, y0, z0, x1, y1, z1, texture, front=None):
    overrides = {4: front} if front else None
    return prism(((x0, y0), (x1, y0), (x1, y1), (x0, y1)), z0, z1, texture, overrides)


def panel(name, x, z, width, height):
    tex_width, tex_height = label_sizes[name]
    x_scale, y_scale = width / tex_width, height / tex_height
    face = f"{name} {(x + width) / x_scale:.6f} {(z + height) / y_scale:.6f} 0 {-x_scale:.6f} {y_scale:.6f}"
    return box(x, -976, z, x + width, -970, z + height, "AW_PANEL", face)


def polar(radius, angle):
    return round(radius * cos(radians(angle))), round(radius * sin(radians(angle)))


def ring(inner, outer, z0, z1, sides, texture):
    inside = [polar(inner, i * 360 / sides) for i in range(sides)]
    outside = [polar(outer, i * 360 / sides) for i in range(sides)]
    for i in range(sides):
        next_side = (i + 1) % sides
        points = (inside[i], outside[i], outside[next_side], inside[next_side])
        yield prism(points, z0, z1, texture)


world = [
    box(-1184, -1184, -64, 1184, 1184, 0, "AW_FLOOR"),
    box(-1184, -1184, 576, 1184, 1184, 608, "SKY"),
    *ring(1088, 1120, 0, 152, SIDES, "AW_WALL"),
    *ring(1088, 1120, 152, 576, SIDES, "SKY"),
    box(-64, -64, 0, 64, 64, 1, "AW_START"),
    box(-292, -1016, 0, 292, -976, 244, "AW_PANEL"),
    panel("AW_USE", -63, 166, 126, 29),
    panel("AW_CREDIT", -228, 203, 456, 35),
]
for radius, _, texture in DISTANCES:
    world.extend(ring(radius - 7, radius + 7, 0, 1, SIDES, texture))

contents = entity("worldspawn", brushes=world, message="Aim Warmup - Open Range", wad=f"{NAME}.wad", skyname="des")
for x, y in ((0, 0), (-72, -24), (72, -24), (0, 80)):
    contents += entity("info_player_start", origin=f"{x} {y} 40", angle="270")

slot = 0
for angles in zip_longest(*(angles for _, angles, _ in DISTANCES)):
    for index, (angle, (radius, _, _)) in enumerate(zip(angles, DISTANCES, strict=True), start=1):
        if angle is None:
            continue
        slot += 1
        x, y = polar(radius, angle)
        contents += entity(
            "info_player_deathmatch", origin=f"{x} {y} 40", angle=str((angle + 180) % 360),
            targetname=f"aim_target_{slot}", netname=str(index),
        )
for x in (-720, -660, 660, 720):
    contents += entity("info_player_deathmatch", origin=f"{x} 0 40", angle="180" if x > 0 else "0")

def button(name, x, z, height):
    brush = panel(f"AW_{name}", x, z, 82, height)
    return entity("func_button", brushes=(brush,), targetname=f"aim_{name.lower()}", spawnflags="1", health="100", wait="0.2", sounds="0")


for index, ((name, _), x) in enumerate(zip(WEAPONS, range(184, -267, -90), strict=True), start=1):
    contents += button(name, x, 85, 74)
    angles = "90 90 0" if name == "FAMAS" else "0 0 -90"
    contents += entity("info_target", origin=f"{x + 41} -967 133",
                       targetname=f"aim_display_{index}", angles=angles)
for name, _, _, x, z in CONTROLS:
    contents += button(name, x, z, 33)
    if name in INDICATORS:
        indicator = box(x + 9, -970, z + 28, x + 73, -968, z + 31, "AW_LED")
        contents += entity("func_illusionary", brushes=(indicator,), targetname=f"aim_led_{name.lower()}")
contents += entity("light_environment", origin="0 0 448", angle="225", pitch="-50", _light="255 244 229 360")
for x, y in ((-520, 0), (520, 0), (0, 520), (0, -520)):
    contents += entity("light", origin=f"{x} {y} 196", _light="222 237 255 155")
contents += entity("light", origin="0 -892 160", _light="235 249 255 220")
(ROOT / f"{NAME}.map").write_text(contents, encoding="ascii")
