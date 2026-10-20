"""从本地 Sonniss GDC 音效库切出游戏音效，写到 assets/sfx/。

Sonniss GDC Game Audio Bundle：免版税、可商用、无需署名。
用法：G:/audio_library/venv/Scripts/python.exe tools/build_sfx.py
每个音效由若干层组成：(文件名片段, 起点秒, 时长秒或 None, 增益 dB)。
各层对齐起音后混合，裁掉开头静音，加淡出，峰值归一化到 -1 dBFS。
"""
import glob
import os
import sys

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

LIB = "G:/audio_library/sonniss/files"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
RATE = 44100

SFX = {
    # 挥刀：三段连击各用一个变体，重击叠一层更低的破空
    "swing_1": [("Fast Action Swish_HW 05", 0.60, 0.29, 0)],
    "swing_2": [("Fast Action Swish_HW 05", 1.58, 0.26, 0)],
    "swing_3": [("Fast Action Swish_HW 05", 2.05, 0.25, 0)],
    "swing_heavy": [("Action Swish_HW 02", 1.07, 0.29, 0), ("Fast Action Swish_HW 05", 0.11, 0.35, -4)],
    # 命中机器人：功夫片式的拳脚打击 + 金属敲击
    "hit_1": [("Seq 2.27 Hit #1 96 HK1", 0.10, 0.23, 0), ("METLImpt_Metal Old File Impact Tap", 0.12, 0.30, -8)],
    "hit_2": [("Seq 2.1 Hit #1 96 HK1", 0.07, 0.26, 0), ("METLImpt_Metal Old File Impact Tap", 0.12, 0.30, -8)],
    "hit_heavy": [("Hit Impact Hard Metal Scrap Debris_UC 01", 0.21, 0.47, 0), ("Seq 2.1 Hit #3 96 HK1", 0.08, 0.29, -3)],
    "break": [("demolisher_metal_impact_002", 0.0, 1.0, 0), ("glass_impact_break_small_014", 0.0, 0.5, -10)],
    # 移动：只留短促、低调的声音，不再有持续的沙沙声和噔噔的脚步
    "dash": [("WHSH_InsJ_Whooshing_Low_Double_01-01", 0.04, 0.19, 0)],
    "walljump": [("Whoosh_Cloth_Leather_Fight_174", 0.0, 0.30, 0)],
    "land": [("IMPACT_LOW_THUD_10", 0.0, 0.20, 0)],
    "slide": [("EFX SD Sliding Whoosh By 06", 0.0, 0.45, 0)],
    # M2 战斗
    "shot": [("SCIWeap_Shot Pulse YR 05", 0.0, 0.45, 0)],
    "enemy_shot": [("Blast Laser 4", 0.0, 0.5, 0)],
    "deflect": [("Machete_Hit_Ring_Fienup_001", 0.0, 0.7, 0)],
    "overclock": [("pang_short_R_to_L_003", 0.0, 0.8, 0)],
    "hurt": [("PUNCH_PERCUSSIVE_HEAVY_06", 0.0, 0.4, 0), ("Broken_Robot_Morphing_Short_Static_Pitch_Confused_Glitch_02", 0.0, 0.4, -6)],
    "charge": [("electricity_surge_discharge_electrical_arc_crackling_002_01", 0.0, 0.5, -2)],
    "shield_block": [("cinematic_metal_impact_050", 0.0, 0.4, 0)],
}


def find(part):
    hits = [p for p in glob.glob(LIB + "/**/*.wav", recursive=True) if part in os.path.basename(p)]
    if not hits:
        sys.exit("找不到音源：" + part)
    return sorted(hits, key=len)[0]


def load(part, start, dur):
    path = find(part)
    info = sf.info(path)
    a = int(start * info.samplerate)
    b = info.frames if dur is None else min(info.frames, a + int(dur * info.samplerate))
    x, sr = sf.read(path, start=a, stop=b, always_2d=True, dtype="float32")
    x = x.mean(axis=1)
    if sr != RATE:
        g = np.gcd(sr, RATE)
        x = resample_poly(x, RATE // g, sr // g).astype(np.float32)
    # 从起音开始（-40 dB 以上的第一个采样往前 2 ms）
    thr = np.abs(x).max() * 0.01
    on = int(np.argmax(np.abs(x) > thr))
    return x[max(0, on - int(0.002 * RATE)):]


def build(layers):
    parts = [load(f, s, d) / max(1e-6, np.abs(load(f, s, d)).max()) * 10 ** (g / 20) for f, s, d, g in layers]
    n = max(len(p) for p in parts)
    mix = np.zeros(n, dtype=np.float32)
    for p in parts:
        mix[: len(p)] += p
    fade = min(len(mix), int(0.04 * RATE))
    mix[-fade:] *= np.linspace(1.0, 0.0, fade)
    return mix / max(1e-6, np.abs(mix).max()) * 10 ** (-1 / 20)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, layers in SFX.items():
        y = build(layers)
        sf.write(os.path.join(OUT, name + ".wav"), y, RATE, subtype="PCM_16")
        print("%-12s %.2fs  <- %s" % (name, len(y) / RATE, " + ".join(l[0] for l in layers)))


if __name__ == "__main__":
    main()
