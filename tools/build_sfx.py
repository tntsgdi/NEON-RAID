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

# 每个音效：layers = [(文件名片段或 @合成, 起点秒, 时长秒, 增益 dB)]，cat 决定统一的响度，lp 可选低通
# 响度按类别统一 RMS（打击 -16、破空 -20、界面/环境 -24 dBFS），而不是只看峰值
CAT_RMS = {"hit": -16.0, "whoosh": -20.0, "ui": -24.0}
SFX = {
    # 挥刀：三段用三种不同的破空声，压掉 4 kHz 以上的嘶嘶声，叠一层短促的剑鸣
    "swing_1": {"cat": "whoosh", "lp": 4000, "layers": [("Fast Action Swish_HW 05", 0.60, 0.29, 0), ("@ring", 0.0, 0.22, -10)]},
    "swing_2": {"cat": "whoosh", "lp": 4000, "layers": [("Action Swish_HW 02", 2.54, 0.29, 0), ("@ring", 0.0, 0.22, -11)]},
    "swing_3": {"cat": "whoosh", "lp": 4000, "layers": [("Seq 2.1 whoosh #1 96 HK1", 0.01, 0.22, 0), ("@ring", 0.0, 0.25, -9)]},
    "swing_heavy": {"cat": "whoosh", "lp": 4500, "layers": [("Action Swish_HW 02", 1.07, 0.29, 0), ("Fast Action Swish_HW 05", 0.11, 0.35, -4), ("@ring", 0.0, 0.35, -7)]},
    # 命中机器人：3 毫秒的起音 click + 功夫片式打击 + 金属敲击
    "hit_1": {"cat": "hit", "layers": [("@click", 0.0, 0.01, -2), ("Seq 2.27 Hit #1 96 HK1", 0.10, 0.23, 0), ("METLImpt_Metal Old File Impact Tap", 0.12, 0.30, -8)]},
    "hit_2": {"cat": "hit", "layers": [("@click", 0.0, 0.01, -2), ("Seq 2.1 Hit #1 96 HK1", 0.07, 0.26, 0), ("METLImpt_Metal Old File Impact Tap", 0.12, 0.30, -8)]},
    "hit_heavy": {"cat": "hit", "layers": [("@click", 0.0, 0.01, 0), ("Hit Impact Hard Metal Scrap Debris_UC 01", 0.21, 0.47, 0), ("Seq 2.1 Hit #3 96 HK1", 0.08, 0.29, -3)]},
    "break": {"cat": "hit", "layers": [("demolisher_metal_impact_002", 0.0, 1.0, 0), ("glass_impact_break_small_014", 0.0, 0.5, -10)]},
    # 移动：只留短促、低调的声音
    "dash": {"cat": "whoosh", "layers": [("WHSH_InsJ_Whooshing_Low_Double_01-01", 0.04, 0.19, 0)]},
    "walljump": {"cat": "whoosh", "layers": [("Whoosh_Cloth_Leather_Fight_174", 0.0, 0.30, 0)]},
    "land": {"cat": "ui", "layers": [("IMPACT_LOW_THUD_10", 0.0, 0.20, 0)]},
    "slide": {"cat": "ui", "lp": 5000, "layers": [("EFX SD Sliding Whoosh By 06", 0.0, 0.45, 0)]},
    # 战斗
    "shot": {"cat": "whoosh", "layers": [("@click", 0.0, 0.01, -4), ("SCIWeap_Shot Pulse YR 05", 0.0, 0.45, 0)]},
    "enemy_shot": {"cat": "whoosh", "layers": [("Blast Laser 4", 0.0, 0.5, 0)]},
    "deflect": {"cat": "hit", "lp": 4000, "layers": [("@click", 0.0, 0.01, 0), ("Machete_Hit_Ring_Fienup_001", 0.0, 0.7, 0), ("@ring", 0.0, 0.3, -6)]},
    # 神经超频：重音就在开头（重击），然后低音往下坠，像时间被拖慢
    "overclock": {"cat": "hit", "layers": [("PUNCH_DESIGNED_LIGHT_78", 0.0, 0.4, 0), ("Bass Drop & Downer Fast 16", 0.0, 0.9, -14), ("@ring", 0.0, 0.5, -3)]},
    "hurt": {"cat": "hit", "layers": [("PUNCH_PERCUSSIVE_HEAVY_06", 0.0, 0.4, 0), ("Broken_Robot_Morphing_Short_Static_Pitch_Confused_Glitch_02", 0.0, 0.4, -6)]},
    "charge": {"cat": "ui", "layers": [("electricity_surge_discharge_electrical_arc_crackling_002_01", 0.0, 0.5, -2)]},
    "shield_block": {"cat": "hit", "layers": [("cinematic_metal_impact_050", 0.0, 0.4, 0)]},
}


def synth(kind, dur):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    if kind == "@click":
        return (np.random.default_rng(3).standard_normal(n) * np.exp(-t * 900)).astype(np.float32)
    if kind == "@ring":
        # 剑鸣：1.1→2.6 kHz 的短扫频，带两个泛音，迅速衰减
        f = 1100 + 1500 * (t / max(dur, 1e-3))
        ph = 2 * np.pi * np.cumsum(f) / RATE
        x = np.sin(ph) + 0.4 * np.sin(2.01 * ph) + 0.2 * np.sin(3.03 * ph)
        return (x * np.exp(-t * 18) * np.minimum(t / 0.004, 1)).astype(np.float32)
    sys.exit("未知合成层：" + kind)


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


def build(recipe):
    parts = []
    for f, s, d, g in recipe["layers"]:
        x = synth(f, d) if f.startswith("@") else load(f, s, d)
        parts.append(x / max(1e-6, np.abs(x).max()) * 10 ** (g / 20))
    n = max(len(p) for p in parts)
    mix = np.zeros(n, dtype=np.float32)
    for p in parts:
        mix[: len(p)] += p
    if recipe.get("lp"):
        mix = lowpass(mix, recipe["lp"])
    fade = min(len(mix), int(0.04 * RATE))
    mix[-fade:] *= np.linspace(1.0, 0.0, fade)
    # 按类别统一响度：取开头 250 ms 和整段 RMS 中较大的（长尾巴的低频也算进去）；峰值不超过 -1 dBFS
    head = mix[: int(0.25 * RATE)]
    rms = max(np.sqrt(np.mean(head ** 2)), np.sqrt(np.mean(mix ** 2))) + 1e-9
    mix = mix * (10 ** (CAT_RMS[recipe["cat"]] / 20) / rms)
    peak = np.abs(mix).max()
    if peak > 10 ** (-1 / 20):
        mix *= 10 ** (-1 / 20) / peak
    return mix.astype(np.float32)


def lowpass(x, cut):
    from scipy.signal import butter, sosfilt
    return sosfilt(butter(4, cut, "low", fs=RATE, output="sos"), x).astype(np.float32)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, recipe in SFX.items():
        y = build(recipe)
        sf.write(os.path.join(OUT, name + ".wav"), y, RATE, subtype="PCM_16")
        print("%-12s %.2fs  <- %s" % (name, len(y) / RATE, " + ".join(l[0] for l in recipe["layers"])))


if __name__ == "__main__":
    main()
