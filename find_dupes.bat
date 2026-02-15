@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ======================================================
echo   8K 影库清理工具 (生成删除命令清单 - 跳过演员层)
echo ======================================================
echo.

set "logfile=待删除清单_改为bat后运行.txt"

:: 初始化清单文件，加入编码声明防止中文路径乱码
echo @echo off > "%logfile%"
echo chcp 65001 ^>nul >> "%logfile%"
echo echo 正在批量清理没有视频的僵尸文件夹... >> "%logfile%"

set /a total_v_folders=0
set /a zero_v=0

echo [正在分析] 扫描中，请稍候...

:: 第一层：遍历演员文件夹 (%%a)
for /d %%a in (*) do (
    echo [扫描演员] %%~nxa
    
    :: 第二层：遍历该演员下的视频文件夹 (%%v)
    for /d %%v in ("%%a\*") do (
        set /a total_v_folders+=1
        set "cur_path=%%~fv"
        set /a vid_count=0
        
        :: 检查该目录下是否有视频 (mp4/mkv/ts/avi/mov/wmv)
        for /f "delims=" %%f in ('dir /b /a-d "!cur_path!\*.mp4" "!cur_path!\*.mkv" "!cur_path!\*.ts" "!cur_path!\*.avi" "!cur_path!\*.mov" "!cur_path!\*.wmv" 2^>nul') do (
            set /a vid_count+=1
        )
        
        :: 如果没有视频 (只有图片、nfo、字幕等)
        if !vid_count! equ 0 (
            set /a zero_v+=1
            echo [待删除] "%%~nxv"
            :: 写入删除命令：rd /s /q 表示删除文件夹及其子内容
            echo echo 正在删除: "!cur_path!" >> "%logfile%"
            echo rd /s /q "!cur_path!" >> "%logfile%"
        )
    )
)

echo echo 清理完成！ >> "%logfile%"
echo pause >> "%logfile%"

echo.
echo ======================================================
echo 扫描完成！
echo ------------------------------------------------------
echo 视频文件夹总数: !total_v_folders!
echo 待删除(无视频)数: !zero_v!
echo.
echo [操作说明]：
echo 1. 已生成报告: "%logfile%"
echo 2. 请打开该文件，确认里面的路径是否正确。
echo 3. 若确认无误，将文件后缀名改为 .bat 即可运行清理。
echo ======================================================
pause
