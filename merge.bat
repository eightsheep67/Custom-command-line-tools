@echo off
setlocal enabledelayedexpansion

:: 1. 扫描文件
if exist "filelist.txt" del "filelist.txt"
set "first_file_full="
set "first_file_name="
set count=0

echo =======================================================
echo      8K VR 智能合并 (精准切除 + 自动增加 _merge)
echo =======================================================

for /f "delims=" %%i in ('dir /b /on *.mp4') do (
    if not "%%i"=="Combined_Video.mp4" (
        if "!first_file_full!"=="" (
            set "first_file_full=%%i"
            set "first_file_name=%%~ni"
        )
        echo [!count!] %%i
        echo file '%%i' >> filelist.txt
        set /a count+=1
    )
)

if !count! equ 0 (echo [错误] 未发现视频文件！ & pause & exit)

:: 2. 自动检测编码格式
set "v_tag="
for /f "tokens=*" %%a in ('ffprobe -v error -select_streams v:0 -show_entries stream^=codec_name -of default^=noprint_wrappers^=1:nokey^=1 "!first_file_full!"') do (
    set "codec=%%a"
)

echo -------------------------------------------------------
echo 检测到编码: !codec!
if /i "!codec!"=="hevc" (
    echo [模式] H.265: 自动添加 hvc1 标签
    set "v_tag=-tag:v hvc1"
) else (
    echo [模式] H.264: 标准流复制
    set "v_tag="
)
echo -------------------------------------------------------

:: 3. 精准取名逻辑：只切掉最后一个分隔符之后的内容
set "suggested_name=!first_file_name!"

:: 只执行一次末尾切除，防止把主编号(如-184)也切了
set "temp_name=!suggested_name!"
set "last_char_idx=-1"
set "pos=0"

:find_loop
set "char=!temp_name:~%pos%,1!"
if "!char!"=="" goto :find_done
if "!char!"=="_" set "last_char_idx=%pos%"
if "!char!"=="-" set "last_char_idx=%pos%"
set /a pos+=1
goto :find_loop

:find_done
if %last_char_idx% geq 0 (
    set /a next_pos=%last_char_idx% + 1
    set "tail=!temp_name:~%next_pos%!"
    
    set "need_strip=0"
    :: 如果后缀是数字或者8k，则标记为需要切除
    echo !tail!| findstr /r "^[0-9][0-9]*$ ^8k$ ^8K$" >nul && set "need_strip=1"
    
    if "!need_strip!"=="1" (
        set "suggested_name=!temp_name:~0,%last_char_idx%!"
    )
)

:: 4. 用户确认
echo 建议名称: [ !suggested_name! ]
set "user_input="
set /p "user_input=直接回车使用建议名，或手动输入: "
if "!user_input!"=="" (set "final_name=!suggested_name!") else (set "final_name=!user_input!")

:: --- 核心修改：统一增加 _merge 后缀 ---
set "final_name=!final_name!_merge"
:: ------------------------------------

:: 5. 路径与合并逻辑
set "current_drive=%~d0"
if /i "%current_drive%"=="D:" (
    set "output_path=!final_name!.mp4"
    set "is_nas=0"
) else (
    set "output_path=D:\!final_name!_temp_merge.mp4"
    set "is_nas=1"
)

ffmpeg -y -f concat -safe 0 -i filelist.txt -c copy !v_tag! -movflags faststart "!output_path!"

if "!is_nas!"=="1" if exist "!output_path!" (
    move "!output_path!" "!final_name!.mp4"
)

if exist "filelist.txt" del "filelist.txt"
echo -------------------------------------------------------
echo [完成] 合并成功！输出文件名: !final_name!.mp4
pause