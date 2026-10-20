"""R-0 主角的像素部件 → assets/sprites/r0/*.png + *.json（RotSprite 32 个角度）

每个部件按"面朝右"画，骨头类部件沿 +x 方向从轴心（关节）伸出去。
颜色只用 pix.PALETTE；机身用"形状 + 光照分层 + 手写细节"的方式画，其余部件逐像素手写。
后腿用整体压暗一阶的调色板变体（_b），不靠运行时调色，保证像素颜色都在调色板里。
运行：G:/audio_library/venv/Scripts/python.exe tools/pixel/build_r0.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import pix  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sprites", "r0")
N = 32

KEY = {"7": "k7", "6": "k6", "5": "k5", "4": "k4", "3": "k3", "2": "k2", "1": "k1",
       "c": "c1", "C": "c2", "H": "c3", "W": "w0", "y": "y1", "Y": "y2"}
# 压暗一阶（后腿、远侧部件）
DARKER = {"k7": "k6", "k6": "k5", "k5": "k4", "k4": "k3", "k3": "k2", "k2": "k1", "k1": "k1",
          "c3": "c2", "c2": "c1", "c1": "c0", "c0": "c0", "w0": "k7"}


def remap(img, table):
    out = img.copy()
    for a, b in table.items():
        src = np.array(pix.PALETTE[a], np.uint8)
        m = np.all(img[:, :, :3] == src, axis=2) & (img[:, :, 3] > 0)
        out[m, :3] = pix.PALETTE[b]
    return out


def poly_mask(points, w, h):
    m = np.zeros((h, w), bool)
    for y in range(h):
        yc = y + 0.5
        xs = []
        n = len(points)
        for i in range(n):
            x0, y0 = points[i]
            x1, y1 = points[(i + 1) % n]
            if (y0 <= yc < y1) or (y1 <= yc < y0):
                xs.append(x0 + (yc - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for a, b in zip(xs[0::2], xs[1::2]):
            for x in range(w):
                if a <= x + 0.5 < b:
                    m[y, x] = True
    return m


def shade(mask, ramp):
    """按每一列从上到下的位置分层上色：ramp = [(到这个比例为止, 色名), ...]"""
    h, w = mask.shape
    img = np.zeros((h, w, 4), np.uint8)
    for x in range(w):
        ys = np.where(mask[:, x])[0]
        if ys.size == 0:
            continue
        top, bot = ys.min(), ys.max()
        for y in ys:
            t = (y - top) / max(bot - top, 1)
            for lim, name in ramp:
                if t <= lim:
                    img[y, x] = pix.rgba(name)
                    break
            if y == top:
                img[y, x] = pix.rgba("k7")
            if y == bot:
                img[y, x] = pix.rgba("k3")
    return img


def overlay(img, rows, key=KEY):
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in ". ":
                continue
            if y < img.shape[0] and x < img.shape[1]:
                img[y, x] = pix.rgba(key[ch])
    return img


def save(name, img, pivot, dark=False):
    pix.atlas(img, pivot, N, name, OUT)
    if dark:
        pix.atlas(remap(img, DARKER), pivot, N, name + "_b", OUT)


def hull():
    # 楔形机身：后背高而厚、往前收成低而尖的机鼻（猎鸟的胸骨），髋部在 (11, 14)
    pts = [(0, 6), (3, 1), (13, 0), (21, 3), (28.5, 10), (24, 12.5), (12, 14.5), (2, 12.5)]
    w, h = 29, 15
    m = poly_mask(pts, w, h)
    img = shade(m, [(0.2, "k6"), (0.55, "k5"), (0.85, "k4"), (1.0, "k4")])
    img = overlay(img, [
        ".............................",
        "....7777777..................",
        "...766666667777..............",
        "..76.......6..6677...........",
        "..6........6.....667.........",
        ".3.4.......3.......667.......",
        ".3.4.......3.........667.....",
        ".3.4.......3...........66....",
        "...4.......3....222.....55...",
        "...4.......3....2.2......55..",
        "....4......3....222.....cCC5.",
        "....4.......3333333...ccC5...",
        ".....44................44....",
        "......4444444444444444.......",
        ".............................",
    ])
    save("hull", pix.rim(img, "c1", ((-1, 0), (0, -1))), (11, 14))


def head():
    img = pix.grid([
        "....5555555555...",
        "..46677777777765.",
        ".4566666666666665",
        "45566666662222265",
        "44555555552222254",
        ".3444444444444443",
        "..33333333333333.",
    ], KEY)
    # 后脑的线缆接口
    img = overlay(img, ["", "", ".3.", ".2.", "", "", ""])
    save("head", pix.rim(img, "c1", ((0, -1),)), (6, 4))


def eye():
    img = pix.grid(["7WWWW", "77WW7"], {"7": "k7", "W": "w0"})
    pix.atlas(img, (0, 0), N, "eye", OUT, lined=False)


def neck():
    save("neck", pix.grid(["5665..", "455554", ".344.."], KEY), (0, 1))


def thigh():
    # 大腿：髋部粗（4px）往膝盖收细，背面一道液压杆
    img = pix.grid([
        ".5666666666....",
        "5677777777665..",
        "45555555555544.",
        ".344444443333..",
    ], KEY)
    save("thigh", img, (1, 1), dark=True)


def shin():
    # 小腿：细长（3px），前缘一道青色导光条
    img = pix.grid([
        ".66666666666665",
        "567CCCCCC777654",
        ".34444444443333",
    ], KEY)
    save("shin", img, (1, 1), dark=True)


def meta():
    save("meta", pix.grid(["5666666.", "4555CC54", ".344443."], KEY), (0, 1), dark=True)


def foot():
    # 鸟爪：前两趾、后一趾，轴心在脚尖接地点
    img = pix.grid([
        "....56...",
        "4.5666655",
        "34.4..4.3",
    ], KEY)
    save("foot", img, (4, 1), dark=True)


def joints():
    save("knee", pix.grid([".66.", "6775", "57H5", ".54."], KEY), (2, 2), dark=True)
    save("ankle", pix.grid(["66", "54"], KEY), (1, 1), dark=True)


def arm():
    save("arm", pix.grid(["5666665.", "4555554.", ".34443.."], KEY), (0, 1))
    save("shoulder", pix.grid([".5665.", "567765", "567765", "456654", ".3443."], KEY), (3, 3))


def blade():
    img = pix.grid([
        "..3666666666666666666666655....",
        "34577777777777777777777777766..",
        "345CCCCCCCCCCCCCCCCCCCCCCCHHHWW",
        ".34444444444444444444443333....",
    ], KEY)
    # 护手
    img = overlay(img, ["2", "2", "2", "2"], {"2": "k2"})
    save("blade", img, (2, 2))
    # 刃口发光层（白），运行时按出刀热度调色
    glow = pix.grid([
        "...............................",
        "...............................",
        "...WWWWWWWWWWWWWWWWWWWWWWWWWWWW",
        "...............................",
    ], {"W": "w0"})
    pix.atlas(glow, (2, 2), N, "blade_glow", OUT, lined=False)


def turret():
    save("turret", pix.grid([".45555....", "4567766666", "4555554444", ".3443....."], KEY), (1, 1))


def core():
    img = pix.grid([".WWW.", "W777W", "W7W7W", "W777W", ".WWW."], {"W": "w0", "7": "k7"})
    pix.atlas(img, (2, 2), N, "core", OUT, lined=False)


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in (hull, head, eye, neck, thigh, shin, meta, foot, joints, arm, blade, turret, core):
        f()
    print("R-0 parts ->", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
