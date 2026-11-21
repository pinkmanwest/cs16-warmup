from pathlib import Path
import re
import struct

root = Path(__file__).resolve().parent
wad = (root / "aim_warmup.wad").read_bytes()
magic, count, directory = struct.unpack_from("<4sii", wad)
assert magic == b"WAD3"
textures = {}
for i in range(count):
    start, size, _, kind, _, _, _, name = struct.unpack_from("<iiiBBBB16s", wad, directory + 32 * i)
    assert kind == 0x43
    textures[name.rstrip(b"\0").upper()] = wad[start:start + size]

bsp = (root / "aim_warmup.bsp").read_bytes()
assert struct.unpack_from("<i", bsp)[0] == 30
lumps = []
for i in range(15):
    start, size = struct.unpack_from("<ii", bsp, 4 + i * 8)
    assert 0 <= start <= start + size <= len(bsp)
    lumps.append(bsp[start:start + size])

lumps[0], removed = re.subn(rb'(?m)^"wad" "[^"]*"\r?\n', b"", lumps[0])
assert removed == 1
old = lumps[2]
count = struct.unpack_from("<i", old)[0]
embedded = bytearray(struct.pack("<i", count) + b"\0" * (4 * count))
names = []
for i in range(count):
    offset = struct.unpack_from("<i", old, 4 + 4 * i)[0]
    assert offset >= 0
    key = old[offset:offset + 16].rstrip(b"\0").upper()
    names.append(key)
    struct.pack_into("<i", embedded, 4 + 4 * i, len(embedded))
    if key == b"SKY":
        # The client recognizes the lowercase sky marker and uses skyname.
        embedded += b"sky".ljust(16, b"\0") + textures[key][16:]
    else:
        embedded += textures[key]
    embedded += b"\0" * (-len(embedded) % 4)
lumps[2] = embedded

labels = {b"AW_" + name for name in (
    b"AK47", b"M4A1", b"AWP", b"DEAGLE", b"USP", b"FAMAS", b"STAND", b"RUN", b"USE",
    b"BOT_MINUS", b"BOT_PLUS", b"NEAR", b"MID", b"FAR", b"CREDIT",
    b"STRAFE", b"RANDOM", b"HEAD", b"TEST"
)}
aligned = set()
for *axes, texture, flags in struct.iter_unpack("<8f2i", lumps[6]):
    name = names[texture]
    if name == b"SKY":
        assert flags & 1
    if name in labels and axes[0] < 0 and axes[6] < 0:
        aligned.add(name)
assert b"SKY" in names and aligned == labels

result = bytearray(struct.pack("<i", 30) + b"\0" * 120)
for i, data in enumerate(lumps):
    struct.pack_into("<ii", result, 4 + i * 8, len(result), len(data))
    result += data
    result += b"\0" * (-len(result) % 4)

targets = re.findall(rb'"targetname" "aim_target_(\d+)"', lumps[0])
assert sorted(map(int, targets)) == list(range(1, 32))
assert b'"skyname" "des"' in lumps[0]
assert lumps[0].count(b'"classname" "func_button"') == 17
assert lumps[0].count(b'"classname" "func_illusionary"') == 5
assert lumps[0].count(b'"classname" "info_target"') == 6
assert len(lumps[7]) > 0 and len(lumps[8]) > 0 and len(lumps[10]) > 0
(root / "aim_warmup_embedded.bsp").write_bytes(result)
print(f"BSP v30 validated: {count} embedded textures, {len(targets)} target spawns, {len(lumps[8])} lighting bytes.")
