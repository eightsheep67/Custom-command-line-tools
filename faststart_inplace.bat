@echo off
:: 解决中文路径乱码
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ======================================================
echo   8K 视频全能优化工具 (Faststart + hvc1 兼容性修复)
echo ======================================================

:: 第一步：预扫描总文件数
echo [1/2] 正在扫描子目录，请稍候...
set /a total=0
for /r %%f in (*.mp4) do (
    echo "%%f" | findstr /i "_temp.mp4" >nul
    if !errorlevel! neq 0 set /a total+=1
)

if %total% equ 0 (
    echo [提示] 没找到 mp4 视频文件。
    pause
    exit
)

echo [2/2] 发现 %total% 个视频，准备开始优化...
echo.

:: 第二步：正式开始处理
set /a current=0
for /r %%f in (*.mp4) do (
    echo "%%f" | findstr /i "_temp.mp4" >nul
    if !errorlevel! neq 0 (
        set /a current+=1
        echo ------------------------------------------------------
        echo [进度: !current! / %total%] 正在处理: "%%~nxf"
        
        :: 执行快速封装：复制流 + 网页优化 + 强制 hvc1 标签
        :: -tag:v hvc1 是解决苹果设备黑屏的关键
        ffmpeg -i "%%f" -c copy -map 0 -movflags +faststart -tag:v hvc1 "%%~dpnf_temp.mp4" -y -stats -loglevel error
        
        if !errorlevel! equ 0 (
            echo.
            echo [状态] ✅ 优化成功 (已开启 Faststart 并修正为 hvc1)
            del /f /q "%%f"
            pushd "%%~dpf"
            ren "%%~nf_temp.mp4" "%%~nxf"
            popd
        ) else (
            echo.
            echo [状态] ❌ 处理失败: "%%f"
            if exist "%%~dpnf_temp.mp4" del /f /q "%%~dpnf_temp.mp4"
        )
    )
)

:: 处理完成后的提醒
echo.
echo ======================================================
echo   🎉 全部处理完成！共优化 %total% 个视频。
echo ======================================================
:: 蜂鸣声提醒
echo ^G
:: 弹出 Windows 桌面通知 (通过 PowerShell 实现)
powershell -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('8K 视频批量优化已完成！共计 %total% 个文件。', '处理完毕')"
pause
