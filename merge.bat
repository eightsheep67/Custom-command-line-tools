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

:: 3. 用户确认 (使用 PowerShell 模拟按键实现预填内容)
echo 建议名称已准备，请按需修改 (支持退格/编辑):
set "final_name="
:: 调用 PowerShell 在输入流中填入建议名
for /f "delims=" %%i in ('powershell -Command "$s='!suggested_name!'; $w=New-Object -ComObject WScript.Shell; $w.SendKeys($s); Read-Host '确认名称'"') do (
    set "final_name=%%i"
)

:: 防止用户直接清空了名字导致报错
if "!final_name!"=="" set "final_name=!suggested_name!"

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