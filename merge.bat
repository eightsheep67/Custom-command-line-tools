@echo off
setlocal enabledelayedexpansion

:: 1. 扫描并排序
if exist "filelist.txt" del "filelist.txt"
set "first_file="
set count=0

echo =======================================================
echo         8K VR 智能合并 (带预填重命名功能)
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

:: 2. 精准取名逻辑
set "full_name=!first_file!"
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

:: 3. 用户确认 (改用 VBScript 弹窗，完美规避输入法干扰)
echo 正在弹出重命名窗口...

:: 创建一个临时的 VBS 脚本来获取用户输入
set "vbs_file=%temp%\input.vbs"
echo strInput = InputBox("请修改文件名:", "8K VR 智能合并", "!suggested_name!") > "%vbs_file%"
echo WScript.Echo strInput >> "%vbs_file%"

:: 运行 VBS 并捕获输出
for /f "delims=" %%i in ('cscript //nologo "%vbs_file%"') do (
    set "final_name=%%i"
)

:: 如果用户点取消或清空，则恢复建议名
if "!final_name!"=="" (
    set "final_name=!suggested_name!"
    echo 用户未输入，使用建议名: !final_name!
) else (
    echo 最终确认名称: !final_name!
)

:: 删除临时文件
if exist "%vbs_file%" del "%vbs_file%"

:: 4. 路径判断与合并
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