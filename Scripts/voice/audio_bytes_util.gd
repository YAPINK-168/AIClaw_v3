class_name AudioBytesUtil
extends RefCounted

## 从 HTTP 下载的原始字节识别格式并构造 Godot AudioStream（不依赖扩展名）。


static func detect_format(data: PackedByteArray) -> String:
	if data.size() < 4:
		return "unknown"
	if data[0] == 0x52 and data[1] == 0x49 and data[2] == 0x46 and data[3] == 0x46:
		return "wav"
	if data[0] == 0x49 and data[1] == 0x44 and data[2] == 0x33:
		return "mp3"
	if data[0] == 0xFF and (data[1] & 0xE0) == 0xE0:
		return "mp3"
	return "unknown"


static func stream_from_bytes(data: PackedByteArray) -> AudioStream:
	if data.is_empty():
		return null
	var kind := detect_format(data)
	match kind:
		"wav":
			var parsed := _wav_pcm_stream(data)
			if parsed != null:
				return parsed
			return _wav_from_pcm_payload(data)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = data
			mp3.loop = false
			return mp3
		_:
			push_error("AudioBytesUtil: 无法识别音频格式 (bytes=%d)" % data.size())
			return null


static func estimate_duration_sec(stream: AudioStream) -> float:
	if stream == null:
		return 0.0
	if stream.has_method("get_length"):
		var len: float = stream.get_length()
		if len > 0.0:
			return len
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		var rate := maxi(wav.mix_rate, 1)
		var ch := 2 if wav.stereo else 1
		var bps := 2
		match wav.format:
			AudioStreamWAV.FORMAT_8_BITS:
				bps = 1
			AudioStreamWAV.FORMAT_16_BITS:
				bps = 2
		var payload := wav.data.size()
		return float(payload) / float(rate * ch * bps)
	if stream is AudioStreamMP3:
		return 0.0
	return 0.0


static func _wav_pcm_stream(data: PackedByteArray) -> AudioStream:
	if data.size() < 44 or not _bytes_eq(data, 0, "RIFF"):
		return null
	var pos := 12
	var sample_rate := 24000
	var channels := 1
	var bits := 16
	var pcm := PackedByteArray()
	while pos + 8 <= data.size():
		var chunk_id := data.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size: int = data.decode_u32(pos + 4)
		pos += 8
		var chunk_end := pos + chunk_size
		# 百炼等来源的 WAV 可能把 data 块 size 写成 0x7FFFFFFF，实际 PCM 为文件剩余字节。
		if chunk_end > data.size() or chunk_size <= 0:
			if chunk_id == "data":
				pcm = data.slice(pos, data.size())
				break
			if pos >= data.size():
				break
			continue
		if chunk_id == "fmt " and chunk_size >= 16:
			channels = int(data.decode_u16(pos + 2))
			sample_rate = int(data.decode_u32(pos + 4))
			bits = int(data.decode_u16(pos + 14))
		elif chunk_id == "data":
			pcm = data.slice(pos, chunk_end)
			break
		pos = chunk_end + (chunk_size % 2)
	if pcm.is_empty():
		return null
	var stream := AudioStreamWAV.new()
	stream.mix_rate = maxi(sample_rate, 1)
	stream.stereo = channels > 1
	stream.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream


static func _bytes_eq(data: PackedByteArray, offset: int, ascii: String) -> bool:
	if offset + ascii.length() > data.size():
		return false
	for i in ascii.length():
		if data[offset + i] != ascii.unicode_at(i):
			return false
	return true


static func _wav_from_pcm_payload(data: PackedByteArray) -> AudioStream:
	var offset := 0
	if data.size() > 44 and data[0] == 0x52:
		offset = 44
	var pcm := data.slice(offset)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 16000
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream
