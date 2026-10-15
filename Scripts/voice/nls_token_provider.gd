class_name NlsTokenProvider
extends Node

## 对应 Unity LocalNlsTokenProvider：manualToken → 缓存 → CreateToken（HMAC-SHA1）。

const AliyunNlsConfigScript := preload("res://Scripts/voice/aliyun_nls_config.gd")

var config: AliyunNlsConfigScript

var _http: HTTPRequest
var _cached_token: String = ""
var _cached_expire_unix: int = 0
var _requesting: bool = false


func setup(nls_config: AliyunNlsConfigScript) -> void:
	config = nls_config


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)


## Prefetch Aliyun token so first STT/TTS on device does not wait on CreateToken.
func warmup() -> void:
	var _t: String = await get_token()


func get_token() -> String:
	if config == null:
		push_error("缺少 AliyunNlsConfig")
		return ""

	var now := int(Time.get_unix_time_from_system())
	if not config.manual_token.is_empty():
		if config.manual_token_expire_unix <= 0 or config.manual_token_expire_unix > now + 60:
			return config.manual_token

	if not _cached_token.is_empty() and _cached_expire_unix > now + 300:
		return _cached_token

	while _requesting:
		await get_tree().process_frame
		now = int(Time.get_unix_time_from_system())
		if not _cached_token.is_empty() and _cached_expire_unix > now + 300:
			return _cached_token

	var created: String = await _create_token()
	return created


func _create_token() -> String:
	_requesting = true
	if config.access_key_id.is_empty() or config.access_key_secret.is_empty():
		push_error("请在 AliyunNlsConfig 填写 AccessKey，或填写有效的 manualToken")
		_requesting = false
		return ""

	var timestamp := _utc_timestamp()
	var nonce := _guid()
	var parameters: Dictionary = {
		"AccessKeyId": config.access_key_id,
		"Action": "CreateToken",
		"Format": "JSON",
		"RegionId": "cn-shanghai",
		"SignatureMethod": "HMAC-SHA1",
		"SignatureNonce": nonce,
		"SignatureVersion": "1.0",
		"Timestamp": timestamp,
		"Version": "2019-02-28",
	}
	var query := _build_canonical_query(parameters)
	var string_to_sign := "GET&" + _percent_encode("/") + "&" + _percent_encode(query)
	var signature := _sign(string_to_sign, config.access_key_secret + "&")
	var url := "https://%s/?%s&Signature=%s" % [config.get_token_meta_host(), query, _percent_encode(signature)]

	var err := _http.request(url, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		push_error("CreateToken 无法发起请求: %s" % err)
		_requesting = false
		return ""

	var completed: Array = await _http.request_completed
	var result: int = int(completed[0])
	var response_code: int = int(completed[1])
	var body: PackedByteArray = completed[3]
	var text: String = body.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_error("CreateToken 失败: code=%s\n%s" % [response_code, text])
		_requesting = false
		return ""

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("Token"):
		push_error("CreateToken 响应无 Token: " + text)
		_requesting = false
		return ""

	var parsed_dict: Dictionary = parsed
	var token_obj: Variant = parsed_dict.get("Token", {})
	if typeof(token_obj) != TYPE_DICTIONARY:
		push_error("CreateToken 响应无 Token.Id: " + text)
		_requesting = false
		return ""
	var token_dict: Dictionary = token_obj
	if not token_dict.has("Id"):
		push_error("CreateToken 响应无 Token.Id: " + text)
		_requesting = false
		return ""

	_cached_token = str(token_dict["Id"])
	if token_dict.has("ExpireTime"):
		_cached_expire_unix = int(token_dict["ExpireTime"])
	else:
		_cached_expire_unix = int(Time.get_unix_time_from_system()) + 86000

	_requesting = false
	return _cached_token


func _utc_timestamp() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]


func _guid() -> String:
	return "%d-%d" % [Time.get_ticks_usec(), randi()]


func _build_canonical_query(parameters: Dictionary) -> String:
	var keys: Array = parameters.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for k in keys:
		parts.append(_percent_encode(str(k)) + "=" + _percent_encode(str(parameters[k])))
	return "&".join(parts)


func _percent_encode(value: String) -> String:
	var sb := PackedStringArray()
	var bytes: PackedByteArray = value.to_utf8_buffer()
	for i in bytes.size():
		var b: int = bytes[i]
		if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or (b >= 48 and b <= 57) \
				or b == 45 or b == 95 or b == 46 or b == 126:
			sb.append("%c" % b)
		else:
			sb.append("%" + "%02X" % b)
	return "".join(sb)


func _sign(string_to_sign: String, key: String) -> String:
	var digest := _hmac_sha1(key.to_utf8_buffer(), string_to_sign.to_utf8_buffer())
	return Marshalls.raw_to_base64(digest)


func _hmac_sha1(key: PackedByteArray, message: PackedByteArray) -> PackedByteArray:
	var block := 64
	if key.size() > block:
		var h := HashingContext.new()
		h.start(HashingContext.HASH_SHA1)
		h.update(key)
		key = h.finish()
	var ikey := PackedByteArray()
	var okey := PackedByteArray()
	ikey.resize(block)
	okey.resize(block)
	for i in block:
		var k: int = key[i] if i < key.size() else 0
		ikey[i] = k ^ 0x36
		okey[i] = k ^ 0x5c
	var inner := HashingContext.new()
	inner.start(HashingContext.HASH_SHA1)
	inner.update(ikey)
	inner.update(message)
	var inner_hash := inner.finish()
	var outer := HashingContext.new()
	outer.start(HashingContext.HASH_SHA1)
	outer.update(okey)
	outer.update(inner_hash)
	return outer.finish()
