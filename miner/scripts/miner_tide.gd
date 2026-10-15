class_name MinerTideState
extends RefCounted

enum Phase { HIGH_HOLD, EBBING, LOW_HOLD }

const EBB_START := 30.0
## 退潮 10s：前 2s 慢、后 8s 快（与背景 30–40s 潮汐中段对齐）
const EBB_SLOW_SEC := 2.0
const EBB_FAST_SEC := 8.0
const EBB_END := EBB_START + EBB_SLOW_SEC + EBB_FAST_SEC
const Y_HIGH := 0.0
const Y_LOW := 162.0
## 前两秒结束时潮位/鱼位进度约 10%，余下 90% 在后 8 秒完成
const EBB_PROGRESS_AFTER_SLOW := 0.10
const EBB_FAST_EASE := 0.84
const EBB_FISH_FAST_EASE := 0.52
const BLOOD_FADE := 0.8

var phase: Phase = Phase.HIGH_HOLD
var tide_layer_y: float = Y_HIGH
var ebb_bar_ratio: float = 1.0
var elapsed: float = 0.0
var blood_moon: bool = false
var blood: float = 0.0

var _ebb_banner_pending: bool = false
var _blood_banner_pending: bool = false


func reset() -> void:
	phase = Phase.HIGH_HOLD
	tide_layer_y = Y_HIGH
	ebb_bar_ratio = 1.0
	elapsed = 0.0
	blood_moon = false
	blood = 0.0
	_ebb_banner_pending = false
	_blood_banner_pending = false


func advance(p_elapsed: float, _fish_y_min: float, _fish_y_max: float) -> void:
	var prev_phase := phase
	var prev_elapsed := elapsed
	elapsed = maxf(p_elapsed, 0.0)
	if blood_moon:
		phase = Phase.HIGH_HOLD
		tide_layer_y = Y_HIGH
		ebb_bar_ratio = 1.0
		if elapsed < EBB_START:
			blood = 0.0
		else:
			blood = smoothstep(0.0, 1.0, clampf((elapsed - EBB_START) / BLOOD_FADE, 0.0, 1.0))
		if prev_elapsed < EBB_START and elapsed >= EBB_START:
			_blood_banner_pending = true
		return
	blood = 0.0
	if elapsed < EBB_START:
		phase = Phase.HIGH_HOLD
		tide_layer_y = Y_HIGH
		ebb_bar_ratio = 1.0
	elif elapsed < EBB_END:
		phase = Phase.EBBING
		var t := ebb_motion_progress()
		tide_layer_y = lerpf(Y_HIGH, Y_LOW, t)
		ebb_bar_ratio = 1.0 - t
	else:
		phase = Phase.LOW_HOLD
		tide_layer_y = Y_LOW
		ebb_bar_ratio = 0.0
	if prev_phase == Phase.HIGH_HOLD and phase == Phase.EBBING:
		_ebb_banner_pending = true


func ebb_motion_progress() -> float:
	return _ebb_piecewise(elapsed, EBB_FAST_EASE)


func ebb_fish_progress() -> float:
	return _ebb_piecewise(elapsed, EBB_FISH_FAST_EASE)


func _ebb_piecewise(t_elapsed: float, fast_ease: float) -> float:
	var dt := t_elapsed - EBB_START
	if dt <= 0.0:
		return 0.0
	if dt >= EBB_SLOW_SEC + EBB_FAST_SEC:
		return 1.0
	if dt <= EBB_SLOW_SEC:
		return lerpf(0.0, EBB_PROGRESS_AFTER_SLOW, dt / EBB_SLOW_SEC)
	var fast := clampf((dt - EBB_SLOW_SEC) / EBB_FAST_SEC, 0.0, 1.0)
	var ft := pow(smoothstep(0.0, 1.0, fast), fast_ease)
	return lerpf(EBB_PROGRESS_AFTER_SLOW, 1.0, ft)


func consume_blood_banner() -> bool:
	if not _blood_banner_pending:
		return false
	_blood_banner_pending = false
	return true


func consume_ebb_banner() -> bool:
	if not _ebb_banner_pending:
		return false
	_ebb_banner_pending = false
	return true


func get_fish_swim_y_max(fish_y_min: float, fish_y_max: float) -> float:
	if phase == Phase.HIGH_HOLD:
		return fish_y_max
	if phase == Phase.LOW_HOLD:
		return fish_y_min - 36.0
	var t := ebb_fish_progress()
	return lerpf(fish_y_max, fish_y_min - 36.0, t)


func should_purge_all_fish() -> bool:
	if blood_moon:
		return false
	return elapsed >= EBB_END
