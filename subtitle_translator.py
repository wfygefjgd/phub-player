"""Real-time subtitle translator for mpv using whisper + Google Translate"""
import json
import os
import subprocess
import tempfile
import threading
import urllib.parse
import sys

import numpy as np

FFMPEG = r"C:\Users\96335\AppData\Local\Programs\Python\Python313\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe"
PROXY = "http://127.0.0.1:10808"


def translate_en_to_zh(text):
    if not text or not text.strip():
        return text
    try:
        import curl_cffi.requests as requests
        encoded = urllib.parse.quote(text[:5000])
        url = f"https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=zh-CN&dt=t&q={encoded}"
        r = requests.get(url, impersonate="chrome",
                         proxies={"https": PROXY, "http": PROXY}, timeout=10)
        data = r.json()
        return "".join([s[0] for s in data[0] if s[0]])
    except:
        return text


class RealtimeTranslator:
    def __init__(self, ipc_path, whisper_model="tiny"):
        self.ipc_path = ipc_path
        self.running = False
        self._thread = None
        self.model = None
        self._sub_id = 0
        self._lock = threading.Lock()

    def _load_model(self):
        if self.model is None:
            from faster_whisper import WhisperModel
            self.model = WhisperModel(
                "tiny", device="cpu",
                compute_type="int8"
            )

    def _send_mpv(self, command):
        if sys.platform == "win32":
            return self._send_mpv_windows(command)
        else:
            return self._send_mpv_unix(command)

    def _send_mpv_windows(self, command):
        try:
            import ctypes
            from ctypes import wintypes
            pipe_name = r"\\.\pipe\mpv-jsonipc"
            kernel32 = ctypes.windll.kernel32
            INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value
            h = kernel32.CreateFileW(
                pipe_name,
                0xC0000000,  # GENERIC_READ | GENERIC_WRITE
                0, None, 3,  # OPEN_EXISTING
                0, None
            )
            if h == INVALID_HANDLE_VALUE:
                return None
            try:
                data = json.dumps({"command": command}).encode() + b"\n"
                written = wintypes.DWORD()
                kernel32.WriteFile(h, data, len(data), ctypes.byref(written), None)
                buf = ctypes.create_string_buffer(4096)
                read = wintypes.DWORD()
                kernel32.ReadFile(h, buf, 4096, ctypes.byref(read), None)
                resp = buf.value.decode().strip()
                for line in resp.split("\n"):
                    try:
                        return json.loads(line)
                    except:
                        continue
            finally:
                kernel32.CloseHandle(h)
        except:
            return None

    def _send_mpv_unix(self, command):
        try:
            import socket
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(1)
            s.connect(self.ipc_path)
            s.send(json.dumps({"command": command}).encode() + b"\n")
            resp = s.recv(4096)
            s.close()
            return json.loads(resp.decode().strip().split("\n")[-1])
        except:
            return None

    def start(self, stream_url):
        if self.running:
            self.stop()
        self.running = True
        self._thread = threading.Thread(
            target=self._process, args=(stream_url,), daemon=True
        )
        self._thread.start()

    def stop(self):
        self.running = False
        if self._thread:
            self._thread.join(timeout=3)
            self._thread = None

    def _process(self, stream_url):
        self._load_model()

        chunk_duration = 10
        ffmpeg_cmd = [
            FFMPEG,
            "-http_proxy", PROXY,
            "-i", stream_url,
            "-vn", "-acodec", "pcm_s16le",
            "-ar", "16000", "-ac", "1",
            "-f", "wav",
            "-",
        ]

        try:
            proc = subprocess.Popen(
                ffmpeg_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
        except:
            return

        audio_buffer = b""
        bytes_per_sec = 16000 * 2
        chunk_bytes = chunk_duration * bytes_per_sec
        my_id = None

        with self._lock:
            self._sub_id += 1
            my_id = self._sub_id

        while self.running:
            data = proc.stdout.read(4096)
            if not data:
                break
            audio_buffer += data

            while len(audio_buffer) >= chunk_bytes and self.running:
                chunk = audio_buffer[:chunk_bytes]
                audio_buffer = audio_buffer[chunk_bytes:]

                audio_np = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0

                try:
                    segments, _ = self.model.transcribe(
                        audio_np, language="en",
                        beam_size=1, vad_filter=True,
                    )
                except:
                    continue

                for seg in segments:
                    if not self.running or my_id != self._sub_id:
                        break
                    en_text = seg.text.strip()
                    if not en_text:
                        continue
                    zh_text = translate_en_to_zh(en_text)
                    self._send_mpv(
                        ["show-text", zh_text, 10000]
                    )

        proc.kill()
