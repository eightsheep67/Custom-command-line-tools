@echo off
:: 使用 65001 编码处理中文和日文路径
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ======================================================
echo   8K 影库路径提取工具 (格式: ./演员/目录/视频)
echo ======================================================

set "output_file=视频路径清单.txt"

:: 初始化输出文件 (清除旧内容)
echo # 8K 影库路径清单 - 生成时间: %date% %time% > "%output_file%"

set /a file_count=0

echo [正在扫描] 请稍候...

:: 第一层：遍历演员文件夹 (%%a)
for /d %%a in (*) do (
    set "actor=%%~nxa"
    
    :: 第二层：遍历该演员下的视频文件夹 (%%v)
    for /d %%v in ("%%a\*") do (
        set "v_folder=%%~nxv"
        
        :: 第三层：列出该文件夹下的视频文件 (%%f)
        :: 支持 mp4, mkv, ts, avi, mov
        for /f "delims=" %%f in ('dir /b /a-d "%%v\*.mp4" "%%v\*.mkv" "%%v\*.ts" "%%v\*.avi" "%%v\*.mov" 2^>nul') do (
            set /a file_count+=1
            :: 输出格式：./演员/视频文件夹/视频文件名
            echo ./!actor!/!v_folder!/%%f >> "%output_file%"
        )
    )
)

echo.
echo ======================================================
echo 扫描完成！
echo 总计找到视频文件: %file_count% 个
echo.
echo 清单已保存至: "%output_file%"
echo ======================================================

:: 自动打开记事本查看结果
start notepad "%output_file%"
pause
