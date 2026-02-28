@echo off
setlocal enabledelayedexpansion

:: 1. 扫描文件并排序
if exist "filelist.txt" del "filelist.txt"
set "first_file="
set count=0

echo =======================================================
echo           8K VR 视频合并清单 (按名称排序)
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

:: 2. 深度取名逻辑：循环切除末尾的特征字符 (数字, 8k, part 等)
set "suggested_name=!first_file!"

:trim_loop
:: 获取最后一个下划线后的内容
set "temp=!suggested_name!"
set "last_part="
:find_last
for /f "tokens=1* delims=_" %%a in ("!temp!") do (
    if "%%b"=="" (set "last_part=%%a") else (set "temp=%%b" & goto find_last)
)

:: 检查这个末尾字段是否包含特征：是数字？包含8k？包含part？
set "should_trim=0"
:: 匹配纯数字 (1, 01, 2...)
echo !last_part!| findstr /r "^[0-9]*$" >nul && set "should_trim=1"
:: 匹配 8k (不分大小写)
echo !last_part!| findstr /i "8k" >nul && set "should_trim=1"
:: 匹配 part 或 cd (常见分段标识)
echo !last_part!| findstr /i "part cd" >nul && set "should_trim=1"

if "!should_trim!"=="1" (
    :: 执行切除：去掉最后一个下划线及其后面的内容
    set "to_remove=_!last_part!"
    call set "suggested_name=%%suggested_name:!to_remove!=%%"
    goto :trim_loop
)

:: 3. 用户确认
echo 建议合并后的文件名: [ !suggested_name! ]
set /p "user_input=直接回车使用建议名，或输入新名称: "
if "!user_input!"=="" (set "final_name=!suggested_name!") else (set "final_name=!user_input!")

echo -------------------------------------------------------
echo 最终输出文件: !final_name!.mp4
echo 正在执行秒速合并 (Copy 模式)...
echo -------------------------------------------------------

:: 4. 调用 ffmpeg 执行合并
ffmpeg -f concat -safe 0 -i filelist.txt -c copy -tag:v hvc1 -movflags faststart "!final_name!.mp4"

:: 5. 清理并打开文件夹
del filelist.txt
echo -------------------------------------------------------
echo [完成] 合并成功！
start "" "%~dp0"
pause
