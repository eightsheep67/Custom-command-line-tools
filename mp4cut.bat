@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ==================== 配置区 ====================
:: 切割起始时间（现在设成任何时间都不会黑屏了）
set START_TIME=00:05:35

:: 输出文件名的后缀标记
set SUFFIX=_cut
:: ===============================================

echo ===================================================
echo   MP4 批量精准切割工具（全时间点防黑屏版）
echo   起始时间: %START_TIME%
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

for %%f in ("*.mp4") do (
    set "filename=%%~nf"
    set "ext=%%~xf"
    
    if "!filename:%SUFFIX%=!"=="!filename!" (
        set /a count+=1
        set "output_file=!filename!%SUFFIX%!ext!"
        
        echo ---------------------------------------------------
        echo [正在处理] "%%f"
        echo ---------------------------------------------------
        
        :: 关键修改：把 -ss 放到 -i 后面，进行精准帧定位与时间戳归零
        :: 1. 优先尝试 N 卡 NVENC 硬件加速
        ffmpeg -hide_banner -i "%%f" -ss %START_TIME% -c:v h264_nvenc -cq 23 -preset p4 -c:a copy -avoid_negative_ts make_zero -movflags +faststart -y "!output_file!"
        
        if !errorlevel! neq 0 (
            echo.
            echo [提示] NVENC 硬件加速不可用，自动切换至 CPU 极速模式...
            :: 2. 降级到 CPU ultrafast 模式
            ffmpeg -hide_banner -i "%%f" -ss %START_TIME% -c:v libx264 -crf 23 -preset ultrafast -g 60 -c:a copy -avoid_negative_ts make_zero -movflags +faststart -y "!output_file!"
        )
        
        if !errorlevel! equ 0 (
            echo.
            echo   └─ [成功] "%%f" 切割完成！
        ) else (
            echo.
            echo   └─ [失败] 处理出现错误。
        )
        echo.
    )
)

if %count% equ 0 (
    echo 当前目录下没有找到需要处理的 MP4 文件。
) else (
    echo ===================================================
    echo 处理完成！共完成 %count% 个视频的切割。
    echo ===================================================
)

echo.
pause