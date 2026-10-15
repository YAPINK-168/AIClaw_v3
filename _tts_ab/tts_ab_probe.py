import hashlib
import json
import ssl
import struct
import urllib.request
from pathlib import Path

CFG = Path(r"E:\GodotProjects\ai-claw-v-3\config\youyou_voice_secrets.cfg")
OUT = Path(r"E:\GodotProjects\ai-claw-v-3\_tts_ab")
WS = "ws-oezduzmjp58m7g0f"
VOICE = "qwen-audio-3.0-tts-plus-vd-bailian-26d6e794c4134aa08f4d6326cc37e642"
TEXT = "你好，我是柚柚。"
TTS_URL = f"https://{WS}.cn-beijing.maas.aliyuncs.com/api/v1/services/audio/tts/SpeechSynthesizer"
CUST_URL = f"https://{WS}.cn-beijing.maas.aliyuncs.com/api/v1/services/audio/tts/customization"


def read_api_key() -> str:
    for line in CFG.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s.startswith("api_key="):
            return s.split("=", 1)[1].strip().strip('"')
    raise RuntimeError("api_key missing in cfg")


def post(url: str, payload: dict, key: str) -> bytes:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        method="POST",
    )
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, context=ctx, timeout=120) as r:
        return r.read()


def wav_info(blob: bytes) -> dict:
    if blob[:4] != b"RIFF":
        return {"err": "not riff", "size": len(blob)}
    pos = 12
    sr = ch = bits = None
    while pos + 8 <= len(blob):
        cid = blob[pos : pos + 4]
        sz = struct.unpack_from("<I", blob, pos + 4)[0]
        pos += 8
        if cid == b"fmt " and sz >= 16:
            ch = struct.unpack_from("<H", blob, pos + 2)[0]
            sr = struct.unpack_from("<I", blob, pos + 4)[0]
            bits = struct.unpack_from("<H", blob, pos + 14)[0]
        pos += sz + (sz % 2)
    return {"size": len(blob), "sample_rate": sr, "channels": ch, "bits": bits}


def download_wav(j: dict) -> bytes:
    url = j.get("output", {}).get("audio", {}).get("url", "")
    if not url:
        raise RuntimeError("no audio url: " + json.dumps(j)[:400])
    with urllib.request.urlopen(url, context=ssl.create_default_context(), timeout=120) as r:
        return r.read()


def main() -> None:
    key = read_api_key()
    OUT.mkdir(exist_ok=True)

    qv = {"model": "voice-enrollment", "input": {"action": "query_voice", "voice_id": VOICE}}
    qv_raw = post(CUST_URL, qv, key)
    qvj = json.loads(qv_raw.decode("utf-8"))
    print("query_voice_request_id=", qvj.get("request_id", ""))
    out = qvj.get("output", qvj)
    safe = {k: out.get(k) for k in ("voice_id", "status", "target_model", "gmt_create", "gmt_modified") if k in out}
    print("query_voice=", json.dumps(safe, ensure_ascii=False))

    plain_body = {
        "model": "qwen-audio-3.0-tts-plus",
        "input": {
            "text": TEXT,
            "voice": VOICE,
            "format": "wav",
            "sample_rate": 24000,
            "language_hints": ["zh"],
        },
    }
    happy_body = json.loads(json.dumps(plain_body))
    happy_body["input"]["instruction"] = "情绪：开心"

    for label, payload in [("curl_plain", plain_body), ("curl_happy_instr", happy_body)]:
        raw = post(TTS_URL, payload, key)
        j = json.loads(raw.decode("utf-8"))
        wav = download_wav(j)
        path = OUT / f"{label}.wav"
        path.write_bytes(wav)
        print(
            label,
            "request_id=",
            j.get("request_id", ""),
            "wav=",
            wav_info(wav),
            "sha256=",
            hashlib.sha256(wav).hexdigest()[:24],
        )

    godot_path = OUT / "godot_plain.wav"
    if godot_path.is_file():
        g = godot_path.read_bytes()
        print(
            "godot_plain",
            "wav=",
            wav_info(g),
            "sha256=",
            hashlib.sha256(g).hexdigest()[:24],
        )


if __name__ == "__main__":
    main()
