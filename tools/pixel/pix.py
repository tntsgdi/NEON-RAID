"""像素美术工具库（只依赖 numpy + 标准库）。

- PALETTE：全项目统一的 32 色调色板（色名 → RGB）。贴图里只能用这些颜色。
- grid()：把文字网格（每个字符 = 一个像素，字符 → 色名映射）变成 RGBA 数组。
- outline()：给不透明区域外加 1px 近黑轮廓（只加在外侧，不吃掉内部像素）。
- rotsprite()：RotSprite 旋转——先用 Scale2x 放大 8 倍、按最近邻旋转、再按 8×8 块取众数缩回，
  旋转后的像素边缘干净，没有半透明混合像素。
- atlas()：把一个部件预生成 N 个角度，横排成一张图集，附带轴心（关节点）在每格里的位置。
- write_png()：用 zlib 写 PNG。
"""
import json
import math
import os
import struct
import zlib

import numpy as np

HEX = {
    # 中性冷灰 8 阶（画面主体）
    "k0": "#05060a", "k1": "#0b0d13", "k2": "#141821", "k3": "#1e232e",
    "k4": "#2b3240", "k5": "#3d4656", "k6": "#5a6478", "k7": "#8a95a8",
    # 玩家青 4 阶
    "c0": "#0e3a44", "c1": "#16707e", "c2": "#2bc4d6", "c3": "#9ef4ff",
    # 敌方红 4 阶
    "r0": "#3a0d14", "r1": "#7a1824", "r2": "#d63446", "r3": "#ff9aa4",
    # 暖黄 3 阶
    "y0": "#5a3d0c", "y1": "#c98a1c", "y2": "#ffd77a",
    # 白
    "w0": "#f2f6fa",
    # 招牌洋红 2 阶
    "m0": "#4a1640", "m1": "#b8348f",
    # 积水 / 夜空蓝 2 阶
    "b0": "#0a1a2a", "b1": "#173550",
    # 补充：雨丝灰蓝、雾
    "g0": "#24344a", "g1": "#4c6a86",
}
PALETTE = {k: tuple(int(v[i:i + 2], 16) for i in (1, 3, 5)) for k, v in HEX.items()}
OUTLINE = "k0"


def rgba(name, a=255):
    r, g, b = PALETTE[name]
    return (r, g, b, a)


def grid(rows, key):
    """rows：字符串列表；key：字符 → 色名（'.' 和 ' ' 是透明）"""
    h = len(rows)
    w = max(len(r) for r in rows)
    img = np.zeros((h, w, 4), np.uint8)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in ". ":
                continue
            if ch not in key:
                raise KeyError("网格里有未定义的字符 %r（第 %d 行）" % (ch, y))
            img[y, x] = rgba(key[ch])
    return img


def pad(img, n):
    h, w = img.shape[:2]
    out = np.zeros((h + 2 * n, w + 2 * n, 4), np.uint8)
    out[n:n + h, n:n + w] = img
    return out


def outline(img, color=OUTLINE):
    """外侧 1px 轮廓（4 邻域），图像先各边扩 1px"""
    img = pad(img, 1)
    a = img[:, :, 3] > 0
    grow = np.zeros_like(a)
    grow[1:, :] |= a[:-1, :]
    grow[:-1, :] |= a[1:, :]
    grow[:, 1:] |= a[:, :-1]
    grow[:, :-1] |= a[:, 1:]
    edge = grow & ~a
    img[edge] = rgba(color)
    return img


def _scale2x(img):
    h, w = img.shape[:2]
    # 用整数键比较像素（RGBA 打包）
    k = (img[:, :, 0].astype(np.uint32) << 24) | (img[:, :, 1].astype(np.uint32) << 16) | (img[:, :, 2].astype(np.uint32) << 8) | img[:, :, 3]
    P = np.pad(k, 1, mode="edge")
    A = P[:-2, 1:-1]
    B = P[1:-1, 2:]
    C = P[1:-1, :-2]
    D = P[2:, 1:-1]
    E = k
    e0 = np.where((C == A) & (C != D) & (A != B), A, E)
    e1 = np.where((A == B) & (A != C) & (B != D), B, E)
    e2 = np.where((D == C) & (D != B) & (C != A), C, E)
    e3 = np.where((B == D) & (B != A) & (D != C), D, E)
    out = np.zeros((h * 2, w * 2), np.uint32)
    out[0::2, 0::2] = e0
    out[0::2, 1::2] = e1
    out[1::2, 0::2] = e2
    out[1::2, 1::2] = e3
    return out


def _unpack(k):
    out = np.zeros(k.shape + (4,), np.uint8)
    out[:, :, 0] = (k >> 24) & 255
    out[:, :, 1] = (k >> 16) & 255
    out[:, :, 2] = (k >> 8) & 255
    out[:, :, 3] = k & 255
    return out


def _pack(img):
    return (img[:, :, 0].astype(np.uint32) << 24) | (img[:, :, 1].astype(np.uint32) << 16) | (img[:, :, 2].astype(np.uint32) << 8) | img[:, :, 3]


def rotsprite(img, angle, pivot, size):
    """把 img 绕 pivot（x, y，像素）旋转 angle 弧度，输出 size×size 的图，轴心在正中间。"""
    big = _unpack(_scale2x(_unpack(_scale2x(_unpack(_scale2x(img))))))  # 8 倍
    bk = _pack(big)
    S = 8
    n = size * S
    cy = cx = n / 2.0
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    dx = xx + 0.5 - cx
    dy = yy + 0.5 - cy
    ca, sa = math.cos(-angle), math.sin(-angle)
    sx = dx * ca - dy * sa + (pivot[0] + 0.5) * S
    sy = dx * sa + dy * ca + (pivot[1] + 0.5) * S
    ix = np.floor(sx).astype(int)
    iy = np.floor(sy).astype(int)
    h, w = bk.shape
    inside = (ix >= 0) & (ix < w) & (iy >= 0) & (iy < h)
    rot = np.zeros((n, n), np.uint32)
    rot[inside] = bk[iy[inside], ix[inside]]
    # 8×8 块取众数（透明优先输给不透明：至少 1/4 不透明才算不透明）
    out = np.zeros((size, size), np.uint32)
    blocks = rot.reshape(size, S, size, S).transpose(0, 2, 1, 3).reshape(size, size, S * S)
    for y in range(size):
        for x in range(size):
            b = blocks[y, x]
            opaque = b[(b & 255) > 0]
            if opaque.size < S * S // 4:
                continue
            vals, counts = np.unique(opaque, return_counts=True)
            out[y, x] = vals[np.argmax(counts)]
    return _unpack(out)


def atlas(img, pivot, n_angles, name, out_dir, lined=True):
    """预生成 n_angles 个角度（按 Godot 的角度方向：顺时针为正）。
    先旋转不带轮廓的原图，再给每一格加 1px 轮廓——轮廓永远是干净的 1px，不会被旋转弄碎。
    写出 <name>.png（横排）和 <name>.json（格子大小、轴心、角度数）。"""
    h, w = img.shape[:2]
    reach = max(math.hypot(pivot[0] - x, pivot[1] - y) for x in (0, w) for y in (0, h))
    size = int(math.ceil(reach * 2 + 2))
    size += size % 2
    cells = []
    for i in range(n_angles):
        a = i * 2 * math.pi / n_angles
        if i == 0:
            cell = np.zeros((size, size, 4), np.uint8)
            ox = size // 2 - pivot[0]
            oy = size // 2 - pivot[1]
            cell[oy:oy + h, ox:ox + w] = img
        else:
            cell = rotsprite(img, a, pivot, size)
        if lined:
            cell = outline(cell)
        cells.append(cell)
    if lined:
        size += 2
    sheet = np.concatenate(cells, axis=1)
    os.makedirs(out_dir, exist_ok=True)
    write_png(os.path.join(out_dir, name + ".png"), sheet)
    with open(os.path.join(out_dir, name + ".json"), "w", encoding="utf-8") as f:
        json.dump({"cell": size, "pivot": [size // 2, size // 2], "angles": n_angles}, f)
    return sheet


def write_png(path, img):
    h, w = img.shape[:2]
    raw = b"".join(b"\x00" + img[y].tobytes() for y in range(h))

    def chunk(t, data):
        c = struct.pack(">I", len(data)) + t + data
        return c + struct.pack(">I", zlib.crc32(t + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def scale_up(img, k):
    return np.repeat(np.repeat(img, k, axis=0), k, axis=1)


def rim(img, color, dirs=((-1, 0), (0, -1))):
    """边缘光：不透明像素里，朝 dirs 方向的邻居是透明的那些（背光一侧的外缘）改成 color。
    面朝右画的部件，默认背面（左）和顶面加光——模拟身后霓虹打过来的轮廓光。"""
    a = img[:, :, 3] > 0
    h, w = a.shape
    out = img.copy()
    for y in range(h):
        for x in range(w):
            if not a[y, x]:
                continue
            for dx, dy in dirs:
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= w or ny >= h or not a[ny, nx]:
                    out[y, x] = rgba(color)
                    break
    return out


def read_png(path):
    """读 8 位 RGBA / RGB PNG（处理全部 5 种行滤波），返回 RGBA 数组"""
    d = open(path, "rb").read()
    i = 8
    w = h = 0
    ct = 6
    idat = b""
    while i < len(d):
        n = struct.unpack(">I", d[i:i + 4])[0]
        t = d[i + 4:i + 8]
        c = d[i + 8:i + 8 + n]
        if t == b"IHDR":
            w, h, _, ct = struct.unpack(">IIBB", c[:10])
        elif t == b"IDAT":
            idat += c
        i += 12 + n
    bpp = 4 if ct == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * bpp
    out = np.zeros((h, stride), np.int32)
    prev = np.zeros(stride, np.int32)
    pos = 0
    for y in range(h):
        f = raw[pos]
        line = np.frombuffer(raw[pos + 1:pos + 1 + stride], np.uint8).astype(np.int32)
        pos += 1 + stride
        cur = np.zeros(stride, np.int32)
        if f == 0:
            cur = line.copy()
        elif f == 2:
            cur = (line + prev) & 255
        else:
            for x in range(stride):
                a = cur[x - bpp] if x >= bpp else 0
                b = prev[x]
                cc = prev[x - bpp] if x >= bpp else 0
                if f == 1:
                    pr = a
                elif f == 3:
                    pr = (a + b) // 2
                else:
                    pp = a + b - cc
                    pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - cc)
                    pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else cc)
                cur[x] = (line[x] + pr) & 255
        out[y] = cur
        prev = cur
    img = out.reshape(h, w, bpp).astype(np.uint8)
    if bpp == 3:
        img = np.concatenate([img, np.full((h, w, 1), 255, np.uint8)], axis=2)
    return img
