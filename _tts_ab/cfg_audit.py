import os
import re
from pathlib import Path

p = Path(r"E:\GodotProjects\ai-claw-v-3\config\youyou_voice_secrets.cfg")
if not p.is_file():
    print("CFG_EXISTS=false")
    raise SystemExit(0)
print("CFG_EXISTS=true")
text = p.read_text(encoding="utf-8")
sec = None
fields = {}
for line in text.splitlines():
    line = line.strip()
    if not line or line.startswith(";"):
        continue
    m = re.match(r"\[(.+)\]", line)
    if m:
        sec = m.group(1)
        continue
    if "=" in line and sec:
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip()
        if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
            v = v[1:-1]
        fields[f"{sec}/{k}"] = v

cfg = ConfigFile = None
try:
    err_sim = 0
    for line in text.splitlines():
        if "=" in line and not line.strip().startswith(";"):
            part = line.split("=", 1)[1].strip()
            if part and part[0] not in '"0123456789-':
                if not part.startswith('"'):
                    err_sim = 1
    print("CFG_QUOTED_STRINGS_OK=", err_sim == 0)
except Exception:
    print("CFG_QUOTED_STRINGS_OK=unknown")

env_dash = bool(os.environ.get("DASHSCOPE_API_KEY", "").strip())

def row(key):
    v = fields.get(key)
    if v is None:
        return "missing", False
    if key.endswith(
        (
            "manual_token_expire_unix",
            "sample_rate",
            "volume",
            "max_token",
            "request_timeout_sec",
        )
    ):
        return "numeric", True
    if v == "":
        return "empty", True
    return "non_empty", True

groups = {
    "aliyun": [
        "aliyun/app_key",
        "aliyun/access_key_id",
        "aliyun/access_key_secret",
        "aliyun/region",
        "aliyun/sample_rate",
        "aliyun/voice",
        "aliyun/volume",
        "aliyun/manual_token",
        "aliyun/manual_token_expire_unix",
    ],
    "moonshot": [
        "moonshot/api_key",
        "moonshot/model",
        "moonshot/api_url",
        "moonshot/max_token",
    ],
    "bailian_tts": [
        "bailian_tts/endpoint_kind",
        "bailian_tts/api_key",
        "bailian_tts/workspace_base_url",
        "bailian_tts/workspace_id",
        "bailian_tts/region",
        "bailian_tts/model",
        "bailian_tts/voice",
        "bailian_tts/format",
        "bailian_tts/sample_rate",
        "bailian_tts/language_hints",
        "bailian_tts/default_instruction",
        "bailian_tts/endpoint_url_override",
        "bailian_tts/request_timeout_sec",
    ],
}
for g, keys in groups.items():
    print(f"## {g}")
    for k in keys:
        st, readable = row(k)
        print(f"{k}\t{st}\treadable={readable}")

print("env_DASHSCOPE_API_KEY", "non_empty" if env_dash else "empty")
app = fields.get("aliyun/app_key", "")
ak = fields.get("aliyun/access_key_id", "")
sk = fields.get("aliyun/access_key_secret", "")
mt = fields.get("aliyun/manual_token", "")
mk = fields.get("moonshot/api_key", "")
tk = fields.get("bailian_tts/api_key", "")
print("SUMMARY asr_app_key", "ok" if app else "missing")
print("SUMMARY asr_auth", "manual_token" if mt else ("aksk" if ak and sk else "missing"))
print("SUMMARY moonshot", "ok" if mk else "missing")
print("SUMMARY tts_key", "cfg" if tk else ("env" if env_dash else "missing"))
