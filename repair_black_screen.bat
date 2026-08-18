@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ==================== 配置区 ====================
:: 匹配已经切坏的文件名规则（默认修复 *_cut.mp4）
set TARGET_PATTERN=*.mp4

:: 修复后的文件后缀标记（例：xxx_cut.mp4 -> xxx_cut_fixed.mp4）
set FIX_SUFFIX=_fixed
:: ===============================================

echo ===================================================
echo   针对黑屏坏视频的精准二次修复工具
echo ===================================================
echo.

where ffmpeg >nul 2>nul
if %errorlevel% neq 0 (
    echo [错误] 未检测到 ffmpeg 命令！请检查 PATH 环境变量。
    echo.
    pause
    exit /b
)

set count=0

for %%f in ("%TARGET_PATTERN%") do (
    set "filename=%%~nf"
    set "ext=%%~xf"
    
    if "!filename:%FIX_SUFFIX%=!"=="!filename!" (
        set /a count+=1
        set "output_file=!filename!%FIX_SUFFIX%!ext!"
        
        echo ---------------------------------------------------
        echo [正在修复黑屏坏视频] "%%f"
        echo ---------------------------------------------------
        
        :: 核心修复原理：
        :: 1. -discard nokey / -ss 00:00:00 强制丢弃坏视频开头的无效时间戳和无效B/P帧
        :: 2. 重新编码视频流生成全新的关键帧，并重置时间戳为 0
        
        ffmpeg -hide_banner -ss 00:00:00 -i "%%f" -c:v h264_nvenc -cq 23 -preset p4 -c:a copy -avoid_negative_ts make_zero -movflags +faststart -y "!output_file!"
        
        if !errorlevel! neq 0 (
            echo.
            echo NVENC 硬件加速不可用，自动切换至 CPU 极速重构模式...
            ffmpeg -hide_banner -ss 00:00:00 -i "%%f" -c:v libx264 -crf 23 -preset ultrafast -g 60 -c:a copy -avoid_negative_ts make_zero -movflags +faststart -y "!output_file!"
        )
        
        if !errorlevel! equ 0 (
            echo.
            echo   └─ [成功] "%%f" 修复完成！
        ) else (
            echo.
            echo   └─ [失败] 该文件坏得太严重，建议重新用原视频切割。
        )
        echo.
    )
)

if %count% equ 0 (
    echo 没有找到需要修复的文件（匹配规则: %TARGET_PATTERN%）。
) else (
    echo ===================================================
    echo 处理完成！共完成 %count% 个视频的修复。
    echo ===================================================
)

echo.
pause