@echo off
:: 再次加强屏蔽
@echo off >nul 2>&1
chcp 65001 >nul

set "del_file=待删除清单_改为bat后运行.txt"
set "multi_file=多视频清单_待人工确认.txt"

:: 初始化
echo @echo off > "%del_file%"
echo chcp 65001 ^>nul >> "%del_file%"
echo 📁 包含 2 个及以上视频文件: > "%multi_file%"

echo [开始分析] 正在静默扫描，请稍候...

:: 第一层：遍历演员
for /d %%a in (*) do (
    echo [正在扫描] %%~nxa
    
    :: 第二层：遍历视频文件夹
    for /d %%v in ("%%a\*") do (
        :: 重点：将子程序的所有输出强制丢弃到 nul
        call :check_folder "%%~fv" >nul 2>&1
    )
)

echo.
echo ======================================================
echo 扫描完成！请确认生成的 .txt 文件。
echo ======================================================
pause
exit /b

:check_folder
set "v_count=0"
:: 在这里统计视频
for /f "delims=" %%f in ('dir /b /a-d "%~1\*.mp4" "%~1\*.mkv" "%~1\*.ts" "%~1\*.avi" "%~1\*.mov" "%~1\*.wmv" 2^>nul') do (
    set /a v_count+=1
)

:: 写入逻辑 (这里使用 >> 是向文件写入，不受 >nul 影响)
if %v_count% equ 0 (
    echo echo 正在删除: "%~1" >> "%del_file%"
    echo rd /s /q "%~1" >> "%del_file%"
) else if %v_count% geq 2 (
    echo [%v_count%个视频] "%~1" >> "%multi_file%"
)
goto :eof
