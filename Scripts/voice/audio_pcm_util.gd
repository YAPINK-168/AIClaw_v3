class_name AudioPcmUtil
extends RefCounted

## 对应 Unity AudioPcmUtil：float ↔ 16bit 小端 PCM，线性重采样。


static func floats_to_pcm16_mono(samples: PackedFloat32Array, from_rate: int, to_rate: int) -> PackedByteArray:
	var resampled := resample(samples, from_rate, to_rate)
	var pcm := PackedByteArray()
	pcm.resize(resampled.size() * 2)
	for i in resampled.size():
		var s := clampf(resampled[i], -1.0, 1.0)
		pcm.encode_s16(i * 2, int(s * 32767.0))
	return pcm


static func resample(input: PackedFloat32Array, from_rate: int, to_rate: int) -> PackedFloat32Array:
	if from_rate == to_rate:
		return input
	if from_rate <= 0 or to_rate <= 0 or input.is_empty():
		return PackedFloat32Array()
	var new_len := int(float(input.size()) * float(to_rate) / float(from_rate))
	if new_len <= 0:
		return PackedFloat32Array()
	var output := PackedFloat32Array()
	output.resize(new_len)
	var last := input.size() - 1
	for i in new_len:
		var src_pos := float(i) * float(from_rate) / float(to_rate)
		var i0 := int(src_pos)
		var i1 := mini(i0 + 1, last)
		var t := src_pos - float(i0)
		output[i] = lerpf(input[i0], input[i1], t)
	return output
