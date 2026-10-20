"""生成第 1 关「第十三街地下城」001–005 的字符地图 → scripts/level/d13_maps.gd

用法：python tools/make_d13_maps.py
地图用代码"画"出来（填矩形、放字符），保证每一行等长、坐标不会数错；改关卡就改这里再重新生成。
图例见 scripts/level/region.gd 开头。
"""
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "scripts", "level", "d13_maps.gd")


class Grid:
    def __init__(self, cols, rows):
        self.g = [[" "] * cols for _ in range(rows)]
        self.cols, self.rows = cols, rows

    def fill(self, c0, r0, c1, r1, ch="#"):
        for r in range(r0, r1 + 1):
            for c in range(c0, c1 + 1):
                self.g[r][c] = ch

    def clear(self, c0, r0, c1, r1):
        self.fill(c0, r0, c1, r1, " ")

    def put(self, c, r, ch):
        self.g[r][c] = ch

    def lines(self):
        return ["".join(row) for row in self.g]


def r001():
    g = Grid(150, 24)
    g.fill(0, 0, 1, 23)
    g.fill(2, 19, 147, 23)
    g.clear(31, 19, 36, 23)          # 5 格宽的沟：跳过去
    g.fill(18, 18, 21, 18)           # 1 格台阶
    g.fill(22, 17, 26, 18)           # 2 格台阶
    g.fill(44, 0, 54, 16)            # 低矮通道（净高 2 格 = 32 像素，只能滑铲）
    g.fill(70, 7, 73, 18)            # 12 格高的墙：走上去
    g.fill(100, 15, 103, 18)
    g.fill(118, 13, 120, 18)
    g.fill(148, 0, 149, 23)
    g.put(4, 18, "@")
    g.put(6, 18, "?")
    g.put(28, 18, "?")
    g.put(64, 18, "?")
    g.put(58, 18, "C")
    g.put(80, 18, "C")
    g.put(110, 18, "C")
    g.put(12, 14, "T")
    g.put(90, 13, "T")
    g.put(140, 18, "E")
    return {"name": "D13_R1", "map": g.lines(), "tips": ["T_R1_MOVE", "T_R1_JUMP", "T_R1_WALL"], "texts": ["D13_T1", "D13_T9"]}


def r002():
    g = Grid(175, 26)
    g.fill(0, 0, 1, 25)
    g.fill(2, 19, 60, 25)
    g.fill(97, 19, 172, 25)          # 中间 36 格（576 像素）的深沟
    g.fill(30, 15, 36, 15)           # 小平台
    g.fill(173, 0, 174, 25)
    g.put(4, 18, "@")
    g.put(6, 18, "?")
    g.put(18, 18, "?")
    g.put(53, 18, "?")
    g.put(26, 18, "g")
    g.put(40, 18, "r")
    g.put(46, 18, "s")
    g.put(49, 18, "C")
    g.put(50, 14, "T")
    g.put(57, 18, "R")
    g.put(84, 12, "w")
    g.put(90, 15, "w")
    g.put(99, 18, "C")
    g.put(112, 18, "g")
    g.put(122, 12, "d")
    g.put(134, 18, "b")
    g.put(142, 14, "T")
    g.put(160, 18, "E")
    return {"name": "D13_R2", "map": g.lines(), "tips": ["T_R2_FIGHT", "T_R2_LOCK", "T_R2_RELAY"], "texts": ["D13_T2", "D13_T7"]}


def r003():
    g = Grid(175, 32)
    g.fill(0, 0, 1, 31)
    g.fill(2, 0, 44, 12)             # 上层走廊的天花板（不让从墙顶绕过去）
    g.fill(2, 19, 44, 20)            # 上层地面
    g.fill(2, 21, 29, 26)            # 岩层
    g.fill(45, 0, 79, 20)            # 上层走廊尽头 + 下层隧道的顶
    g.fill(2, 27, 172, 31)           # 下层地面
    g.fill(173, 0, 174, 31)
    g.fill(22, 13, 23, 18, "W")      # 可破墙：堵满走廊
    g.clear(34, 20, 37, 20)
    g.fill(34, 19, 37, 19, "F")      # 薄地板：砸穿掉进下层隧道
    g.put(4, 18, "@")
    g.put(6, 18, "?")
    g.put(26, 18, "?")
    g.put(84, 26, "?")
    g.put(12, 18, "h")
    g.put(28, 18, "C")
    g.put(60, 26, "C")
    g.put(84, 26, "C")
    g.put(100, 22, "T")
    g.put(115, 26, "H")
    g.put(138, 26, "g")
    g.put(160, 26, "E")
    return {"name": "D13_R3", "map": g.lines(), "tips": ["T_R3_WALL", "T_R3_SLAM", "T_R3_ELITE"], "texts": ["D13_T6"], "require_clear": True}


def r004():
    g = Grid(210, 32)
    g.fill(0, 0, 1, 31)
    g.fill(2, 0, 40, 12)
    g.fill(2, 19, 40, 20)
    g.fill(41, 0, 43, 20)
    g.fill(2, 21, 29, 26)
    g.fill(44, 0, 84, 20)
    g.fill(2, 27, 100, 31)
    g.fill(20, 13, 21, 18, "W")
    g.clear(32, 20, 35, 20)
    g.fill(32, 19, 35, 19, "F")
    g.fill(62, 21, 62, 26, "D")      # 安保门
    # 隧道出口：2 格一级的台阶爬上地面
    g.fill(86, 25, 88, 26)
    g.fill(89, 23, 91, 26)
    g.fill(92, 21, 94, 26)
    g.fill(95, 19, 110, 31)
    g.fill(147, 19, 207, 31)         # 111–146：36 格深沟
    g.fill(208, 0, 209, 31)
    g.put(4, 18, "@")
    g.put(6, 18, "?")
    g.put(46, 26, "?")
    g.put(100, 18, "?")
    g.put(12, 18, "h")
    g.put(52, 26, "k")
    g.put(26, 18, "C")
    g.put(66, 26, "C")
    g.put(98, 18, "C")
    g.put(149, 18, "C")
    g.put(30, 16, "T")
    g.put(104, 18, "R")
    g.put(136, 12, "w")
    g.put(150, 14, "T")
    g.put(195, 18, "E")
    return {"name": "D13_R4", "map": g.lines(), "tips": ["T_R4_ROUTE", "T_R4_DOOR", "T_R4_RELAY"], "texts": ["D13_T5", "D13_T4"]}


def r005():
    g = Grid(150, 26)
    g.fill(0, 0, 1, 25)
    g.fill(2, 19, 147, 25)
    g.fill(30, 14, 40, 14)
    g.fill(55, 11, 65, 11)
    g.fill(80, 14, 92, 14)
    g.fill(100, 10, 108, 10)
    g.fill(132, 0, 135, 18)          # 封锁者的大门（锁着）
    g.fill(148, 0, 149, 25)
    g.put(4, 18, "@")
    g.put(6, 18, "?")
    g.put(20, 14, "T")
    g.put(36, 13, "g")
    g.put(48, 18, "r")
    g.put(60, 10, "s")
    g.put(72, 18, "b")
    g.put(78, 10, "d")
    g.put(86, 13, "g")
    g.put(104, 18, "H")
    g.put(110, 9, "d")
    g.put(118, 18, "r")
    g.put(45, 18, "C")
    g.put(95, 18, "C")
    g.put(126, 18, "E")
    g.put(128, 12, "T")
    return {"name": "D13_R5", "map": g.lines(), "tips": ["T_R5_FINAL"], "texts": ["D13_T3", "D13_T8"], "require_clear": True}


def gd_value(v, indent):
    pad = "\t" * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list):
        inner = ",\n".join(pad + "\t" + gd_value(x, indent + 1) for x in v)
        return "[\n" + inner + ",\n" + pad + "]"
    if isinstance(v, dict):
        inner = ",\n".join(pad + "\t" + '"%s": %s' % (k, gd_value(x, indent + 1)) for k, x in v.items())
        return "{\n" + inner + ",\n" + pad + "}"
    raise TypeError(v)


def main():
    regions = [r001(), r002(), r003(), r004(), r005()]
    out = ["class_name D13Maps",
           "## 第 1 关「第十三街地下城」001–005 的字符地图。由 tools/make_d13_maps.py 生成，别手改。",
           "",
           "const REGIONS := " + gd_value(regions, 0),
           ""]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
