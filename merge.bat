@echo off
setlocal enabledelayedexpansion

:: 1. 扫描并排序
if exist "filelist.txt" del "filelist.txt"
set "first_file="
set count=0

echo =======================================================
echo        8K VR 智能合并 (精准切除最后两段后缀)
echo =======================================================

for /f "delims=" %%i in ('dir /b /on *.mp4') do (
    if not "%%i"=="Combined_Video.mp4" (
        if "!first_file!"=="" set "first_file=%%~ni"
        echo [!count!] %%i
        echo file '%%i' >> filelist.txt
        set /a count+=1
    )
)

if !count! equ 0 (echo [错误] 未发现视频文件！ & pause & exit)
echo -------------------------------------------------------

:: 2. 精准取名逻辑：只切掉最后两个 "_" 之后的内容
:: 示例: twojav.com@ipvr00344_1_8k -> twojav.com@ipvr00344
set "full_name=!first_file!"

:: 第一次剥离 (去掉 _8k)
set "name_tmp=!full_name!"
set "suggested_name=!full_name!"
:find_last_1
for /f "tokens=1* delims=_" %%a in ("!name_tmp!") do (
    if "%%b"=="" (
        set "to_remove=_%%a"
        call set "suggested_name=%%full_name:!to_remove!=%%"
    ) else (
        set "name_tmp=%%b"
        goto find_last_1
    )
)

:: 第二次剥离 (去掉 _1)
set "full_name=!suggested_name!"
set "name_tmp=!full_name!"
:find_last_2
for /f "tokens=1* delims=_" %%a in ("!name_tmp!") do (
    if "%%b"=="" (
        set "to_remove=_%%a"
        call set "suggested_name=%%full_name:!to_remove!=%%"
    ) else (
        set "name_tmp=%%b"
        goto find_last_2
    )
)

:: 3. 用户确认
echo 建议名称: [ !suggested_name! ]
set /p "user_input=直接回车使用建议名，或手动输入: "
if "!user_input!"=="" (set "final_name=!suggested_name!") else (set "final_name=!user_input!")

:: 4. 路径判断与合并 (hvc1 + faststart)
set "current_drive=%~d0"
if /i "%current_drive%"=="D:" (
    set "output_path=!final_name!.mp4"
    set "is_nas=0"
) else (
    set "output_path=D:\!final_name!_temp_merge.mp4"
    set "is_nas=1"
)

ffmpeg -y -f concat -safe 0 -i filelist.txt -c copy -tag:v hvc1 -movflags faststart "!output_path!"

if "!is_nas!"=="1" (
    move "!output_path!" "!final_name!.mp4"
)

del filelist.txt
echo -------------------------------------------------------
echo [完成] 合并成功！输出: !final_name!.mp4
pause
