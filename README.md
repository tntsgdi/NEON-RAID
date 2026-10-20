# 霓虹行者 / NEON RAID

2D 横版高速动作：跑酷 × 射击 × 瞬间夺壳 × 霓虹电网。Godot 4.7。

当前进度：**M2 基础战斗**（F4 在手感测试场和战斗训练场之间切换）。设计定案见 [design/DECISIONS.md](design/DECISIONS.md)，进度见 [design/TODO.md](design/TODO.md)。

## 操作

| 键 | 动作 |
| --- | --- |
| A / D | 移动（按住即加速到疾跑） |
| 空格 | 跳（按得越久跳得越高；贴墙时按住朝墙方向连按 = 往上爬） |
| Shift | 冲刺（可配合方向键斜冲，空中一次） |
| C | 滑铲 |
| 鼠标 | 瞄准 |
| 左键 | 电磁手枪点射（8 格能量，停火回充） |
| 右键 | 挥刀，朝面朝方向（连按三段；按住 W 上挑，空中按住 S 下劈） |
| R | 重来 |
| F1 | 手感调参面板 |
| F2 | 中文 / English |
| F3 | 高清 / 像素渲染 |
| F4 | 手感测试场 / 战斗训练场 |

## 测试

```bash
# headless 验收（脚本输入，不碰键鼠、不写文件）
Godot --headless --path . -s tests/m1_test.gd --fixed-fps 60
Godot --headless --path . -s tests/m2_test.gd --fixed-fps 60
# 姿势截图（窗口在屏幕外、不抢焦点），输出到 screenshots/
tools/run_test.sh tests/shots.gd --fixed-fps 60
```
