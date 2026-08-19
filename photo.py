from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
import html
import json
import os
import random
import re
import sys
import time
from urllib.parse import urljoin, urlparse

from bs4 import BeautifulSoup
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from curl_cffi import requests

# ================= 配置区 =================
SAVE_ROOT = "/volume3/documents/CARRIERS/China Telecom/x86/Photos/unsort"
URL_FILE = "/volume3/documents/CARRIERS/China Telecom/x86/Photos/urls.txt"
LOG_BASE_DIR = "/volume3/documents/CARRIERS/China Telecom/x86/Photos"
RAW_COOKIE = "__ss_pv_d=2026-04-20; __suvt=765d2758230e11023743ca607cbfaaad; __nuvt=29438f6e4014fb59ab053a57dacbdd2c; __ss_pv_done=1; __ss_pv_c=11; deviceType=1"
CONSECUTIVE_LIMIT = 1    # 连续 N 个相册/页面无资源判定结束
MAX_THREADS = 7
MAX_RETRIES = 15

# 域名分流配置
PRIMARY_DOMAIN = "img.xchina.io"          # 用于图片和普通直链视频
HLS_DOMAIN = "video.xchina.download"     # 专门用于 HLS (m3u8 / ts) 视频
# =========================================

session = requests.Session(impersonate="chrome120")
session.headers.update({
    "Cookie": RAW_COOKIE,
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML,"
        " like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ),
    "X-Requested-With": "XMLHttpRequest",
})


def get_corrected_url(url, is_hls=False):
    """根据资源类型智能修正域名：
    - is_hls=True 时强制替换为 HLS_DOMAIN
    - 否则替换为 PRIMARY_DOMAIN
    """
    target_domain = HLS_DOMAIN if is_hls else PRIMARY_DOMAIN
    parsed = urlparse(url)
    if parsed.netloc and parsed.netloc != target_domain:
        return url.replace(parsed.netloc, target_domain, 1)
    return url


def download_m3u8_video(m3u8_url, album_path, filename, referer):
    """带 AES-128 自动解密与详细日志的 HLS 切片多线程下载器（强制锁定 HLS 专用域名）"""
    target = os.path.join(album_path, filename)
    MIN_LIMIT = 5120

    if os.path.exists(target) and os.path.getsize(target) > MIN_LIMIT:
        print(f"    ߓ栛HLS] 目标文件已存在且校验通过，跳过下载: {filename}", flush=True)
        return "SKIP"

    # 强制将 m3u8 地址修正为 HLS 专用域名
    m3u8_url = get_corrected_url(m3u8_url, is_hls=True)

    try:
        print(f"    ߓ栛HLS 详细日志] 开始解析 m3u8 索引: {m3u8_url}", flush=True)
        base_origin = f"https://{HLS_DOMAIN}"

        headers = {
            "Referer": referer,
            "Origin": base_origin,
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                " (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ),
        }

        start_time = time.time()
        
        res = None
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                print(f"    ߓ栛HLS] 正在获取 m3u8 索引 (尝试 {attempt}/{MAX_RETRIES})...", flush=True)
                res = session.get(m3u8_url, headers=headers, timeout=15)
                if res.status_code == 200:
                    print(f"    ✅ [HLS] m3u8 索引获取成功", flush=True)
                    break
                else:
                    print(f"    ⚠️ [HLS] 获取 m3u8 索引 HTTP 状态码: {res.status_code}，准备重试...", flush=True)
            except Exception as e:
                print(f"    ⚠️ [HLS] 获取 m3u8 索引网络异常 ({e})，准备重试...", flush=True)
            time.sleep(1.5)

        if not res or res.status_code != 200:
            print(f"    ❌ [HLS] 获取 m3u8 索引彻底失败，HTTP 状态码: {res.status_code if res else 'None'}", flush=True)
            return "FAIL"

        lines = res.text.splitlines()
        ts_urls = []
        key_url = None
        iv_hex = None

        for line in lines:
            line = line.strip()
            if line.startswith("#EXT-X-KEY"):
                method_match = re.search(r"METHOD=([^,]+)", line)
                uri_match = re.search(r'URI="([^"]+)"', line)
                iv_match = re.search(r"IV=(0x[0-9a-fA-F]+)", line)

                if method_match and method_match.group(1) == "AES-128" and uri_match:
                    # 秘钥地址同样走 HLS 域名
                    key_url = get_corrected_url(urljoin(m3u8_url, uri_match.group(1)), is_hls=True)
                    if iv_match:
                        iv_hex = iv_match.group(1)
            elif line and not line.startswith("#"):
                # 切片地址走 HLS 域名
                ts_urls.append(get_corrected_url(urljoin(m3u8_url, line), is_hls=True))

        if not ts_urls:
            print("    ❌ [HLS] 未能在 m3u8 中解析到任何有效的切片(.ts)地址", flush=True)
            return "FAIL"

        aes_key = None
        if key_url:
            print(f"    ߔ᠛HLS 加密] 检测到 AES-128 加密，正在获取密钥: {key_url}", flush=True)
            for attempt in range(1, MAX_RETRIES + 1):
                try:
                    key_res = session.get(key_url, headers=headers, timeout=15)
                    if key_res.status_code == 200:
                        aes_key = key_res.content
                        print(f"    ߔ᠛HLS 加密] 密钥获取成功，长度: {len(aes_key)} 字节", flush=True)
                        break
                    else:
                        print(f"    ⚠️ [HLS 加密] 密钥获取状态码: {key_res.status_code}，重试 (尝试 {attempt}/{MAX_RETRIES})", flush=True)
                except Exception as e:
                    print(f"    ⚠️ [HLS 加密] 密钥获取网络异常 ({e})，重试 (尝试 {attempt}/{MAX_RETRIES})", flush=True)
                time.sleep(1.5)
            
            if not aes_key:
                print("    ❌ [HLS 加密] 密钥获取彻底失败", flush=True)
                return "FAIL"

        total_ts = len(ts_urls)
        print(f"    ߓ栛HLS 详情] 共解析到 {total_ts} 个视频切片，启动多线程下载...", flush=True)

        ts_buffers = [None] * total_ts

        def fetch_and_decrypt_ts(idx, url):
            t_start = time.time()
            for attempt in range(1, MAX_RETRIES + 1):
                try:
                    r = session.get(url, headers=headers, timeout=30)
                    if r.status_code == 200 and len(r.content) > 0:
                        raw_data = r.content
                        if aes_key:
                            if iv_hex:
                                iv = bytes.fromhex(iv_hex[2:])
                            else:
                                iv = idx.to_bytes(16, byteorder="big")

                            cipher = Cipher(
                                algorithms.AES(aes_key),
                                modes.CBC(iv),
                                backend=default_backend(),
                            )
                            decryptor = cipher.decryptor()
                            decrypted_data = (
                                decryptor.update(raw_data) + decryptor.finalize()
                            )

                            try:
                                unpadder = padding.PKCS7(128).unpadder()
                                decrypted_data = (
                                    unpadder.update(decrypted_data) + unpadder.finalize()
                                )
                            except Exception:
                                pass

                            data_to_write = decrypted_data
                        else:
                            data_to_write = raw_data

                        cost = time.time() - t_start
                        print(f"        [切片 {idx+1}/{total_ts}] 下载并解密成功 | 大小: {len(data_to_write)} 字节 | 耗时: {cost:.2f}s", flush=True)
                        return idx, data_to_write
                    else:
                        print(f"        ⚠️ [切片 {idx+1}/{total_ts}] 下载状态码异常: {r.status_code}，重试 (尝试 {attempt}/{MAX_RETRIES})", flush=True)
                except Exception as e:
                    print(f"        ⚠️ [切片 {idx+1}/{total_ts}] 下载异常 ({e})，重试 (尝试 {attempt}/{MAX_RETRIES})", flush=True)
                
                if attempt < MAX_RETRIES:
                    backoff_time = min(10, (1.5 ** (attempt - 1))) + random.uniform(0.3, 0.8)
                    time.sleep(backoff_time)

            print(f"        ❌ [切片 {idx+1}/{total_ts}] 达到最大重试次数 ({MAX_RETRIES})，下载失败", flush=True)
            return idx, None

        with ThreadPoolExecutor(max_workers=MAX_THREADS) as ex:
            futures = [
                ex.submit(fetch_and_decrypt_ts, i, u) for i, u in enumerate(ts_urls)
            ]
            for f in as_completed(futures):
                idx, data = f.result()
                if data:
                    ts_buffers[idx] = data

        if any(b is None for b in ts_buffers):
            missing_indices = [i for i, b in enumerate(ts_buffers) if b is None]
            print(f"    ❌ [HLS] 部分切片下载失败，缺失索引: {missing_indices}，放弃合并", flush=True)
            if os.path.exists(target):
                os.remove(target)
            return "FAIL"

        print(f"    ߓ栛HLS] 所有切片下载完成，正在合并写入文件: {target}", flush=True)
        with open(target, "wb") as f_out:
            for buf in ts_buffers:
                f_out.write(buf)

        if os.path.exists(target) and os.path.getsize(target) >= MIN_LIMIT:
            print(f"    ✅ [HLS 完成] 视频合并成功！大小: {os.path.getsize(target)/(1024*1024):.2f} MB | 总耗时: {time.time() - start_time:.2f}s", flush=True)
            return "OK"

    except Exception as e:
        print(f"    ❌ [HLS 异常] 下载流程发生错误: {e}", flush=True)

    if os.path.exists(target):
        try:
            os.remove(target)
        except Exception:
            pass
    return "FAIL"


def download_file_with_domain_switch(url, album_path, filename, referer, is_video=False):
    """支持域名锁定的下载函数（图片和普通直链视频走 PRIMARY_DOMAIN）"""
    target = os.path.join(album_path, filename)
    MIN_LIMIT = 5120

    if os.path.exists(target) and os.path.getsize(target) > MIN_LIMIT:
        print(f"    ߓ栛{ '视频' if is_video else '图片' }] 目标文件已存在且校验通过，跳过下载: {filename}", flush=True)
        return "SKIP"

    # 普通直链强制修正为 PRIMARY_DOMAIN
    corrected_url = get_corrected_url(url, is_hls=False)
    urls_to_try = [corrected_url]

    req_headers = {
        "Referer": referer if referer else f"https://{PRIMARY_DOMAIN}/",
        "Origin": f"https://{PRIMARY_DOMAIN}",
    }
    label = "视频" if is_video else "图片"

    print(f"    ߌࠛ{label} 域名锁定策略] 当前文件 '{filename}' 强制使用主节点: {PRIMARY_DOMAIN}", flush=True)

    for current_url in urls_to_try:
        current_domain = urlparse(current_url).netloc
        print(f"        ߚࠛ开始请求] 正在使用域名 [{current_domain}] 请求地址: {current_url}", flush=True)
        
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                time.sleep(random.uniform(0.3, 0.8) if is_video else 0.1)
                resp = session.get(
                    current_url, headers=req_headers, timeout=120 if is_video else 25, stream=is_video
                )

                print(f"        ߑ頛{label} 详情] 域名 [{current_domain}] 响应状态码: {resp.status_code} (尝试 {attempt}/{MAX_RETRIES})", flush=True)

                if resp.status_code == 200:
                    if is_video:
                        print(f"        ߓ堛{label}] 状态码 200，开始以流式写入视频文件: {filename}", flush=True)
                        with open(target, "wb") as f:
                            for chunk in resp.iter_content(chunk_size=128 * 1024):
                                if chunk:
                                    f.write(chunk)
                    else:
                        if len(resp.content) >= MIN_LIMIT:
                            with open(target, "wb") as f:
                                f.write(resp.content)

                    if os.path.exists(target) and os.path.getsize(target) >= MIN_LIMIT:
                        file_size = os.path.getsize(target)
                        print(f"        ✅ [{label}] 下载成功！文件名: {filename} | 最终大小: {file_size} 字节 | 使用域名: {current_domain}", flush=True)
                        return "OK"
                    else:
                        print(f"        ⚠️ [{label}] 文件大小异常或下载不完整 ({filename})，准备重试 (尝试 {attempt}/{MAX_RETRIES})", flush=True)
                        if os.path.exists(target):
                            os.remove(target)
                elif resp.status_code == 403:
                    print(f"        ❌ [{label}] 状态码 403 (拒绝访问)，该域名节点权限受限", flush=True)
                    break
                elif resp.status_code == 404:
                    print(f"        ⚠️ [{label}] 状态码 404 (资源不存在)，该域名节点无此文件", flush=True)
                    break
                else:
                    print(f"        ⚠️ [{label}] HTTP 响应状态码异常: {resp.status_code}，准备重试...", flush=True)

            except Exception as e:
                print(f"        ⚠️ [{label}] 下载网络异常 ({e})，当前域名: {current_domain}，准备重试 (尝试 {attempt}/{MAX_RETRIES})", flush=True)
                if os.path.exists(target):
                    try:
                        os.remove(target)
                    except Exception:
                        pass

            if attempt < MAX_RETRIES:
                backoff_time = min(10, (1.5 ** (attempt - 1))) + random.uniform(0.3, 0.8)
                time.sleep(backoff_time)

    print(f"        ❌ [{label}] 文件下载彻底失败: {filename}", flush=True)
    return "FAIL"


def parse_all_videos_from_html(page_url, album_id):
    """智能全量嗅探页面中的所有视频流地址（针对 HLS 自动匹配对应域名）"""
    video_tasks = []
    try:
        print(f"    ߔ视频全量嗅探] 正在请求解析相册页面: {page_url}", flush=True)
        res = session.get(page_url, timeout=20)
        print(f"    ߑ頛视频全量嗅探详情] 页面响应状态码: {res.status_code}", flush=True)
        
        if res.status_code == 200:
            html_text = html.unescape(res.text)
            clean_text = html_text.replace("\\/", "/")

            blacklist = ["placeholder", "thumb", "logo", "icon", "/photo/id-"]

            # 1. 匹配所有 m3u8 链接并使用 HLS_DOMAIN 修正
            m3u8_matches = re.findall(r'["\']([^"\']+\.m3u8(?:\?[^"\'\s]*)?)["\']', clean_text, re.IGNORECASE)
            seen_m3u8 = set()
            for link in m3u8_matches:
                if any(k in link.lower() for k in blacklist):
                    continue
                full_link = get_corrected_url(urljoin(page_url, link), is_hls=True)
                if full_link not in seen_m3u8:
                    seen_m3u8.add(full_link)
                    video_tasks.append(("m3u8", full_link))

            # 2. 匹配所有 mp4 直链并使用 PRIMARY_DOMAIN 修正
            mp4_matches = re.findall(r'["\']([^"\']+\.mp4(?:\?[^"\'\s]*)?)["\']', clean_text, re.IGNORECASE)
            seen_mp4 = set()
            for link in mp4_matches:
                if any(k in link.lower() for k in blacklist):
                    continue
                full_link = get_corrected_url(urljoin(page_url, link), is_hls=False)
                if full_link not in seen_mp4:
                    seen_mp4.add(full_link)
                    video_tasks.append(("mp4", full_link))

            # 3. 通过 BeautifulSoup 补充标签提取
            soup = BeautifulSoup(html_text, "html.parser")
            for tag in soup.find_all(["video", "source", "a"]):
                src = tag.get("src") or tag.get("data-src") or tag.get("href")
                if src and (".m3u8" in src.lower() or ".mp4" in src.lower()):
                    if any(k in src.lower() for k in blacklist):
                        continue
                    is_hls = ".m3u8" in src.lower()
                    full_link = get_corrected_url(urljoin(page_url, src), is_hls=is_hls)
                    v_type = "m3u8" if is_hls else "mp4"
                    if not any(t[1] == full_link for t in video_tasks):
                        video_tasks.append((v_type, full_link))
        else:
            print(f"    ⚠️ [视频全量嗅探] 页面请求状态码异常: {res.status_code}", flush=True)

    except Exception as e:
        print(f"    ❌ [视频全量嗅探] 解析网页视频流出现异常: {e}", flush=True)

    # 4. 安全拦截过滤
    cleaned_tasks = []
    for v_type, v_url in video_tasks:
        if "/photo/id-" in v_url.lower():
            print(f"    ߛ᯸安全拦截] 已自动过滤带有 id- 的无效视频源: {v_url}", flush=True)
            continue
        cleaned_tasks.append((v_type, v_url))
    video_tasks = cleaned_tasks

    # 5. 兜底标准 CDN 规则
    if not video_tasks and album_id != "noID":
        fallback_direct = f"https://{PRIMARY_DOMAIN}/photos/{album_id}/00001.mp4"
        print(f"    ⚠️ [视频全量嗅探] 未在页面中直接匹配到有效直链，启用标准 CDN 兜底规则", flush=True)
        video_tasks.append(("mp4", fallback_direct))

    print(f"    ߓ렛嗅探结果汇总] 共发现 {len(video_tasks)} 个有效视频直链：", flush=True)
    for idx, (v_type, v_url) in enumerate(video_tasks, start=1):
        print(f"        [{idx}] 类型: {v_type.upper()} -> 目标地址: {v_url}", flush=True)

    return video_tasks


def parse_media_url(p_url, fname):
    """解析图片真实地址（走 PRIMARY_DOMAIN）"""
    print(f"        ߖ쯸解析图片地址] 正在请求详情页: {p_url}", flush=True)
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            time.sleep(random.uniform(0.5, 1.0))
            res = session.get(p_url, timeout=25)
            print(f"        ߑ頛解析图片详情] 状态码: {res.status_code} (尝试 {attempt}/{MAX_RETRIES})", flush=True)
            if res.status_code == 200:
                soup = BeautifulSoup(res.text, "html.parser")
                for img in soup.find_all("img"):
                    for attr in ["data-original", "data-actual", "data-src", "src", "file", "zoom-file"]:
                        val = img.get(attr)
                        if val and any(ext in val.lower() for ext in [".jpg", ".jpeg", ".png", ".webp"]):
                            if any(k in val.lower() for k in ["loading", "logo", "icon", "pixel", "spacer"]):
                                continue
                            real_img_url = get_corrected_url(urljoin(p_url, val), is_hls=False)
                            print(f"        ✅ [解析图片成功] 获取到真实图片直链: {real_img_url}", flush=True)
                            return real_img_url
            else:
                print(f"        ⚠️ [解析图片] HTTP 状态码异常: {res.status_code}，准备重试...", flush=True)
        except Exception as e:
            print(f"        ⚠️ [解析图片] 网络异常 ({e})，准备重试...", flush=True)
        time.sleep(1.5)
        
    print(f"        ❌ [解析图片彻底失败]: {fname}", flush=True)
    return None


def process_album(start_url, sub_dir=""):
    stats = {"players": 0, "img_ok": 0, "video_ok": 0, "skip": 0, "fail": 0}
    try:
        album_id_match = re.search(r"id-([a-z0-9]+)", start_url)
        album_id = album_id_match.group(1) if album_id_match else "noID"

        target_root = os.path.join(SAVE_ROOT, sub_dir) if sub_dir else SAVE_ROOT
        
        res = None
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                res = session.get(start_url, timeout=20)
                if res.status_code == 200:
                    break
                else:
                    print(f"    ⚠️ [相册首页] HTTP 状态码 {res.status_code}，准备重试...", flush=True)
            except Exception as e:
                print(f"    ⚠️ [相册首页] 网络异常 ({e})，准备重试...", flush=True)
            time.sleep(1.5)
            
        if not res or res.status_code != 200:
            print(f"    ❌ [相册首页] 无法加载相册首页，跳过: {start_url}", flush=True)
            return stats

        soup = BeautifulSoup(res.text, "html.parser")
        full_title = soup.title.string if soup.title else "Album"
        raw_title = re.sub(r'[\\/:*?"<>|]', "", re.split(r"[-_|]", full_title)[0]).strip()
        unique_name = f"{raw_title} [{album_id}]"

        path = os.path.join(target_root, unique_name)
        
        if os.path.exists(target_root):
            for folder in os.listdir(target_root):
                if f"[{album_id}]" in folder and re.search(r"\[\d+P?(\+\d+V)?\]$", folder):
                    print(f"  [-] 跳过已完成相册: {folder}", flush=True)
                    return stats

        os.makedirs(path, exist_ok=True)
        print(f"    目录: {unique_name}", flush=True)

        # ===== 视频处理 =====
        if album_id != "noID":
            print(f"    ߔ视频嗅探] 开始全面检索页面中的所有视频源...", flush=True)
            all_video_sources = parse_all_videos_from_html(start_url, album_id)

            for v_idx, (v_type, v_url) in enumerate(all_video_sources, start=1):
                v_name = f"V_{v_idx:04d}.mp4"
                print(f"    ߎ젦쨤苨쬠{v_idx} 个视频 [{v_type.upper()}] -> {v_url}", flush=True)
                
                if v_type == "m3u8":
                    st = download_m3u8_video(v_url, path, v_name, start_url)
                else:
                    st = download_file_with_domain_switch(v_url, path, v_name, start_url, is_video=True)

                if st == "OK":
                    print(f"    [+] 视频下载完成: {v_name}", flush=True)
                    stats["video_ok"] += 1
                    stats["players"] += 1
                elif st == "SKIP":
                    print(f"    [-] 视频已存在，跳过: {v_name}", flush=True)
                    stats["video_ok"] += 1
                    stats["players"] += 1
                else:
                    print(f"    ❌ 视频下载失败: {v_name}", flush=True)
                    stats["fail"] += 1

        # ===== 图片下载逻辑 =====
        p_idx, p_con = 1, 0
        base_url = re.sub(r"(/\d+)?\.html$", "", start_url)
        while p_idx < 150:
            c_url = f"{base_url}/{p_idx}.html"
            p_links = []
            
            print(f"    ߔ䠛DEBUG 翻页] 正在请求第 {p_idx} 页: {c_url}", flush=True)
            
            for attempt in range(1, MAX_RETRIES + 1):
                try:
                    p_res = session.get(c_url, timeout=20)
                    print(f"    ߑ頛DEBUG 翻页详情] 第 {p_idx} 页响应状态码: {p_res.status_code} (尝试 {attempt}/{MAX_RETRIES})", flush=True)
                    
                    if p_res.status_code == 404:
                        print(f"    ߛ᠛DEBUG 翻页] 第 {p_idx} 页返回 404，停止翻页", flush=True)
                        break
                    if p_res.status_code == 200:
                        p_links = sorted(
                            list(
                                set([
                                    urljoin(c_url, a["href"])
                                    for a in BeautifulSoup(p_res.text, "html.parser").find_all("a", href=True)
                                    if "Show.html" in a["href"]
                                ])
                            )
                        )
                        if p_links:
                            print(f"    ✅ [DEBUG 翻页] 第 {p_idx} 页成功提取到 {len(p_links)} 个图片详情链接", flush=True)
                            break
                        else:
                            print(f"    ⚠️ [DEBUG 翻页] 第 {p_idx} 页状态码 200，但未匹配到任何 'Show.html' 链接，准备重试...", flush=True)
                    else:
                        print(f"    ⚠️ [翻页 {p_idx}] HTTP 状态码 {p_res.status_code}，准备重试...", flush=True)
                except Exception as e:
                    print(f"    ⚠️ [翻页 {p_idx}] 网络异常 ({e})，准备重试...", flush=True)
                
                time.sleep(1.5)

            if p_links:
                p_con = 0
                print(f"    Page {p_idx}: 发现 {len(p_links)} 张图片", flush=True)
                with ThreadPoolExecutor(max_workers=MAX_THREADS) as executor:
                    def img_worker(link, ix):
                        fn = f"P{p_idx:03d}_{ix+1:04d}.jpg"
                        target_file = os.path.join(path, fn)
                        if os.path.exists(target_file) and os.path.getsize(target_file) > 5120:
                            return "SKIP", fn
                        m_url = parse_media_url(link, fn)
                        return (download_file_with_domain_switch(m_url, path, fn, link, False), fn) if m_url else ("FAIL", fn)

                    futures = [executor.submit(img_worker, l, i) for i, l in enumerate(p_links)]
                    for f in as_completed(futures):
                        rv, fn = f.result()
                        if rv == "OK":
                            stats["img_ok"] += 1
                            print(f"        [+] 图片下载成功: {fn}", flush=True)
                        elif rv == "SKIP":
                            stats["skip"] += 1
                            print(f"        [-] 图片已存在，跳过: {fn}", flush=True)
                        else:
                            stats["fail"] += 1
                            print(f"        ❌ 图片下载失败: {fn}", flush=True)
                stats["players"] += len(p_links)
            else:
                p_con += 1
                print(f"    ⚠️ [DEBUG 翻页] 第 {p_idx} 页连续未获取到图片链接，当前连续空页计数: {p_con}", flush=True)
                
            if p_con >= CONSECUTIVE_LIMIT:
                print(f"    ߛ᠛DEBUG 翻页] 连续空页达到限制 ({CONSECUTIVE_LIMIT})，终止当前相册翻页", flush=True)
                break
            p_idx += 1

        success_total = stats["img_ok"] + stats["skip"]
        # 只要总处理数量大于 0，且图片没有严重失败，或者允许部分失败时也给尾标
        if stats["players"] > 0:
            # 只要有图片下载成功或者跳过（即图片主体顺利完成），就打上尾标
            tag = f"{success_total}P" + (f"+{stats['video_ok']}V" if stats['video_ok'] > 0 else "")
            try:
                final_name = f"{unique_name} [{tag}]"
                final_path = os.path.join(target_root, final_name)
                if not os.path.exists(final_path):
                    os.rename(path, final_path)
                print("    ✅ 相册处理完成", flush=True)
            except Exception as e:
                print(f"    ⚠️ 重命名相册文件夹失败: {e}", flush=True)
    except Exception as e:
        print(f"❌ 严重错误: {e}", flush=True)
    return stats


def get_albums_from_category(start_url):
    base_cat = re.sub(r"(/\d+)?\.html$", "", start_url)
    all_albums, cat_page, category_name = [], 1, ""
    con_page_fail = 0

    while cat_page < 100:
        cur_cat = f"{base_cat}/{cat_page}.html"
        found = []
        
        print(f"  ߔ䠛DEBUG 分类列表] 正在请求列表页 {cat_page}: {cur_cat}", flush=True)
        
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                res = session.get(cur_cat, timeout=25)
                print(f"  ߑ頛DEBUG 分类列表详情] 列表页 {cat_page} 响应状态码: {res.status_code} (尝试 {attempt}/{MAX_RETRIES})", flush=True)
                
                if res.status_code == 404:
                    print(f"  ߛ᠛DEBUG 分类列表] 列表页 {cat_page} 返回 404，停止分类加载", flush=True)
                    break
                if res.status_code == 200:
                    soup = BeautifulSoup(res.text, "html.parser")
                    if not category_name:
                        category_name = re.sub(
                            r'[\\/:*?"<>|]', "", re.split(r"[-_|第 ]", soup.title.string if soup.title else "")[0].strip()
                        )
                    links = [
                        re.sub(r"(/\d+)?\.html$", "/1.html", urljoin(cur_cat, a["href"]))
                        for a in soup.find_all("a", href=True)
                        if "/photo/id-" in a["href"]
                    ]
                    if links:
                        found = list(dict.fromkeys(links))
                        print(f"  ✅ 列表页 {cat_page}: 提取 {len(found)} 个任务", flush=True)
                        break
                    else:
                        print(f"  ⚠️ [DEBUG 分类列表] 列表页 {cat_page} 状态码 200，但未匹配到 '/photo/id-' 链接，准备重试...", flush=True)
                else:
                    print(f"  ⚠️ [分类列表页 {cat_page}] HTTP 状态码 {res.status_code}，准备重试...", flush=True)
            except Exception as e:
                print(f"  ⚠️ [分类列表页 {cat_page}] 网络异常 ({e})，准备重试...", flush=True)
            time.sleep(1.5)

        if found:
            all_albums.extend(found)
            con_page_fail = 0
            cat_page += 1
        else:
            con_page_fail += 1
            print(f"  ⚠️ [DEBUG 分类列表] 列表页 {cat_page} 失败/无数据，当前连续空页计数: {con_page_fail}", flush=True)
            if con_page_fail >= CONSECUTIVE_LIMIT:
                print(f"  ߛ᠛DEBUG 分类列表] 连续空页达到限制 ({CONSECUTIVE_LIMIT})，终止分类列表加载", flush=True)
                break
            cat_page += 1

    return category_name, all_albums


def main():
    if not os.path.exists(URL_FILE):
        print(f"❌ 找不到 URL 文件: {URL_FILE}", flush=True)
        return
    with open(URL_FILE, "r", encoding="utf-8") as f:
        seeds = [l.strip() for l in f if l.strip() and "http" in l]

    print(f"读取完成，urls.txt 中共有 {len(seeds)} 条原始任务链接\n" + "=" * 40, flush=True)

    for idx, s in enumerate(seeds, start=1):
        if "/photos/" in s:
            cat_name, albums = get_albums_from_category(s)
            print(f"分类: 【{cat_name}】 共解析出 {len(albums)} 个相册", flush=True)
            for i, url in enumerate(albums, start=1):
                print(f"\n[任务 {idx}-{i}/{len(albums)}] {url}", flush=True)
                process_album(url, sub_dir=cat_name)
        else:
            clean_s = re.sub(r"(/\d+)?\.html$", "", s)
            url = f"{clean_s}/1.html"
            print(f"\n[单任务 {idx}/{len(seeds)}] {url}", flush=True)
            process_album(url)


if __name__ == "__main__":
    main()