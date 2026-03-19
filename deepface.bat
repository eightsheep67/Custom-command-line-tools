@echo off
setlocal enabledelayedexpansion

:: ==========================================
:: 1. 3080 Ti 性能设置区
:: ==========================================
set "SCALE_FACTOR=2.0"
set "THREAD_COUNT=16"
set "SYSTEM_MEMORY_LIMIT=24"
set "VRAM_STRATEGY=tolerant"
set "IMAGE_QUALITY=90"
set "VIDEO_QUALITY=85"
set "VIDEO_ENCODER=hevc_nvenc"
:: 强制禁用内容分析器（针对 3.x 及以上版本有效）
set "FACEFUSION_CONTENT_ANALYSER_DISABLED=1"


:: ==========================================
:: 2. 环境路径锁定
:: ==========================================
set "FF_PATH=D:\Applications\FF\facefusion"
set PATH=%FF_PATH%\venv\Lib\site-packages\onnxruntime\capi;%PATH%
set PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.8\bin;%PATH%
set PATH=C:\Windows\System32;%PATH%


:: 3. 路径预处理
set "BASE_DIR=%~dp0"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
set "SOURCE_FILE=%BASE_DIR%\face.jpg"
set "OUTPUT_DIR=%BASE_DIR%\output"
set "FAIL_DIR=%BASE_DIR%\fail"

:: 确保文件夹存在
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
if not exist "%FAIL_DIR%" mkdir "%FAIL_DIR%"

:: 4. 环境检查与切换
d:
cd /d "%FF_PATH%"
if not exist "venv\Scripts\activate.bat" (
    echo [错误] 找不到虚拟环境，请检查 D:\Applications\FF\facefusion 路径！
    pause
    exit
)
call venv\Scripts\activate

echo ======================================================
echo [3080 Ti 容错增强模式] 启动成功
echo [功能] 自动将失败任务移至: \fail 文件夹
echo ======================================================

:: 5. 遍历任务
:: 使用 /r 确保路径处理更稳健
for %%F in ("%BASE_DIR%\*.jpg" "%BASE_DIR%\*.png" "%BASE_DIR%\*.webp" "%BASE_DIR%\*.mp4" "%BASE_DIR%\*.mov") do (
    set "FULL_PATH=%%F"
    set "FILE_NAME=%%~nxF"
    set "TARGET_OUT=%OUTPUT_DIR%\%%~nxF"
    
    :: 排除 face.jpg 自身
    if /i "%%~nxF" NEQ "face.jpg" (
        if exist "!TARGET_OUT!" (
            echo [跳过] %%~nxF 已存在
        ) else (
            echo [正在处理] %%~nxF ...
            
            :: 核心指令
            python facefusion.py headless-run ^
             --source-paths "%SOURCE_FILE%" ^
             --target-path "%%F" ^
             --output-path "!TARGET_OUT!" ^
             --processors face_swapper face_enhancer ^
             --execution-providers cuda ^
             --execution-thread-count %THREAD_COUNT% ^
             --system-memory-limit %SYSTEM_MEMORY_LIMIT% ^
             --video-memory-strategy %VRAM_STRATEGY% ^
               --face-detector-model yolo_face ^
               --face-mask-types box occlusion region ^
             --face-mask-blur 0.3 ^
             --face-selector-mode one ^
             --face-swapper-model inswapper_128_fp16 ^
             --face-enhancer-model gfpgan_1.4 ^
             --face-enhancer-blend 100 ^
             --face-swapper-pixel-boost 1024x1024 ^
             --output-image-scale %SCALE_FACTOR% ^
             --output-image-quality %IMAGE_QUALITY% ^
             --output-video-scale %SCALE_FACTOR% ^
             --output-video-encoder %VIDEO_ENCODER% ^
             --output-video-quality %VIDEO_QUALITY%

            :: --- 容错判定逻辑 ---
            if errorlevel 1 (
                echo [!!警告!!] %%~nxF 处理失败，正在隔离...
                :: 失败后把原图移走，防止死循环
                move "%%F" "%FAIL_DIR%\" >nul
                :: 如果生成了错误的 0 字节文件，顺便清理掉
                if exist "!TARGET_OUT!" del /q "!TARGET_OUT!"
                echo [状态] 已跳过并继续后续任务。
                echo --------------------------------------
            )
        )
    )
)

echo.
echo [任务报告] 全部流程处理完毕！
pause
