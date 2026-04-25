# ===========================================================
# 3080 Ti 硬件加速 - 全功能诊断版 (数量过滤 + 状态全显)
# ===========================================================

# --- 用户配置区 ---
$OVERWRITE  = 1  # 【1: 覆盖已有视频 | 0: 跳过已有视频】
$MIN_COUNT  = 20 # 【起做门槛：少于此张数的文件夹将不生成视频】
$QUALITY    = 19 # 画质 (建议 18-22)
$FPS        = 2  # 帧率 (每秒显示几张图)
# ------------------

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$BaseDir = Get-Location

# --- 启动信息展示 ---
Write-Host "`n===========================================================" -ForegroundColor Green
Write-Host "      RTX 3080 Ti 硬件加速 (全能过滤版)          " -ForegroundColor Green
Write-Host "  起始目录: $BaseDir" -ForegroundColor Gray
Write-Host "  门槛设置: 少于 $MIN_COUNT 张图片将自动跳过" -ForegroundColor Cyan
if ($OVERWRITE -eq 1) {
    Write-Host "  运行模式: 【 强制覆盖 】" -ForegroundColor Yellow
} else {
    Write-Host "  运行模式: 【 增量跳过 】" -ForegroundColor Cyan
}
Write-Host "===========================================================" -ForegroundColor Green

Write-Host "`n>>> 正在扫描目录结构..." -ForegroundColor Cyan
$FolderPaths = cmd /c "dir /ad /s /b" 2>$null
$AllFolders = @($BaseDir) + $FolderPaths
Write-Host ">>> 共检索到 $($AllFolders.Count) 个位置，开始处理...`n" -ForegroundColor Green

foreach ($FullPath in $AllFolders) {
    if ($FullPath -match "@eaDir|\.|\#") { continue }
    
    $FolderName = Split-Path $FullPath -Leaf
    $OutputPath = Join-Path $FullPath "$FolderName.mp4"
    
    # 1. 获取图片
    $Imgs = Get-ChildItem -LiteralPath "$FullPath" -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match "jpg|jpeg|png" }

    # --- 细化跳过原因判定 ---
    
    # 情况 1: 文件夹里根本没照片
    if ($Imgs.Count -eq 0) {
        Write-Host "[跳过-无图] $FullPath" -ForegroundColor DarkGray
        continue
    }

    # 情况 2: 照片数量不足 (新增过滤逻辑)
    if ($Imgs.Count -lt $MIN_COUNT) {
        Write-Host "[跳过-量少] $FullPath (仅 $($Imgs.Count) 张)" -ForegroundColor DarkMagenta
        continue
    }

    # 情况 3: 视频已存在
    if (Test-Path -LiteralPath $OutputPath) {
        if ($OVERWRITE -eq 0) {
            Write-Host "[跳过-存在] $FullPath" -ForegroundColor Cyan
            continue
        } else {
            Write-Host "[覆盖重刷] $FullPath" -ForegroundColor Yellow
        }
    } else {
        # 情况 4: 全新合成
        Write-Host "[全新合成] $FullPath" -ForegroundColor Green
    }

    # --- 2. 动态画布计算 (Max_W x Max_H) ---
    $maxW = 0
    $maxH = 0
    foreach ($img in $Imgs) {
        $size = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$($img.FullName)"
        if ($size -match '(\d+)x(\d+)') {
            $w = [int]$matches[1]; $h = [int]$matches[2]
            if ($w -gt $maxW) { $maxW = $w }
            if ($h -gt $maxH) { $maxH = $h }
        }
    }
    # 偶数对齐
    if ($maxW % 2 -ne 0) { $maxW++ }
    if ($maxH % 2 -ne 0) { $maxH++ }
    
    Write-Host "           >> 分辨率: ${maxW}x${maxH} | 数量: $($Imgs.Count)P" -ForegroundColor Gray

    # --- 3. 排序与列表生成 ---
    $SortedImgs = $Imgs | Sort-Object { [regex]::Replace($_.Name, '\d+', { $args[0].Value.PadLeft(10, '0') }) }
    $ListFile = Join-Path $FullPath "img_list.txt"
    $ListContent = $SortedImgs | ForEach-Object { "file '$($_.Name -replace "'", "''")'" }
    $Utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($ListFile, $ListContent, $Utf8NoBom)

    # --- 4. 3080 Ti 合成逻辑 (比例保护) ---
    $vf_logic = "scale=${maxW}:${maxH}:force_original_aspect_ratio=decrease,pad=${maxW}:${maxH}:(ow-iw)/2:(oh-ih)/2,format=yuv420p"
    
    $null | & ffmpeg -y -r $FPS -f concat -safe 0 -i "$ListFile" `
        -vf "$vf_logic" `
        -c:v hevc_nvenc -preset p7 -rc vbr -cq $QUALITY -tag:v hvc1 `
        -loglevel error -stats "$OutputPath"

    if (Test-Path -LiteralPath $ListFile) { Remove-Item -LiteralPath $ListFile -Force }
}

Write-Host "`n===========================================================" -ForegroundColor Green
Write-Host "   所有任务已处理完毕！" -ForegroundColor Green
Write-Host "===========================================================" -ForegroundColor Green
Pause