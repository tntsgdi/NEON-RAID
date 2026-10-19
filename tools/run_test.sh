#!/usr/bin/env bash
# 带渲染的测试/截图：窗口从屏幕外启动、不抢焦点、点击穿透，项目里不写任何文件
# （编辑器里 F5 运行永远不会受影响）。测试脚本自己加 tests/test_window.gd。
# 用法：tools/run_test.sh <test.gd> [--fixed-fps 60] -- <args...>
cd "$(dirname "$0")/.."
script="$1"; shift
/e/godot/godot47/Godot_v4.7-stable_win64_console.exe --path . --resolution 1920x1080 --position -2600,40 -s "$script" "$@"
