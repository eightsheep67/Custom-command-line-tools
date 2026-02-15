#!/bin/bash

# 进入脚本所在目录
cd "$(dirname "$0")"

HISTORY_FILE=".processed_history.log"
touch "$HISTORY_FILE"
TEMP_LIST=".todo_list.tmp"

echo "正在扫描目录并比对历史记录..."

# 1. 扫描并将不在历史记录中的文件存入临时清单
> "$TEMP_LIST"
total_files=0

# 使用 find 直接查找并过滤
find . -type f -iname "*.mp4" ! -name "*_temp.mp4" | while read -r file; do
    if ! grep -qF "$file" "$HISTORY_FILE"; then
        echo "$file" >> "$TEMP_LIST"
    fi
done

total_files=$(wc -l < "$TEMP_LIST")

if [ "$total_files" -eq 0 ]; then
    echo "======================================================"
    echo "未发现新视频。所有视频已处理完毕。"
    echo "======================================================"
    rm -f "$TEMP_LIST"
    exit 0
fi

echo "======================================================"
echo "   群晖 8K 视频优化工具 (稳定修复版)"
echo "   待处理新视频总数: $total_files"
echo "======================================================"

# 2. 逐行读取临时清单进行处理
current_count=0
while IFS= read -r file; do
    ((current_count++))
    
    echo ""
    echo "进度: [$current_count / $total_files]"
    echo "正在处理: $file"
    
    temp_file="${file%.mp4}_temp.mp4"

    # 执行 ffmpeg 封装 (使用全路径并禁用输入流)
    /bin/ffmpeg -nostdin -i "$file" -c copy -map 0 -movflags +faststart -tag:v hvc1 "$temp_file" -y -stats -loglevel error

    if [ $? -eq 0 ]; then
        echo "[成功] 已注入 Faststart & hvc1 标签"
        mv "$temp_file" "$file"
        echo "$file" >> "$HISTORY_FILE"
    else
        echo "[错误] 处理失败: $file"
        rm -f "$temp_file"
    fi
done < "$TEMP_LIST"

# 清理临时清单
rm -f "$TEMP_LIST"

echo ""
echo "🎉 批处理完成！历史记录已同步。"
