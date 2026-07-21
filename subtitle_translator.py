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
        url = f"https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=zh-CN&dt=t&q={encoded}"
        r = requests.get(url, impersonate="chrome",
                         proxies={"https": PROXY, "http": PROXY}, timeout=10)
        data = r.json()
        return "".join([s[0] for s in data[0] if s[0]])
    except:
        return text


class RealtimeTranslator:
    def __init__(self, callback=None, whisper_model="tiny"):
        # callback(zh_text) is invoked for each translated chunk (GUI display).
        self.callback = callback
        self.running = False
        self._thread = None
        self.model = None
        self._sub_id = 0
        self._lock = threading.Lock()
        self._srt_path = None
        self._srt_entries = []  # (index, start_sec, end_sec, text)

    def _load_model(self):
        if self.model is None:
            from faster_whisper import WhisperModel
            self.model = WhisperModel(
                "tiny", device="cpu",
                compute_type="int8"
            )

    def set_srt_path(self, path):
        self._srt_path = path
        self._srt_entries = []
        if path and os.path.exists(path):
            try:
                os.remove(path)
            except:
                pass

    def _write_srt(self):
        if not self._srt_path:
            return
        try:
            def fmt(t):
                h, m, s = int(t // 3600), int((t % 3600) // 60), t % 60
                return f"{h:02d}:{m:02d}:{s:06.3f}".replace(".", ",")
            lines = []
            for i, (idx, a, b, txt) in enumerate(self._srt_entries, 1):
                lines.append(str(i))
                lines.append(f"{fmt(a)} --> {fmt(b)}")
                lines.append(txt)
                lines.append("")
            with open(self._srt_path, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))
        except:
            pass

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
        is_local_stream = stream_url.startswith("http://127.0.0.1:") or stream_url.startswith("http://localhost:")
        ffmpeg_cmd = [
            FFMPEG,
        ]
        if not is_local_stream:
            ffmpeg_cmd.extend(["-http_proxy", PROXY])
        ffmpeg_cmd.extend([
            "-i", stream_url,
            "-vn", "-acodec", "pcm_s16le",
            "-ar", "16000", "-ac", "1",
            "-f", "wav",
            "-",
        ])

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
        chunk_idx = 0
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
                chunk_idx += 1
                start_sec = (chunk_idx - 1) * chunk_duration
                end_sec = chunk_idx * chunk_duration

                audio_np = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0

                try:
                    segments, _ = self.model.transcribe(
                        audio_np,
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
                    if self.callback:
                        try:
                            self.callback(zh_text)
                        except:
                            pass
                    if self._srt_path:
                        with self._lock:
                            self._srt_entries.append(
                                (chunk_idx, start_sec, end_sec, zh_text))
                        self._write_srt()

        proc.kill()
