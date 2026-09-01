#!/usr/bin/env python3
"""从 assets/icons/app_icon.png 生成带透明通道的 Windows app_icon.ico。

flutter_launcher_icons 的 encodeIco 会丢掉 alpha，圆角外变成黑色。
本脚本嵌入多尺寸 RGBA PNG（Vista+ ICO），保留透明角。
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "icons" / "app_icon.png"
OUT = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
SIZES = (16, 32, 48, 64, 128, 256)


def decode_png(data: bytes) -> tuple[int, int, list[tuple[int, int, int, int]]]:
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    i = 8
    w = h = color = None
    idat = b""
    while i < len(data):
        ln = struct.unpack(">I", data[i : i + 4])[0]
        typ = data[i + 4 : i + 8]
        chunk = data[i + 8 : i + 8 + ln]
        i += 12 + ln
        if typ == b"IHDR":
            w, h, bit, color, *_ = struct.unpack(">IIBBBBB", chunk)
            if bit != 8 or color != 6:
                raise SystemExit(f"需要 8-bit RGBA PNG，当前 bit={bit} color={color}")
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
    assert w is not None and h is not None
    raw = zlib.decompress(idat)
    bpp, stride = 4, w * 4
    rows: list[bytearray] = []
    prev = bytearray(stride)
    o = 0
    for _ in range(h):
        ft = raw[o]
        o += 1
        row = bytearray(raw[o : o + stride])
        o += stride
        if ft == 1:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + left) & 255
        elif ft == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 255
        elif ft == 3:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
        elif ft == 4:

            def paeth(a: int, b: int, c: int) -> int:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    return a
                if pb <= pc:
                    return b
                return c

            for x in range(stride):
                a = row[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + paeth(a, b, c)) & 255
        rows.append(row)
        prev = row
    pixels = [tuple(row[x * 4 : x * 4 + 4]) for row in rows for x in range(w)]
    return w, h, pixels  # type: ignore[return-value]


def encode_png(w: int, h: int, pixels: list[tuple[int, int, int, int]]) -> bytes:
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(pixels[y * w + x])
    compressed = zlib.compress(bytes(raw), 9)

    def chunk(typ: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + typ
            + data
            + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(
        b"IEND", b""
    )


def resize_nn(
    w: int, h: int, pixels: list[tuple[int, int, int, int]], nw: int, nh: int
) -> list[tuple[int, int, int, int]]:
    out: list[tuple[int, int, int, int]] = []
    for y in range(nh):
        sy = y * h // nh
        for x in range(nw):
            sx = x * w // nw
            out.append(pixels[sy * w + sx])
    return out


def build_ico(png_by_size: dict[int, bytes]) -> bytes:
    order = sorted(png_by_size)
    header = struct.pack("<HHH", 0, 1, len(order))
    offset = 6 + 16 * len(order)
    directory = b""
    blobs = b""
    for size in order:
        png = png_by_size[size]
        bw = 0 if size >= 256 else size
        bh = 0 if size >= 256 else size
        directory += struct.pack("<BBBBHHII", bw, bh, 0, 0, 1, 32, len(png), offset)
        blobs += png
        offset += len(png)
    return header + directory + blobs


def main() -> None:
    if not SRC.is_file():
        raise SystemExit(f"找不到源图: {SRC}")
    w, h, pixels = decode_png(SRC.read_bytes())
    if pixels[0][3] != 0:
        print("警告: 源图左上角 alpha 非 0，透明圆角可能不正确")
    png_by_size = {
        size: encode_png(size, size, resize_nn(w, h, pixels, size, size)) for size in SIZES
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(build_ico(png_by_size))
    print(f"已写入 {OUT} ({OUT.stat().st_size} bytes), 尺寸: {', '.join(map(str, SIZES))}")


if __name__ == "__main__":
    main()
