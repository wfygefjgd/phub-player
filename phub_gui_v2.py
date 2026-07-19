"""PHUB API 图形界面 v2 - 左右分栏布局，内嵌mpv播放器"""
import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

import tkinter as tk
from tkinter import ttk, messagebox, filedialog
import asyncio
import threading
import subprocess
import json
import os
import tempfile
import urllib.parse

from phub import Client
from base_api.modules.config import config
config.proxies = {
    'https': 'http://127.0.0.1:10808',
    'http': 'http://127.0.0.1:10808'
}

MPV_PATH = r"C:\Users\96335\mpv\mpv.exe"
from subtitle_translator import RealtimeTranslator


def translate_en_to_zh(text):
    if not text or not text.strip():
        return text
    try:
        import curl_cffi.requests as requests
        encoded = urllib.parse.quote(text[:5000])
        url = f"https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=zh-CN&dt=t&q={encoded}"
        r = requests.get(url, impersonate="chrome", proxies={"https": "http://127.0.0.1:10808"}, timeout=15)
        data = r.json()
        return "".join([s[0] for s in data[0] if s[0]])
    except Exception as e:
        return f"翻译失败: {e}"


def translate_batch_zh(texts):
    if not texts:
        return []
    try:
        import curl_cffi.requests as requests
        joined = "\n".join(texts)
        encoded = urllib.parse.quote(joined[:5000])
        url = f"https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=zh-CN&dt=t&q={encoded}"
        r = requests.get(url, impersonate="chrome", proxies={"https": "http://127.0.0.1:10808"}, timeout=20)
        data = r.json()
        translated_parts = []
        for s in data[0]:
            if s[0]:
                translated_parts.append(s[0])
        full = "".join(translated_parts)
        lines = full.split("\n")
        if len(lines) >= len(texts):
            return lines[:len(texts)]
        while len(lines) < len(texts):
            lines.append(texts[len(lines)])
        return lines
    except:
        return [translate_en_to_zh(t) for t in texts]


class Toast:
    def __init__(self, root):
        self.root = root
        self.label = None

    def show(self, msg, duration=500):
        if self.label:
            self.label.destroy()
        self.label = tk.Toplevel(self.root)
        self.label.overrideredirect(True)
        self.label.attributes("-topmost", True)
        self.label.configure(bg="#333")
        x = self.root.winfo_x() + self.root.winfo_width() - 180
        y = self.root.winfo_y() + self.root.winfo_height() - 60
        self.label.geometry(f"160x35+{x}+{y}")
        tk.Label(self.label, text=msg, bg="#333", fg="#7ee787",
                 font=("Segoe UI", 10, "bold")).pack(fill="both", expand=True)
        self.root.after(duration, self._hide)

    def _hide(self):
        if self.label:
            self.label.destroy()
            self.label = None


class MpvPlayer:
    def __init__(self):
        self.proc = None
        self.playing = False
        if sys.platform == "win32":
            self._ipc_path = r"\\.\pipe\phub-mpv-ipc"
        else:
            self._ipc_path = os.path.join(tempfile.gettempdir(), "phub_mpv_ipc.sock")

    def _send(self, command):
        if not self.proc or self.proc.poll() is not None:
            return
        try:
            if sys.platform == "win32":
                import ctypes
                from ctypes import wintypes
                kernel32 = ctypes.windll.kernel32
                INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value
                h = kernel32.CreateFileW(
                    self._ipc_path, 0xC0000000, 0, None, 3, 0, None
                )
                if h == INVALID_HANDLE_VALUE:
                    return
                try:
                    data = json.dumps({"command": command}).encode() + b"\n"
                    written = wintypes.DWORD()
                    kernel32.WriteFile(h, data, len(data), ctypes.byref(written), None)
                finally:
                    kernel32.CloseHandle(h)
            else:
                import socket
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(0.3)
                s.connect(self._ipc_path)
                s.send(json.dumps({"command": command}).encode() + b"\n")
                s.close()
        except:
            pass

    def play(self, url, wid=None):
        self.stop()
        try:
            args = [
                MPV_PATH, url, "--no-terminal",
                f"--input-ipc-server={self._ipc_path}",
                "--keep-open=no", "--volume=100",
                "--http-proxy=http://127.0.0.1:10808",
                "--http-header-fields=Referer: https://www.pornhub.com/",
                "--no-input-default-bindings",
                "--input-conf=MBTN_LEFT cycle pause",
            ]
            if wid:
                args.append(f"--wid={wid}")
            else:
                args.append("--force-window")
            self.proc = subprocess.Popen(
                args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            self.playing = True
        except Exception:
            pass

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self._send(["quit"])
            try:
                self.proc.wait(timeout=0.5)
            except:
                pass
            if self.proc.poll() is None:
                self.proc.kill()
        self.proc = None
        self.playing = False

    def toggle_pause(self):
        self._send(["cycle", "pause"])

    def seek(self, pct):
        self._send(["seek", str(pct), "absolute"])

    def set_volume(self, val):
        self._send(["set_property", "volume", str(int(val))])

    def _query(self, prop):
        try:
            if sys.platform == "win32":
                import ctypes
                from ctypes import wintypes
                kernel32 = ctypes.windll.kernel32
                INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value
                h = kernel32.CreateFileW(
                    self._ipc_path,
                    0xC0000000, 0, None, 3, 0, None
                )
                if h == INVALID_HANDLE_VALUE:
                    return 0
                try:
                    data = json.dumps({"command": ["get_property", prop]}).encode() + b"\n"
                    written = wintypes.DWORD()
                    kernel32.WriteFile(h, data, len(data), ctypes.byref(written), None)
                    buf = ctypes.create_string_buffer(4096)
                    read = wintypes.DWORD()
                    kernel32.ReadFile(h, buf, 4096, ctypes.byref(read), None)
                    resp = buf.value.decode().strip()
                    for line in resp.split("\n"):
                        d = json.loads(line)
                        if d.get("data") is not None:
                            return float(d["data"])
                finally:
                    kernel32.CloseHandle(h)
            else:
                import socket
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(0.3)
                s.connect(self._ipc_path)
                s.send(json.dumps({"command": ["get_property", prop]}).encode() + b"\n")
                resp = s.recv(4096).decode().strip()
                s.close()
                for line in resp.split("\n"):
                    d = json.loads(line)
                    if d.get("data") is not None:
                        return float(d["data"])
        except:
            pass
        return 0

    def get_position(self):
        return self._query("time-pos")

    def get_duration(self):
        return self._query("duration")


class PHUBApp:
    def __init__(self, root):
        self.root = root
        self.root.title("PHUB API v5.2.0")
        self.root.geometry("1280x720")
        self.root.configure(bg="#1e1e1e")
        self.root.minsize(1000, 600)

        self._set_dark_title_bar()

        self.client = Client()
        self.toast = Toast(root)
        self.mpv = MpvPlayer()
        self.translator = RealtimeTranslator(self.mpv._ipc_path)
        self._running = True

        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TNotebook", background="#1e1e1e", borderwidth=0)
        style.configure("TNotebook.Tab", background="#2d2d2d", foreground="#aaa",
                         padding=[12, 4], font=("Segoe UI", 10))
        style.map("TNotebook.Tab",
                   background=[("selected", "#1e1e1e")],
                   foreground=[("selected", "#ff6b35")])
        style.configure("Treeview",
                         background="#1a1a1a", foreground="#ddd",
                         fieldbackground="#1a1a1a", font=("Segoe UI", 10))
        style.configure("Treeview.Heading",
                         background="#333", foreground="#ddd", font=("Segoe UI", 10, "bold"))
        style.map("Treeview", background=[("selected", "#ff6b35")], foreground=[("selected", "#fff")])
        style.configure("TFrame", background="#1e1e1e")
        style.configure("TCombobox", fieldbackground="#2d2d2d", background="#2d2d2d",
                         foreground="#fff", selectbackground="#2d2d2d")
        style.configure("TScale", background="#1e1e1e", troughcolor="#333")
        style.configure("TProgressbar", background="#ff6b35", troughcolor="#2d2d2d")
        style.configure("Horizontal.TScale", background="#1a1a1a", troughcolor="#333")

        self.main_frame = tk.Frame(root, bg="#1e1e1e")
        self.main_frame.pack(fill="both", expand=True)

        self.left_container = tk.Frame(self.main_frame, bg="#000")

        self.mpv_frame = tk.Frame(self.left_container, bg="#000")
        self.mpv_frame.pack(side="top", fill="both", expand=True)

        self.player_bar = tk.Frame(self.left_container, bg="#1a1a1a", height=40)
        self.player_bar.pack(side="bottom", fill="x")
        self.player_bar.pack_propagate(False)

        btn_frame = tk.Frame(self.player_bar, bg="#1a1a1a")
        btn_frame.pack(side="left", padx=6, pady=4)

        self.btn_close = tk.Button(btn_frame, text="\u2716", bg="#c0392b", fg="#fff", width=3,
                                   command=self._close_video, relief="flat", font=("Segoe UI", 11))
        self.btn_close.pack(side="left", padx=2)
        self.btn_play = tk.Button(btn_frame, text="\u25b6", bg="#333", fg="#fff", width=3,
                                  command=self._toggle_play, relief="flat", font=("Segoe UI", 11))
        self.btn_play.pack(side="left", padx=2)

        self.progress_canvas = tk.Canvas(self.player_bar, bg="#333", height=12,
                                          highlightthickness=0, cursor="hand2")
        self.progress_canvas.pack(side="left", fill="x", expand=True, padx=8, pady=14)
        self.progress_canvas.bind("<Button-1>", self._on_progress_click)
        self.progress_canvas.bind("<B1-Motion>", self._on_progress_drag)
        self._progress_pct = 0

        self.time_label = tk.Label(self.player_bar, text="00:00 / 00:00", bg="#1a1a1a", fg="#aaa",
                                    font=("Consolas", 9), width=14)
        self.time_label.pack(side="right", padx=(0,8))

        vol_frame = tk.Frame(self.player_bar, bg="#1a1a1a")
        vol_frame.pack(side="right", padx=4)
        tk.Label(vol_frame, text="\U0001f50a", bg="#1a1a1a", fg="#aaa",
                 font=("Segoe UI", 9)).pack(side="left")
        self.vol_canvas = tk.Canvas(vol_frame, bg="#333", width=80, height=12,
                                     highlightthickness=0, cursor="hand2")
        self.vol_canvas.pack(side="left", padx=4, pady=14)
        self.vol_canvas.bind("<Button-1>", self._on_vol_click)
        self.vol_canvas.bind("<B1-Motion>", self._on_vol_drag)
        self._vol_pct = 100

        self.sep = tk.Frame(self.main_frame, bg="#444", width=2)

        self.right_panel = tk.Frame(self.main_frame, bg="#1e1e1e")
        self.right_panel.pack(side="right", fill="both", expand=True)

        nb = ttk.Notebook(self.right_panel)
        nb.pack(fill="both", expand=True, padx=8, pady=8)

        f1 = ttk.Frame(nb); nb.add(f1, text="  推荐  "); self._build_recommend(f1)
        f2 = ttk.Frame(nb); nb.add(f2, text="  搜索  "); self._build_search(f2)
        f3 = ttk.Frame(nb); nb.add(f3, text="  详情  "); self._build_detail(f3)
        f4 = ttk.Frame(nb); nb.add(f4, text="  下载  "); self._build_download(f4)

        self.status_lbl = tk.Label(self.right_panel, text="就绪", bg="#1e1e1e", fg="#888",
                                    font=("Segoe UI", 9), anchor="w")
        self.status_lbl.pack(fill="x", padx=10, pady=(0, 5))

        self._video_playing = False
        self.mpv_frame.update_idletasks()
        self._mpv_wid = self.mpv_frame.winfo_id()

        self._loop = asyncio.new_event_loop()
        threading.Thread(target=self._run_loop, daemon=True).start()
        self._start_progress_loop()
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        self.root.bind("<Key>", self._on_key)
        self.root.focus_set()
        self._keep_focus()
        self.root.after(500, self.do_recommend)

    def _on_key(self, e):
        if e.keysym == "Left":
            self._seek_relative(-15)
        elif e.keysym == "Right":
            self._seek_relative(15)
        elif e.keysym == "Escape":
            self._close_video()
        elif e.keysym == "space":
            self._toggle_play()

    def _keep_focus(self):
        if self._running and self._video_playing:
            self.root.focus_force()
        if self._running:
            self.root.after(500, self._keep_focus)

    def _seek_relative(self, secs):
        if self._video_playing:
            self.mpv._send(["seek", str(secs), "relative"])

    def _set_dark_title_bar(self):
        def _apply():
            import ctypes
            hwnd = ctypes.windll.user32.GetAncestor(self.root.winfo_id(), 2)
            if not hwnd:
                return
            DWMWA_USE_IMMERSIVE_DARK_MODE = 20
            val = ctypes.c_int(1)
            ctypes.windll.dwmapi.DwmSetWindowAttribute(
                hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE,
                ctypes.byref(val), ctypes.sizeof(val)
            )
            DWMWA_CAPTION_COLOR = 35
            color = ctypes.c_int(0x1E1E1E)
            ctypes.windll.dwmapi.DwmSetWindowAttribute(
                hwnd, DWMWA_CAPTION_COLOR,
                ctypes.byref(color), ctypes.sizeof(color)
            )
        self.root.after(100, _apply)

    def _on_close(self):
        self._running = False
        self.translator.stop()
        self.mpv.stop()
        self.root.destroy()

    def _toggle_play(self):
        if self.mpv.playing:
            self.mpv.toggle_pause()
            if self.btn_play.cget("text") == "\u25b6":
                self.btn_play.config(text="\u23f8")
            else:
                self.btn_play.config(text="\u25b6")

    def _stop_play(self):
        self.mpv.stop()
        self.btn_play.config(text="\u25b6")
        self._progress_pct = 0
        self._draw_progress()
        self.time_label.config(text="00:00 / 00:00")

    def _show_player(self):
        if self._video_playing:
            return
        self._video_playing = True
        self.right_panel.pack_forget()
        self.sep.pack(side="left", fill="y")
        self.left_container.pack(side="left", fill="both", expand=True)
        self.mpv_frame.update_idletasks()
        self._mpv_wid = self.mpv_frame.winfo_id()
        self._draw_progress()
        self._draw_vol()

    def _close_video(self):
        self._video_playing = False
        self.mpv.stop()
        self.btn_play.config(text="\u25b6")
        self._progress_pct = 0
        self.time_label.config(text="00:00 / 00:00")
        self.left_container.pack_forget()
        self.sep.pack_forget()
        self.right_panel.pack(side="right", fill="both", expand=True)

    def _draw_progress(self):
        self.progress_canvas.delete("all")
        w = self.progress_canvas.winfo_width()
        h = self.progress_canvas.winfo_height()
        self.progress_canvas.create_rectangle(0, 0, w, h, fill="#333", outline="")
        filled = w * self._progress_pct / 100
        self.progress_canvas.create_rectangle(0, 0, filled, h, fill="#ff6b35", outline="")

    def _on_progress_click(self, e):
        w = self.progress_canvas.winfo_width()
        if w > 0:
            pct = e.x / w * 100
            dur = self.mpv.get_duration()
            if dur > 0:
                self.mpv.seek(pct / 100 * dur)

    def _on_progress_drag(self, e):
        self._on_progress_click(e)

    def _draw_vol(self):
        self.vol_canvas.delete("all")
        w = self.vol_canvas.winfo_width()
        h = self.vol_canvas.winfo_height()
        self.vol_canvas.create_rectangle(0, 0, w, h, fill="#333", outline="")
        filled = w * self._vol_pct / 100
        self.vol_canvas.create_rectangle(0, 0, filled, h, fill="#888", outline="")

    def _on_vol_click(self, e):
        w = self.vol_canvas.winfo_width()
        if w > 0:
            self._vol_pct = max(0, min(100, e.x / w * 100))
            self.mpv.set_volume(self._vol_pct)
            self._draw_vol()

    def _on_vol_drag(self, e):
        self._on_vol_click(e)

    def _start_progress_loop(self):
        self._mpv_duration_override = 0
        def _update():
            if not self._running:
                return
            if self._video_playing and self.mpv.playing and self.mpv.proc and self.mpv.proc.poll() is None:
                pos = self.mpv.get_position()
                dur = self.mpv.get_duration()
                if pos > 0 and dur > 0 and dur < 120 and pos > dur:
                    self._mpv_duration_override = max(self._mpv_duration_override, dur)
                    dur = 0
                if dur > 0:
                    self._mpv_duration_override = 0
                    self._progress_pct = pos / dur * 100 if dur > 0 else 0
                    self._draw_progress()
                    self.time_label.config(text=f"{self._fmt(pos*1000)} / {self._fmt(dur*1000)}")
                else:
                    self._progress_pct = 0
                    self._draw_progress()
                    self.time_label.config(text=f"{self._fmt(pos*1000)} / --:--")
                if self.btn_play.cget("text") != "\u23f8" and pos > 0:
                    self.btn_play.config(text="\u23f8")
            self.root.after(500, _update)
        self.root.after(1000, _update)

    def _run_loop(self):
        asyncio.set_event_loop(self._loop)
        self._loop.run_forever()

    @staticmethod
    def _fmt(ms):
        s = int(ms / 1000); m, s = divmod(s, 60); h, m = divmod(m, 60)
        return f"{h}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"

    def _toggle_subtitle(self):
        if self.translator.running:
            self.translator.stop()
            self.sub_btn.config(text="实时字幕: 关", bg="#444", fg="#aaa")
            self.toast.show("字幕已关闭")
        else:
            self._current_stream = getattr(self, '_current_stream', None)
            if self._current_stream:
                self.translator.stop()
                self.translator.start(self._current_stream)
                self.sub_btn.config(text="实时字幕: 开", bg="#238636", fg="#fff")
                self.toast.show("字幕已开启")
            else:
                self.toast.show("请先播放视频")

    def _copy_url(self, url):
        self.root.clipboard_clear()
        self.root.clipboard_append(url)
        self.toast.show("已复制")

    def _bind_menu(self, tree):
        def on_rc(e):
            item = tree.identify_row(e.y)
            if item:
                tree.selection_set(item)
                url = tree.item(item)["values"][-1]
                m = tk.Menu(tree, tearoff=0, bg="#2d2d2d", fg="#fff",
                            activebackground="#ff6b35", font=("Segoe UI",10))
                m.add_command(label="复制链接", command=lambda: self._copy_url(url))
                m.tk_popup(e.x_root, e.y_root)
        tree.bind("<Button-3>", on_rc)

    def run_async(self, coro, cb=None):
        self._loop.call_soon_threadsafe(asyncio.ensure_future, self._wrap(coro, cb))

    def _wrap(self, coro, cb):
        async def t():
            try:
                r = await coro
                if cb: self.root.after(0, cb, r)
            except Exception as e:
                self.root.after(0, lambda: messagebox.showerror("错误", str(e)))
        return t()

    def _parse_m3u8(self, text):
        lines = text.strip().split("\n")
        streams = []
        for i, line in enumerate(lines):
            if line.startswith("#EXT-X-STREAM-INF:"):
                try:
                    w = int(line.split("RESOLUTION=")[1].split("x")[0].split(",")[0])
                except:
                    w = 0
                if w > 0 and i+1 < len(lines):
                    url = lines[i+1].strip()
                    streams.append((w, url))
        if not streams:
            return text.strip().split("\n")[-1].strip() if text.strip() else None
        streams.sort(key=lambda x: x[0], reverse=True)
        return streams[0][1]

    def _resolve_m3u8(self, m3u8_text):
        import m3u8 as _m3u8
        import curl_cffi.requests as _req
        proxy = {"http": "http://127.0.0.1:10808", "https": "http://127.0.0.1:10808"}
        session = _req.Session(impersonate="chrome", proxies=proxy)
        headers = {"Referer": "https://www.pornhub.com/"}
        try:
            master = _m3u8.loads(m3u8_text)
        except Exception:
            return None
        if not master.playlists:
            return None
        sorted_pls = sorted(master.playlists,
            key=lambda p: (p.stream_info.resolution[0] if p.stream_info.resolution else 0))
        for pl in reversed(sorted_pls):
            try:
                current_url = pl.absolute_uri
                for _ in range(5):
                    r = session.get(current_url, headers=headers, timeout=10)
                    if r.status_code != 200:
                        break
                    parsed = _m3u8.loads(r.text)
                    if parsed.is_variant and parsed.playlists:
                        best_sub = max(parsed.playlists,
                            key=lambda p: (p.stream_info.resolution[0] if p.stream_info.resolution else 0))
                        current_url = _m3u8.urljoin(current_url, best_sub.uri)
                    else:
                        seg_count = len(parsed.segments)
                        if seg_count >= 3:
                            return current_url
                        break
            except Exception:
                continue
        return None

    def _play_by_url(self, url, title, status_lbl):
        async def f():
            v = await self.client.get_video(url)
            await v.ensure_html()
            stream = self._resolve_m3u8(v.m3u8_base_url)
            return (stream, v.title, url)
        def done(r):
            stream, vtitle, vurl = r
            if stream:
                t = title or vtitle
                status_lbl.config(text=f"播放中: {t}")
                self.status_lbl.config(text=f"播放: {t}")
                self._current_stream = stream
                self._show_player()
                self.btn_play.config(text="\u23f8")
                self.mpv.play(stream, wid=self._mpv_wid)
                if self.translator.running:
                    self.translator.stop()
                    self.translator.start(stream)
            else:
                messagebox.showerror("错误", "无法获取播放地址")
        self.run_async(f(), done)

    def _build_search(self, p):
        top = tk.Frame(p, bg="#1e1e1e"); top.pack(fill="x", padx=10, pady=(10,5))
        tk.Label(top, text="关键词:", bg="#1e1e1e", fg="#ddd").pack(side="left")
        self.s_entry = tk.Entry(top, width=40, bg="#2d2d2d", fg="#fff", insertbackground="#fff", font=("Segoe UI",10))
        self.s_entry.pack(side="left", padx=5)
        self.s_entry.bind("<Return>", lambda e: self.do_search())
        tk.Label(top, text="数量:", bg="#1e1e1e", fg="#ddd").pack(side="left", padx=(15,0))
        self.s_cnt = ttk.Combobox(top, values=["5","10","20","50"], width=5); self.s_cnt.set("10")
        self.s_cnt.pack(side="left", padx=5)
        tk.Button(top, text="搜索", bg="#ff6b35", fg="#fff", font=("Segoe UI",10,"bold"),
                  command=self.do_search, relief="flat", padx=15).pack(side="left", padx=10)
        cols = ("title","duration","url")
        tf = tk.Frame(p, bg="#1a1a1a"); tf.pack(fill="both", expand=True, padx=10, pady=5)
        self.s_tree = ttk.Treeview(tf, columns=cols, show="headings", height=18)
        self.s_tree.heading("title",text="标题"); self.s_tree.heading("duration",text="时长"); self.s_tree.heading("url",text="链接")
        self.s_tree.column("title",width=480); self.s_tree.column("duration",width=80,anchor="center"); self.s_tree.column("url",width=300)
        self.s_tree.pack(side="left",fill="both",expand=True)
        sc = ttk.Scrollbar(tf, orient="vertical", command=self.s_tree.yview); self.s_tree.configure(yscrollcommand=sc.set); sc.pack(side="right",fill="y")
        self.s_tree.bind("<Double-1>", lambda e: self._on_dblclick(self.s_tree, 2, 0, self.s_lbl))
        self._bind_menu(self.s_tree)
        self.s_lbl = tk.Label(p, text="右键复制 | 双击播放", bg="#1e1e1e", fg="#888")
        self.s_lbl.pack(fill="x", padx=10, pady=(0,5))

    def do_search(self):
        q = self.s_entry.get().strip()
        if not q: return
        n = int(self.s_cnt.get()); self.s_lbl.config(text="搜索中..."); self.s_tree.delete(*self.s_tree.get_children())
        async def f():
            r = []
            async for v in self.client.search_videos(q):
                r.append(v)
                if len(r) >= n: break
            return r
        def done(vs):
            for v in vs:
                m,s = divmod(v.duration,60)
                self.s_tree.insert("","end",values=(v.title,f"{m}:{s:02d}",v.url))
            self.s_lbl.config(text=f"找到 {len(vs)} 个 | 翻译中...")
            threading.Thread(target=self._translate_search_tree, args=(vs,), daemon=True).start()
        self.run_async(f(), done)

    def _translate_search_tree(self, vs):
        titles = [v.title for v in vs]
        translated = translate_batch_zh(titles)
        self.root.after(0, lambda: self._apply_search_translations(vs, translated))

    def _apply_search_translations(self, vs, translated):
        items = self.s_tree.get_children()
        for i, (item, zh) in enumerate(zip(items, translated)):
            if i < len(vs):
                m,s = divmod(vs[i].duration,60)
                self.s_tree.item(item, values=(zh, f"{m}:{s:02d}", vs[i].url))
        self.s_lbl.config(text=f"找到 {len(vs)} 个")

    def _build_recommend(self, p):
        top = tk.Frame(p, bg="#1e1e1e"); top.pack(fill="x", padx=10, pady=(10,5))
        tk.Label(top, text="Cookie:", bg="#1e1e1e", fg="#ddd").pack(side="left")
        self.r_cookie = tk.Entry(top, width=50, bg="#2d2d2d", fg="#fff", insertbackground="#fff", font=("Segoe UI",10))
        self.r_cookie.pack(side="left", padx=5)
        tk.Button(top, text="获取推荐", bg="#ff6b35", fg="#fff", font=("Segoe UI",9,"bold"),
                  command=self.do_recommend, relief="flat", padx=10).pack(side="left", padx=10)
        tk.Label(top, text="(可选，留空=匿名)", bg="#1e1e1e", fg="#666").pack(side="left")
        cols = ("title","duration","url")
        self.r_tree = ttk.Treeview(p, columns=cols, show="headings", height=18)
        self.r_tree.heading("title",text="标题"); self.r_tree.heading("duration",text="时长"); self.r_tree.heading("url",text="链接")
        self.r_tree.column("title",width=480); self.r_tree.column("duration",width=80,anchor="center"); self.r_tree.column("url",width=300)
        self.r_tree.pack(fill="both",expand=True,padx=10,pady=5)
        self.r_tree.bind("<Double-1>", lambda e: self._on_dblclick(self.r_tree, 2, 0, self.r_lbl))
        self._bind_menu(self.r_tree)
        self.r_lbl = tk.Label(p, text="填入浏览器Cookie可获取个性化推荐", bg="#1e1e1e", fg="#888"); self.r_lbl.pack(fill="x", padx=10, pady=(0,5))

    def do_recommend(self):
        self.r_lbl.config(text="加载中..."); self.r_tree.delete(*self.r_tree.get_children())
        cookie = self.r_cookie.get().strip()
        threading.Thread(target=self._fetch_recommend, args=(cookie,), daemon=True).start()

    def _fetch_recommend(self, cookie):
        import re as _re
        import random as _rnd
        import curl_cffi.requests as requests
        try:
            proxies = {"https": "http://127.0.0.1:10808", "http": "http://127.0.0.1:10808"}
            session = requests.Session(impersonate="chrome", proxies=proxies)
            headers = {}
            if cookie:
                headers["Cookie"] = cookie
            urls = [
                "https://www.pornhub.com/",
                "https://www.pornhub.com/video?o=ht",
                "https://www.pornhub.com/video?o=cm",
                "https://www.pornhub.com/video?o=md",
                "https://www.pornhub.com/video?o=tr",
                "https://www.pornhub.com/video?o=vi",
                "https://www.pornhub.com/video?o=pg",
            ]
            _rnd.shuffle(urls)
            urls = urls[:5]
            seen = set()
            results = []
            for u in urls:
                try:
                    r = session.get(u, headers=headers, timeout=15)
                    if r.status_code != 200:
                        continue
                    chunks = _re.split(r'(?=<a\s+[^>]*class="[^"]*linkVideoThumb)', r.text)
                    for chunk in chunks[1:]:
                        vk_m = _re.search(r'viewkey=([a-f0-9]+)', chunk)
                        title_m = _re.search(r'title="([^"]{5,})"', chunk)
                        dur_m = _re.search(r'class="[^"]*duration[^"]*"[^>]*>\s*(\d+:\d+(?::\d+)?)\s*<', chunk)
                        if not dur_m:
                            dur_m = _re.search(r'class="[^"]*dur[^"]*"[^>]*>\s*(\d+:\d+(?::\d+)?)\s*<', chunk)
                        if vk_m and title_m:
                            vk = vk_m.group(1)
                            if vk not in seen:
                                seen.add(vk)
                                title = title_m.group(1).replace("&#039;", "'").replace("&amp;", "&")
                                dur = dur_m.group(1).strip() if dur_m else "-"
                                if dur != "-":
                                    try:
                                        parts = dur.split(":")
                                        secs = int(parts[0]) * 60 + int(parts[1]) if len(parts) == 2 else int(parts[0])
                                        if secs < 30:
                                            continue
                                    except:
                                        pass
                                url = f"https://www.pornhub.com/view_video.php?viewkey={vk}"
                                results.append((title, dur, url))
                except:
                    continue
                if len(results) >= 40:
                    break
            _rnd.shuffle(results)
            results = results[:30]
            self.root.after(0, lambda: self._fill_recommend(results))
        except Exception as e:
            self.root.after(0, lambda: self.r_lbl.config(text=f"加载失败: {e}"))

    def _fill_recommend(self, results):
        for title, dur, url in results:
            self.r_tree.insert("", "end", values=(title, dur, url))
        self.r_lbl.config(text=f"推荐 {len(results)} 个 | 翻译中...")
        threading.Thread(target=self._translate_recommend_tree, args=(results,), daemon=True).start()

    def _translate_recommend_tree(self, results):
        titles = [title for title, dur, url in results]
        translated = translate_batch_zh(titles)
        self.root.after(0, lambda: self._apply_recommend_translations(results, translated))

    def _apply_recommend_translations(self, results, translated):
        items = self.r_tree.get_children()
        for i, (item, zh) in enumerate(zip(items, translated)):
            if i < len(results):
                self.r_tree.item(item, values=(zh, results[i][1], results[i][2]))
        self.r_lbl.config(text=f"推荐 {len(results)} 个")

    def _build_detail(self, p):
        top = tk.Frame(p, bg="#1e1e1e"); top.pack(fill="x", padx=10, pady=(10,5))
        tk.Label(top, text="链接:", bg="#1e1e1e", fg="#ddd").pack(side="left")
        self.d_entry = tk.Entry(top, width=50, bg="#2d2d2d", fg="#fff", insertbackground="#fff", font=("Segoe UI",10))
        self.d_entry.pack(side="left", padx=5)
        tk.Button(top, text="获取", bg="#ff6b35", fg="#fff", font=("Segoe UI",9,"bold"),
                  command=self.do_detail, relief="flat", padx=10).pack(side="left", padx=5)
        tk.Button(top, text="播放", bg="#238636", fg="#fff",
                  command=lambda: self._play_by_url(self.d_entry.get().strip(),"",self.d_lbl), relief="flat", padx=10).pack(side="left", padx=5)
        tk.Button(top, text="翻译", bg="#1f6feb", fg="#fff",
                  command=self.do_translate, relief="flat", padx=10).pack(side="left", padx=5)
        tk.Button(top, text="下载", bg="#444", fg="#fff",
                  command=lambda: (self.dl_entry.delete(0,"end"), self.dl_entry.insert(0, self.d_entry.get().strip())), relief="flat", padx=10).pack(side="left", padx=5)
        self.sub_btn = tk.Button(top, text="实时字幕: 关", bg="#444", fg="#aaa",
                  command=self._toggle_subtitle, relief="flat", padx=8)
        self.sub_btn.pack(side="left", padx=5)

        df = tk.Frame(p, bg="#1e1e1e"); df.pack(fill="both", expand=True, padx=10, pady=5)
        self.d_text = tk.Text(df, bg="#1a1a1a", fg="#ddd", font=("Consolas",10), insertbackground="#fff", wrap="word", state="disabled")
        self.d_text.pack(side="left", fill="both", expand=True)
        ds = ttk.Scrollbar(df, orient="vertical", command=self.d_text.yview); self.d_text.configure(yscrollcommand=ds.set); ds.pack(side="right",fill="y")

        tk.Label(p, text="中文翻译:", bg="#1e1e1e", fg="#ff6b35", font=("Segoe UI",9,"bold")).pack(fill="x", padx=10, pady=(5,0))
        self.d_lbl = tk.Label(p, text="", bg="#1e1e1e", fg="#888"); self.d_lbl.pack(fill="x", padx=10)

    def do_detail(self):
        url = self.d_entry.get().strip()
        if not url: return
        async def f():
            v = await self.client.get_video(url)
            tags = ", ".join(v.tags) if isinstance(v.tags, list) else v.tags
            cats = ", ".join(v.categories) if isinstance(v.categories, list) else v.categories
            return "\n".join([
                f"标题:      {v.title}", f"时长:      {v.duration}秒",
                f"播放:      {v.views}", f"点赞:      {v.likes}",
                f"评分:      {v.rating_percent}%", f"HD:        {v.is_hd}", f"VR:        {v.is_vr}",
                f"发布时间:  {v.publish_date}", f"标签:      {tags}", f"分类:      {cats}",
            ])
        def done(t):
            self.d_text.config(state="normal"); self.d_text.delete("1.0","end")
            self.d_text.insert("1.0",t); self.d_text.config(state="disabled")
        self.run_async(f(), done)

    def do_translate(self):
        self.d_text.config(state="normal")
        text = self.d_text.get("1.0","end").strip()
        self.d_text.config(state="disabled")
        if not text: return
        self.d_text.config(state="normal"); self.d_text.delete("1.0","end")
        self.d_text.insert("1.0","翻译中..."); self.d_text.config(state="disabled")
        def done(r):
            self.d_text.config(state="normal"); self.d_text.delete("1.0","end")
            self.d_text.insert("1.0",r); self.d_text.config(state="disabled")
        threading.Thread(target=lambda: self.root.after(0, done, translate_en_to_zh(text)), daemon=True).start()

    def _build_download(self, p):
        top = tk.Frame(p, bg="#1e1e1e"); top.pack(fill="x", padx=10, pady=(10,5))
        tk.Label(top, text="链接:", bg="#1e1e1e", fg="#ddd").pack(side="left")
        self.dl_entry = tk.Entry(top, width=40, bg="#2d2d2d", fg="#fff", insertbackground="#fff", font=("Segoe UI",10))
        self.dl_entry.pack(side="left", padx=5)
        tk.Label(top, text="画质:", bg="#1e1e1e", fg="#ddd").pack(side="left", padx=(15,0))
        self.dl_q = ttk.Combobox(top, values=["best","worst","half","240","480","720","1080"], width=8)
        self.dl_q.set("best"); self.dl_q.pack(side="left", padx=5)
        tk.Button(top, text="选择路径", bg="#444", fg="#fff",
                  command=self._choose_path, relief="flat", padx=8).pack(side="left", padx=5)
        tk.Button(top, text="下载", bg="#238636", fg="#fff", font=("Segoe UI",9,"bold"),
                  command=self.do_download, relief="flat", padx=15).pack(side="left", padx=5)
        self.dl_plbl = tk.Label(p, text="保存路径: 当前目录", bg="#1e1e1e", fg="#aaa")
        self.dl_plbl.pack(fill="x", padx=10, pady=3)
        self.dl_prog = ttk.Progressbar(p, mode="determinate")
        self.dl_prog.pack(fill="x", padx=10, pady=3)
        self.dl_slbl = tk.Label(p, text="就绪", bg="#1e1e1e", fg="#888")
        self.dl_slbl.pack(fill="x", padx=10)
        self.dl_log = tk.Text(p, bg="#1a1a1a", fg="#98c379", font=("Consolas",9), height=14, state="disabled", wrap="word")
        self.dl_log.pack(fill="both",expand=True,padx=10,pady=5)
        self.save_path = "./"

    def _choose_path(self):
        d = filedialog.askdirectory()
        if d: self.save_path = d; self.dl_plbl.config(text=f"保存路径: {d}")

    def do_download(self):
        url = self.dl_entry.get().strip()
        if not url: return
        q = self.dl_q.get()
        self.dl_log.config(state="normal"); self.dl_log.delete("1.0","end"); self._log("下载中..."); self.dl_prog["value"]=0
        def prog(pos,total):
            pct = int(pos/total*100) if total else 0
            self.root.after(0, lambda: self.dl_prog.configure(value=pct))
            self.root.after(0, lambda: self.dl_slbl.config(text=f"下载中... {pct}%"))
        async def f():
            v = await self.client.get_video(url)
            self.root.after(0, lambda: self._log(f"标题: {v.title}"))
            await v.ensure_html()
            await v.download(quality=q, path=self.save_path, callback=prog)
            return v.title
        def done(t):
            self._log(f"完成: {t}"); self.dl_prog["value"]=100; self.dl_slbl.config(text="完成")
            messagebox.showinfo("完成", f"下载完成!\n{t}")
        self.run_async(f(), done)

    def _log(self, msg):
        self.dl_log.config(state="normal"); self.dl_log.insert("end",msg+"\n")
        self.dl_log.see("end"); self.dl_log.config(state="disabled")

    def _on_dblclick(self, tree, url_idx, title_idx, status_lbl):
        sel = tree.selection()
        if not sel: return
        vals = tree.item(sel[0])["values"]
        url = vals[url_idx]; title = vals[title_idx]
        status_lbl.config(text=f"加载中: {title}...")
        self._play_by_url(url, title, status_lbl)


if __name__ == "__main__":
    try:
        root = tk.Tk()
        PHUBApp(root)
        root.mainloop()
    except Exception:
        import traceback
        log_path = os.path.join(os.path.expanduser("~"), "Documents", "Default Project", "error.log")
        with open(log_path, "w", encoding="utf-8") as f:
            traceback.print_exc(file=f)
