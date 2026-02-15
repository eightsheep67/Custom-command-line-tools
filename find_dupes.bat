@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ======================================================
echo   8K 影库深度扫描 (全兼容版：解决括号/逗号/空格报错)
echo ======================================================
echo.

set "del_log=待删除清单_改为bat运行.txt"
set "dupe_log=重复视频清单_手动核对.txt"

:: 初始化文件
echo @echo off > "%del_log%"
echo chcp 65001 ^>nul >> "%del_log%"
echo echo 正在批量清理没有视频的僵尸文件夹... >> "%del_log%"

echo 重复视频扫描报告 - 生成时间: %date% %time% > "%dupe_log%"
echo ------------------------------------------------------ >> "%dupe_log%"

set /a total_v_folders=0
set /a zero_v=0
set /a multi_v=0

echo [正在分析] 扫描中，请稍候...

:: 第一层：遍历演员文件夹 (%%a)
:: 直接通过 dir 获取目录列表，避开 if 字符串对比
for /f "delims=" %%a in ('dir /b /ad') do (
    set "dir_name=%%a"
    
    :: 检查是否是文件夹，且不是我们生成的日志文件
    if exist "%%a\" (
        echo [扫描演员] !dir_name!
        
        :: 第二层：遍历该演员下的视频文件夹 (%%v)
        for /d %%v in ("%%a\*") do (
            set /a total_v_folders+=1
            set "cur_path=%%~fv"
            set /a vid_count=0
            
            :: 统计视频数量 (mp4/mkv/ts/avi/mov)
            for /f "delims=" %%f in ('dir /b /a-d "!cur_path!\*.mp4" "!cur_path!\*.mkv" "!cur_path!\*.ts" "!cur_path!\*.avi" "!cur_path!\*.mov" 2^>nul') do (
                set /a vid_count+=1
            )
            
            :: 逻辑 A：无视频
            if !vid_count! equ 0 (
                set /a zero_v+=1
                echo [待删除] "%%~nxv"
                echo echo 正在删除: "!cur_path!" >> "%del_log%"
                echo rd /s /q "!cur_path!" >> "%del_log%"
            )
            
            :: 逻辑 B：重复视频
            if !vid_count! geq 2 (
                set /a multi_v+=1
                echo [发现重复] "%%~nxv" (!vid_count!个)
                echo [重复目录] 路径: "!cur_path!" >> "%dupe_log%"
                for /f "delims=" %%f in ('dir /b /a-d "!cur_path!\*.mp4" "!cur_path!\*.mkv" "!cur_path!\*.ts" 2^>nul') do (
                    echo          * %%f >> "%dupe_log%"
                )
                echo ------------------------------------------------------ >> "%dupe_log%"
            )
        )
    )
)

echo echo 清理完成！ >> "%del_log%"
echo pause >> "%del_log%"

echo.
echo ======================================================
echo 扫描完成！最终统计：
echo ------------------------------------------------------
echo 视频文件夹总数: !total_v_folders!
echo 待删除(无视频)数: !zero_v!
echo 冗余(多视频)数: !multi_v!
echo.
echo [操作]：查看生成的两个清单文件。
echo ======================================================
pause
