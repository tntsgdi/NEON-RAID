@echo off
rem 双击直接试玩 M1（不用开编辑器）
set "GODOT=%USERPROFILE%\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=E:\godot\godot47\Godot_v4.7-stable_win64.exe"
start "" "%GODOT%" --path "%~dp0"
