#!/bin/bash

# 强制进入脚本所在目录
cd "$(dirname "$0")"

# 1. 递归扫描总数 (忽略大小写)
total_files=$(find . -type f -iname "*.mp4" ! -name "*_temp.mp4" | wc -l)
current_count=0

if [ "$total_files" -eq 0 ]; then
    echo "未发现待处理文件。路径: $(pwd)"
    exit 0
fi

echo "======================================================"
echo "   群晖 8K 视频批量优化工具 (后台稳定版)"
echo "   发现待处理视频总数: $total_files"
echo "======================================================"

# 2. 递归处理
# 使用 -print0 配合 read -d '' 解决中文路径和空格问题
find . -type f -iname "*.mp4" ! -name "*_temp.mp4" -print0 | while read -d $'\0' -r file; do
    ((current_count++))
    
    echo ""
    echo "进度: [$current_count / $total_files]"
    echo "正在处理: $file"
    
    # 定义临时文件 (在原视频同目录下)
    temp_file="${file%.mp4}_temp.mp4"

    # 【关键修正】添加 -nostdin 参数防止脚本卡死
    /bin/ffmpeg -nostdin -i "$file" -c copy -map 0 -movflags +faststart -tag:v hvc1 "$temp_file" -y -stats -loglevel error

    if [ $? -eq 0 ]; then
        echo "[成功] 已完成优化，替换原文件..."
        mv "$temp_file" "$file"
    else
        echo "[错误] 处理失败，跳过: $file"
        rm -f "$temp_file"
    fi
done

echo ""
echo "🎉 全部处理完成！"
