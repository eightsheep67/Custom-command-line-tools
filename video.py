import os
import subprocess
import json
import datetime
import sys

# ===================== 配置区 =====================
OVERWRITE_ORIGINAL = True      # 是否覆盖原文件
GPU_QUALITY = "28"            # 硬件编码质量 (3080Ti)
EXTENSIONS = ('.mp4', '.mkv', '.mov', '.avi', '.flv', '.wmv', '.ts', '.m4v')

# 记录“已扫描并确认OK”的文件数据库，永久保存
DB_FILE = "processed_database.txt"
# =================================================

def load_database():
    """加载已处理的文件数据库"""
    if not os.path.exists(DB_FILE):
        return set()
    with open(DB_FILE, "r", encoding="utf-8") as f:
        # 使用 set 提高查找速度
        return set(line.strip() for line in f if line.strip())

def save_to_database(file_path):
    """将处理成功或已达标的文件存入数据库"""
    with open(DB_FILE, "a", encoding="utf-8") as f:
        f.write(file_path + "\n")

def get_video_details(file_path):
    cmd = ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_streams', file_path]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', shell=True)
        data = json.loads(result.stdout)
        video_stream = next((s for s in data.get('streams', []) if s.get('codec_type') == 'video'), None)
        if not video_stream: return None
        return {
            "codec": video_stream.get('codec_name', '').lower(),
            "tag": video_stream.get('codec_tag_string', '').lower(),
            "is_mp4": file_path.lower().endswith('.mp4')
        }
    except: return None

def run_workflow():
    db = load_database()
    target_dir = os.getcwd()
    print(f">>> 启动增量审计模式，已记录库文件: {len(db)} 个")
    print(f">>> 根目录: {target_dir}\n")

    current_tasks = []

    # --- 阶段 1: 扫描与对比 ---
    for root, _, files in os.walk(target_dir):
        for file in files:
            if file.lower().endswith(EXTENSIONS):
                if file == DB_FILE or "_tmp_optimized" in file:
                    continue
                
                full_path = os.path.abspath(os.path.join(root, file))
                
                # 【关键改动】如果在数据库中，直接跳过
                if full_path in db:
                    # 如果你想看跳过的细节，可以取消下一行的注释
                    # print(f"[数据库命中] 跳过: {file}")
                    continue

                info = get_video_details(full_path)
                if not info: continue
                
                c_check = "☑️" if info['codec'] == 'hevc' else "❌"
                t_check = "☑️" if info['tag'] == 'hvc1' else "❌"
                m_check = "☑️" if info['is_mp4'] else "❌"
                
                mode = None
                if info['codec'] != 'hevc':
                    mode = "GPU_TRANSCODE"
                    reason = "【需转码: 非HEVC】"
                elif info['tag'] != 'hvc1' or not info['is_mp4']:
                    mode = "COPY"
                    reason = "【需封装: 标签/格式不符】"
                else:
                    # 文件已达标，虽然没处理，但也记录到数据库，下次不再扫它
                    print(f"文件达标: {full_path} (已加入数据库)")
                    save_to_database(full_path)
                    continue

                print("-" * 60)
                print(f"发现新视频: {full_path}")
                print(f"详情: 编码HEVC:{c_check} | 标签hvc1:{t_check} | 容器MP4:{m_check} => {reason}")
                current_tasks.append((mode, full_path))

    # --- 阶段 2: 处理新发现的任务 ---
    if not current_tasks:
        print("\n>>> 扫描完毕：没有发现新增或需要处理的文件。")
        return

    print(f"\n>>> 扫描完毕：共有 {len(current_tasks)} 个新任务待处理。\n")
    
    for i, (mode, input_path) in enumerate(current_tasks, 1):
        base = os.path.splitext(input_path)[0]
        temp_output = base + "_tmp_optimized.mp4"
        final_output = base + ".mp4" if OVERWRITE_ORIGINAL else base + "_optimized.mp4"
        
        print(f"[{i}/{len(current_tasks)}] 处理中: {input_path}")

        cmd = ['ffmpeg', '-y', '-hwaccel', 'cuda', '-i', input_path]
        if mode == "GPU_TRANSCODE":
            cmd += ['-c:v', 'hevc_nvenc', '-rc:v', 'vbr', '-cq:v', GPU_QUALITY, '-preset', 'p6', '-pix_fmt', 'yuv420p']
        else:
            cmd += ['-c:v', 'copy']

        cmd += ['-c:a', 'aac', '-tag:v', 'hvc1', '-movflags', '+faststart', temp_output]

        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', shell=True)
        for line in process.stdout:
            if "frame=" in line:
                print(f"\r    进度: {line.strip()[:100]}", end="", flush=True)
        process.wait()

        if process.returncode == 0:
            if OVERWRITE_ORIGINAL:
                if input_path != final_output and os.path.exists(input_path):
                    os.remove(input_path)
                os.replace(temp_output, final_output)
            else:
                os.replace(temp_output, final_output)
            
            print(f"\n    [√] 成功并记入数据库")
            # 处理成功，存入数据库，下次不再扫描
            save_to_database(input_path if OVERWRITE_ORIGINAL else final_output)
        else:
            print(f"\n    [×] 失败")

if __name__ == "__main__":
    # 环境检查
    try:
        subprocess.run(['ffmpeg', '-version'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except:
        print("未找到 FFmpeg!"); sys.exit()

    run_workflow()
    print("\n>>> 流程结束。")
    input("按回车退出...")