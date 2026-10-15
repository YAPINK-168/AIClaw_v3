@tool
extends EditorPlugin

# MCPServer and MCPAutoSave are now provided by the C++ GDExtension
# (registered in ClassDB at SCENE init level). No preload needed.
const SettingsPanel = preload("res://addons/godot_mcp/ui/settings_panel.tscn")

# 版本号单一真源 = plugin.cfg 的 version(_enter_tree 里读入)。
# quick-build 打包时会把版本写进打包副本的 plugin.cfg,footer/更新比对随之一致,
# 不再需要在这里硬编码(以前两处会不同步)。
var PLUGIN_VERSION := "0.0.0"
const SERVER_NAME := "godot-mcp"   # MCP 服务器在客户端配置里的键名

# 面板配色(常量,供整面板与就地刷新复用)
const C_TEXT := Color("eeeeee")
const C_TEXT2 := Color("888888")

# ── 品牌/联系方式(常量,不翻译)──
const EMAIL := "a549623165@gmail.com"
const WECHAT := "lidaxian-AI"
const SUPPORT_WECHAT := "vberai-support"
const DOWNLOAD_URL := "https://www.vberai.com/game-engines/godot"
const DOWNLOAD_LABEL := "www.vberai.com/game-engines/godot"
const REGISTER_URL := "https://www.vberai.com/auth/register"  # 注册账号(web)
const PRICING_URL := "https://www.vberai.com/pricing"         # 充值/升级入口兜底(后端未下发 upgradeUrl 时)

# ── 产品版本检查(公开接口,无需登录)──
# 新协议:GET {VberAI apiBase}/v1/products/godot-mcp/version?edition=standalone
# 返回 version + releaseNotes 多语言 map;下载入口仍走产品官网。
const UPDATE_PRODUCT_CODE := "godot-mcp"
const UPDATE_EDITION := "standalone"
const UPDATE_API_DEFAULT := "https://api.vberai.com/api"
const UPDATE_FALLBACK_DOWNLOAD := "https://www.vberai.com/game-engines/godot"

# ── 多语言(与四个 MCP 共用同一套 20 语言集),可手动切换 / 跟随编辑器语言 ──
# 顺序按地域分组而不是按加进来的先后:到二十种以后,只有同语系挨在一起下拉才好找。
# 繁中在 Godot 侧按 gettext 惯例用下划线(zh_TW.po),cocos 那边是 zh-TW.js,各随各的平台。
const LOCALES := [
	"zh", "zh_TW", "en", "ja", "ko",
	"vi", "th", "id", "ms", "fil", "hi",
	"fr", "de", "es", "it", "pt",
	"pl", "ru", "tr",
	"ar",
]
# [locale_code, 显示名]。下拉只列具体语言(无「Auto」项):默认选中当前生效语言
# (settings.lang 为空时 = 跟随 Godot 编辑器语言),选了某个即固定为该语言。
const LANG_OPTIONS := [
	["zh", "中文"],
	["zh_TW", "繁體中文"],
	["en", "English"],
	["ja", "日本語"],
	["ko", "한국어"],
	["vi", "Tiếng Việt"],
	["th", "ไทย"],
	["id", "Bahasa Indonesia"],
	["ms", "Bahasa Melayu"],
	["fil", "Filipino"],
	["hi", "हिन्दी"],
	["fr", "Français"],
	["de", "Deutsch"],
	["es", "Español"],
	["it", "Italiano"],
	["pt", "Português"],
	["pl", "Polski"],
	["ru", "Русский"],
	["tr", "Türkçe"],
	["ar", "العربية"],
]
# 从右往左书写的语言。目前只有 ar 有翻译,he/fa/ur 先列出来:将来补上 .po
# 就自动生效,不必再回来改布局代码。文字本身的双向排序和阿拉伯字形连写由
# Godot 的 TextServer(ICU) 负责,这里只管控件的排列方向。
const RTL_LOCALES := ["ar", "he", "fa", "ur"]
var _i18n := {}          # locale -> {key: string}
var _locale := "en"

var mcp_server: Node  # MCPServer (C++ Node subclass)
var settings_panel: Control
var dock: Control
var auto_save: Node  # MCPAutoSave (C++ Node subclass)
var _status_timer: Timer  # 1Hz dock refresh (Running/Stopped + endpoint)
var _tools_http: HTTPRequest  # tools/list fetch for the 工具管理 tab

# ── 版本更新检查 ──
var _update_http: HTTPRequest    # /products/:code/version 请求(公开接口,无需 token)
var _update_manual := false      # 本次是否手动触发(手动时忽略「跳过」,且无更新会提示「已最新」)
var _update_busy := false        # 请求在飞,避免并发/叠加弹窗
var _update_dialog: AcceptDialog # 复用弹窗,避免多次弹出叠加

# ── VberAI 账号(登录门禁)──
# login/verify/refresh 是阻塞的同步网络调用(C++ 侧 NSURLSession),必须放在
# Thread 里跑,否则会卡住编辑器主线程;同一时刻只允许一个账号操作在跑。
var _account_thread: Thread
var _account_busy := false
var _account_error := ""       # 显示在账号区的错误信息(空 = 无)
var _google_pending := false   # 已打开浏览器等待 Google 回调
var _last_refresh_msec := 0    # 静默续期的退避(断网时避免 1Hz 连环重试)
var _last_session_check_msec := 0  # 多设备踢出轮询的退避(30s 一次)
# 本次启动是否发生了端口回落：{requested, actual}，空 = 没有。刻意记在这里而不是每帧
# 去问 C++ 的 get_port_fallback() —— 启动后我们会把绑上的端口 set_port 回去让两边一致
# (否则停服后 get_active_port() 会退回没绑上的那个旧端口，endpoint/一键配置全跟着错)，
# 而那一步会立刻让 C++ 侧的 fallback 归空，提示条还没等用户看见就消失了。
var _port_fallback: Dictionary = {}
# 退出/重启后回填邮箱,省得重输。密码出于安全不持久化(拷走文件也拿不到),
# 需要时重新输入即可。token 已持久化,平时重启不用重登。
var _saved_email := ""

# ── 防火墙可达性探测 ──
# macOS/Windows 防火墙按「接收方应用」拦截入站,进程内自连永远通,
# 所以必须用外部进程(curl)探测端口是否真的对外可达。
# 用 OS.create_process + Timer 轮询,而非 Thread:编辑器启动时会重编
# @tool 脚本,后台线程里跑 GDScript 会被打断("Bad address index")。
var _fw_probe_pid := -1
var _fw_probe_reason := ""
var _fw_probe_deadline_msec := 0
var _fw_timer: Timer
var _fw_pending_google := false  # 探测进行中时又点了 Google 登录

# Plugin settings
var settings := {
	"port": 2000,
	"host": "127.0.0.1",
	"auto_start": false,   # 走正常启动流程：默认不自动启动，用户在面板手动点「启动」
	"debug_mode": true,
	"lang": "",            # 面板语言；空串 = 跟随 Godot 编辑器语言
	"fw_hint_dismissed": false,  # 防火墙提示弹窗的「不再提示」
	"saved_email": "",           # 退出/重启后回填邮箱(密码出于安全不存)
	"skipped_version": ""        # 用户「跳过」的版本号;该版本不再弹更新(critical 除外)
}

const SETTINGS_PATH = "user://godot_mcp_settings.json"


func _enter_tree() -> void:
	# Register plugin in Engine meta so RefCounted tools can reach
	# get_undo_redo() / get_editor_interface() via Engine.get_meta.
	Engine.set_meta("GodotMCPPlugin", self)

	# Crash recovery: if a previous game_run play {bridge:true} injected the
	# runtime-bridge autoload but the editor died before restoring project.godot,
	# a dirty marker is left behind. Undo the injection now.
	_recover_bridge_autoload()

	# 版本号从 plugin.cfg 读(单一真源;quick-build 打包会把版本写入该文件)。
	PLUGIN_VERSION = _read_plugin_version()

	# Load settings first (may pin the UI language).
	_load_settings()
	_restore_saved_credentials()

	# Load UI translations (honors settings.lang, else follows editor language).
	_load_translations()

	# Create MCP server instance (C++ GDExtension)
	mcp_server = ClassDB.instantiate("MCPServer")
	mcp_server.name = "MCPServer"
	add_child(mcp_server)

	# Auto-save singleton — debounces save_scene after mutations (C++ GDExtension)
	auto_save = ClassDB.instantiate("MCPAutoSave")
	auto_save.name = "MCPAutoSave"
	add_child(auto_save)

	# Initialize server with settings
	mcp_server.initialize(settings.port, settings.host, settings.debug_mode)

	# Google 登录回调落地(浏览器 → GET /callback 送来一次性 code)后,
	# 在后台线程用 PKCE verifier 换令牌。
	mcp_server.vber_oauth_code_received.connect(_on_vber_oauth_code)

	# 服务器每次启动后做一次「外部可达性」体检:被防火墙拦住时弹窗指引用户放行。
	mcp_server.server_started.connect(_on_server_started_probe)
	_fw_timer = Timer.new()
	_fw_timer.wait_time = 0.25
	_fw_timer.autostart = false
	_fw_timer.timeout.connect(_poll_fw_probe)
	add_child(_fw_timer)

	# Create dock panel
	_create_dock()

	# 上次登录的会话仍在 → 后台向后端校验一次(/auth/me,离线时保持宽限)。
	var vs: Dictionary = mcp_server.vber_status()
	if bool(vs.get("loggedIn", false)):
		_start_account_op("verify")

	# Dedicated request for tools/list (tools tab).
	_tools_http = HTTPRequest.new()
	_tools_http.timeout = 10.0
	add_child(_tools_http)
	_tools_http.request_completed.connect(_on_tools_http_completed)

	# 版本更新检查:编辑器加载/启用插件时静默查一次(与 cocos 一致,非定时轮询)。
	_update_http = HTTPRequest.new()
	_update_http.timeout = 10.0
	add_child(_update_http)
	_update_http.request_completed.connect(_on_update_http_completed)
	_check_for_update(false)

	# 1Hz dock refresh: keep 状态(Running/Stopped) and Endpoint in sync while
	# the dock is visible. Cheap — no network, just reads mcp_server state.
	_status_timer = Timer.new()
	_status_timer.wait_time = 1.0
	_status_timer.autostart = true
	_status_timer.timeout.connect(_update_dock_ui)
	add_child(_status_timer)

	# Auto-start only if the user explicitly opted in (default off).
	if settings.auto_start:
		mcp_server.start()

	print("[Godot MCP] Plugin loaded (v%s, port %d)" % [PLUGIN_VERSION, settings.port])


const _BRIDGE_MARKER := "user://_mcp_bridge_dirty"
const _BRIDGE_AUTOLOAD_KEY := "autoload/MCPRuntimeBridge"


func _recover_bridge_autoload() -> void:
	if not FileAccess.file_exists(_BRIDGE_MARKER):
		return
	var had_prev := false
	var prev := ""
	var f := FileAccess.open(_BRIDGE_MARKER, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			had_prev = bool(parsed.get("had_prev", false))
			prev = String(parsed.get("prev", ""))
	if had_prev:
		ProjectSettings.set_setting(_BRIDGE_AUTOLOAD_KEY, prev)
	elif ProjectSettings.has_setting(_BRIDGE_AUTOLOAD_KEY):
		ProjectSettings.clear(_BRIDGE_AUTOLOAD_KEY)
	ProjectSettings.save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_BRIDGE_MARKER))
	print("[Godot MCP] Recovered leaked runtime-bridge autoload from a prior session")


func _exit_tree() -> void:
	# 更新弹窗挂在编辑器根节点上,不随插件树自动释放,手动清掉。
	if _update_dialog and is_instance_valid(_update_dialog):
		_update_dialog.queue_free()
		_update_dialog = null

	# 等后台线程收尾(悬空的 Thread 会在析构时报错/崩溃)。
	if _account_thread:
		_account_thread.wait_to_finish()
		_account_thread = null

	# Stop server
	if mcp_server:
		mcp_server.stop()
		mcp_server.queue_free()
		mcp_server = null

	if auto_save:
		auto_save.queue_free()
		auto_save = null

	# Remove the right-side dock
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()

	if Engine.has_meta("GodotMCPPlugin"):
		Engine.remove_meta("GodotMCPPlugin")

	print("[Godot MCP] Plugin unloaded")


func _create_dock() -> void:
	# 放到右侧属性面板(Inspector)那一列。启用插件(项目设置→插件)后出现，
	# 走标准的 EditorPlugin dock 生命周期。
	dock = _create_dock_ui()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _create_dock_ui() -> Control:
	# dock root must be a Control whose `name` is the tab title.
	var root = VBoxContainer.new()
	root.name = "GodotMCP"
	# 文案由 _t() 和插件内的 i18n/*.po 完整管理。若继承 Godot 编辑器的
	# 自动翻译，手动选 English 后 "Tools/Setup/Start" 又会被编辑器中文
	# 翻回「工具/设置/开始」，形成中英混排。
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	root.custom_minimum_size = Vector2(_sc(300), _sc(240))
	_apply_layout_direction(root)
	_populate_dock(root)
	return root


func _rebuild_dock() -> void:
	# Re-render the dock (called after a language switch / config change).
	if dock:
		# 语言可能刚从阿拉伯语切成英语(或反过来),方向要跟着换。
		_apply_layout_direction(dock)
		_populate_dock(dock)
		_update_dock_ui()


func _is_rtl() -> bool:
	return _locale in RTL_LOCALES


func _apply_layout_direction(root: Control) -> void:
	# 只需设根节点:子节点默认 LAYOUT_DIRECTION_INHERITED,会一路继承下去,
	# 于是 HBoxContainer 反向排列、Label/Button 的文本对齐整体翻转。
	root.layout_direction = Control.LAYOUT_DIRECTION_RTL if _is_rtl() \
		else Control.LAYOUT_DIRECTION_LTR


func _populate_dock(root: Control) -> void:
	# We wrap the actual controls in a ScrollContainer so the dock
	# stays bounded and never pushes other panels off-screen.
	for c in root.get_children():
		c.queue_free()

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var outer = MarginContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("margin_top", _sc(8))
	outer.add_theme_constant_override("margin_bottom", _sc(8))
	outer.add_theme_constant_override("margin_left", _sc(6))
	outer.add_theme_constant_override("margin_right", _sc(6))
	scroll.add_child(outer)

	# Dark card (rounded #2a2a2a fill, #404040 border). Fills the dock width.
	var card = PanelContainer.new()
	card.name = "GodotMCPInner"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.add_theme_stylebox_override("panel", _flat_style(Color("2a2a2a"), Color("404040"), 1, 6, 12, 10))
	outer.add_child(card)

	var panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", _sc(6))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(panel)

	# ===== 配色 =====
	var TEXT := Color("eeeeee")
	var TEXT2 := Color("888888")
	var LABEL := Color("aaaaaa")

	# ── 语言切换 ──
	var lang_row = HBoxContainer.new()
	lang_row.alignment = BoxContainer.ALIGNMENT_END
	lang_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lang_opt = OptionButton.new()
	lang_opt.name = "LangOption"
	lang_opt.add_theme_font_size_override("font_size", _sc(11))
	# 默认选中「当前生效语言」_locale(未手动指定时 = 跟随 Godot 编辑器语言的探测结果);
	# 选了某个具体语言即固定(settings.lang 被设为该 locale)。不再有单独的「Auto」项。
	var sel_idx := 0
	for i in LANG_OPTIONS.size():
		lang_opt.add_item(LANG_OPTIONS[i][1], i)
		if LANG_OPTIONS[i][0] == _locale:
			sel_idx = i
	lang_opt.select(sel_idx)
	lang_opt.item_selected.connect(_on_lang_selected)
	lang_row.add_child(lang_opt)
	panel.add_child(lang_row)

	# ── 品牌头 ──
	var brand_name = Label.new()
	brand_name.text = _t("brand_name")
	brand_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand_name.add_theme_color_override("font_color", Color("007acc"))
	brand_name.add_theme_font_size_override("font_size", _sc(15))
	panel.add_child(brand_name)

	var brand_sub = Label.new()
	brand_sub.text = "Godot MCP Server"
	brand_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand_sub.add_theme_color_override("font_color", TEXT2)
	brand_sub.add_theme_font_size_override("font_size", _sc(11))
	panel.add_child(brand_sub)

	panel.add_child(HSeparator.new())

	# ── VberAI 账号(登录门禁:未登录时下方整个服务器面板隐藏)──
	var acct = VBoxContainer.new()
	acct.name = "AccountView"
	acct.add_theme_constant_override("separation", _sc(4))
	acct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(acct)
	_render_account_into(acct)

	# ================================================================
	# 服务器控制面板（仅登录后可见,见 _populate_dock 尾部的可见性设置）
	# ================================================================
	var server_view = VBoxContainer.new()
	server_view.name = "ServerView"
	server_view.add_theme_constant_override("separation", _sc(6))
	server_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(server_view)

	# ── Tab 栏 ──
	var tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", _sc(4))
	for t in [["server", _t("tab_server")], ["tools", _t("tab_tools")], ["config", _t("tab_config")]]:
		var tb = Button.new()
		tb.name = "Tab_" + t[0]
		tb.text = t[1]
		tb.toggle_mode = true
		tb.button_pressed = (t[0] == "server")
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_tab_button(tb)
		tb.pressed.connect(_on_tab_pressed.bind(t[0]))
		tab_bar.add_child(tb)
	server_view.add_child(tab_bar)

	# ── Tab 内容：服务器 ──
	var tab_server = VBoxContainer.new()
	tab_server.name = "TabServer"
	tab_server.add_theme_constant_override("separation", _sc(6))
	server_view.add_child(tab_server)

	var status_container = HBoxContainer.new()
	var status_label = Label.new()
	status_label.text = _t("lbl_status")
	status_label.add_theme_color_override("font_color", LABEL)
	status_container.add_child(status_label)
	var status_value = Label.new()
	status_value.name = "StatusValue"
	status_value.text = _t("stopped")
	status_value.add_theme_color_override("font_color", Color.RED)
	status_container.add_child(status_value)
	tab_server.add_child(status_container)

	var port_container = HBoxContainer.new()
	var port_label = Label.new()
	port_label.text = _t("lbl_port")
	port_label.add_theme_color_override("font_color", LABEL)
	port_container.add_child(port_label)
	var port_spin = SpinBox.new()
	port_spin.name = "PortSpinBox"
	port_spin.min_value = 1024
	port_spin.max_value = 65535
	port_spin.value = settings.port
	port_spin.editable = true
	port_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_container.add_child(port_spin)
	tab_server.add_child(port_container)

	# 端口回落提示：端口框里装的是首选端口，被占用时服务落在别的端口上，
	# 不标出来用户会以为设置没生效(第二个项目开在同一台机器上时必现)。
	var fallback_label = Label.new()
	fallback_label.name = "PortFallbackLabel"
	fallback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fallback_label.add_theme_color_override("font_color", Color("#fd7e14"))
	fallback_label.add_theme_font_size_override("font_size", _sc(11))
	fallback_label.visible = false
	tab_server.add_child(fallback_label)

	var auto_start_check = CheckBox.new()
	auto_start_check.name = "AutoStartCheck"
	auto_start_check.text = _t("chk_autostart")
	auto_start_check.button_pressed = settings.auto_start
	auto_start_check.toggled.connect(_on_auto_start_toggled)
	tab_server.add_child(auto_start_check)

	var button_container = HBoxContainer.new()
	var start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = _t("btn_start")
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.pressed.connect(_on_start_pressed)
	button_container.add_child(start_button)
	var stop_button = Button.new()
	stop_button.name = "StopButton"
	stop_button.text = _t("btn_stop")
	stop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop_button.pressed.connect(_on_stop_pressed)
	button_container.add_child(stop_button)
	tab_server.add_child(button_container)

	var ep_row = HBoxContainer.new()
	var info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.text = _t("lbl_endpoint") + ("http://127.0.0.1:%d/mcp" % _effective_port())
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.add_theme_color_override("font_color", TEXT2)
	info_label.add_theme_font_size_override("font_size", _sc(11))
	ep_row.add_child(info_label)
	var copy_ep = Button.new()
	copy_ep.text = _t("btn_copy")
	_style_secondary_button(copy_ep)
	copy_ep.pressed.connect(func(): _copy_to_clipboard("http://127.0.0.1:%d/mcp" % _effective_port(), copy_ep))
	ep_row.add_child(copy_ep)
	tab_server.add_child(ep_row)

	var conn_label = Label.new()
	conn_label.name = "ConnectionLabel"
	conn_label.text = _t("lbl_connections") + "0"
	conn_label.add_theme_color_override("font_color", TEXT2)
	conn_label.add_theme_font_size_override("font_size", _sc(11))
	tab_server.add_child(conn_label)

	# ── Tab 内容：工具管理（只读，按分类分组）──
	var tab_tools = VBoxContainer.new()
	tab_tools.name = "TabTools"
	tab_tools.add_theme_constant_override("separation", _sc(5))
	tab_tools.visible = false
	server_view.add_child(tab_tools)
	var tools_title = Label.new()
	tools_title.name = "ToolsTitle"
	tools_title.text = _t("tools_title")
	tools_title.add_theme_color_override("font_color", TEXT)
	tools_title.add_theme_font_size_override("font_size", _sc(13))
	tab_tools.add_child(tools_title)
	var tools_list = VBoxContainer.new()
	tools_list.name = "ToolList"
	tools_list.add_theme_constant_override("separation", _sc(3))
	tab_tools.add_child(tools_list)

	# ── Tab 内容：一键配置(自动写入客户端配置文件)──
	var tab_config = VBoxContainer.new()
	tab_config.name = "TabConfig"
	tab_config.add_theme_constant_override("separation", _sc(6))
	tab_config.visible = false
	server_view.add_child(tab_config)
	_build_config_tab(tab_config)

	# ── 关于 / 联系 footer ──
	panel.add_child(HSeparator.new())

	var copyright = Label.new()
	copyright.text = _t("copyright_line").format([PLUGIN_VERSION])
	copyright.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copyright.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copyright.add_theme_color_override("font_color", TEXT)
	copyright.add_theme_font_size_override("font_size", _sc(11))
	panel.add_child(copyright)

	# 手动「检查更新」:忽略「跳过」,无更新时提示「已是最新」。
	var upd_row = HBoxContainer.new()
	upd_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var upd_btn = Button.new()
	upd_btn.name = "CheckUpdateButton"
	upd_btn.text = _t("check_for_updates")
	upd_btn.add_theme_font_size_override("font_size", _sc(10))
	_style_secondary_button(upd_btn)
	upd_btn.pressed.connect(func(): _check_for_update(true))
	upd_row.add_child(upd_btn)
	panel.add_child(upd_row)

	var protocol = Label.new()
	protocol.text = _t("protocol_line")
	protocol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	protocol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	protocol.add_theme_color_override("font_color", TEXT2)
	protocol.add_theme_font_size_override("font_size", _sc(10))
	panel.add_child(protocol)

	var contact = RichTextLabel.new()
	contact.bbcode_enabled = true
	contact.fit_content = true
	contact.scroll_active = false
	contact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contact.add_theme_color_override("default_color", Color("aaaaaa"))
	contact.add_theme_font_size_override("normal_font_size", _sc(10))
	contact.text = "[center]📧 %s: [url=mailto:%s]%s[/url]\n💬 %s: %s    💬 %s: %s\n⬇ %s: [url=%s]%s[/url][/center]" % [
		_t("contact_email"), EMAIL, EMAIL,
		_t("contact_wechat"), WECHAT,
		_t("contact_support"), SUPPORT_WECHAT,
		_t("contact_download"), DOWNLOAD_URL, DOWNLOAD_LABEL,
	]
	contact.meta_clicked.connect(func(meta): OS.shell_open(_with_utm(str(meta))))
	panel.add_child(contact)

	# 登录门禁:服务器面板只在账号「可用」态显示(有权益+未被踢,与 C++ 门禁一致)。
	server_view.visible = _account_active()


# 一键配置页:每个客户端一行(状态 + 一键配置/删除/打开位置);底部通用 JSON + CLI。
func _build_config_tab(tab_config: VBoxContainer) -> void:
	var cfg_hint = Label.new()
	cfg_hint.text = _t("config_hint")
	cfg_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cfg_hint.add_theme_color_override("font_color", C_TEXT2)
	cfg_hint.add_theme_font_size_override("font_size", _sc(11))
	tab_config.add_child(cfg_hint)

	for client in _ai_clients():
		var configured := _client_configured(client)
		var box = VBoxContainer.new()
		box.add_theme_constant_override("separation", _sc(2))
		var head = HBoxContainer.new()
		head.add_theme_constant_override("separation", _sc(8))
		var nm = Label.new()
		nm.text = String(client.name)
		nm.add_theme_color_override("font_color", C_TEXT)
		nm.add_theme_font_size_override("font_size", _sc(12))
		head.add_child(nm)
		# 状态紧挨在客户端名右边,清楚对应是哪个客户端。
		var st = Label.new()
		st.text = ("✓ " + _t("status_configured")) if configured else ("✗ " + _t("status_not_configured"))
		st.add_theme_color_override("font_color", Color("3fb950") if configured else Color("888888"))
		st.add_theme_font_size_override("font_size", _sc(11))
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(st)
		box.add_child(head)

		var pth = Label.new()
		pth.text = _client_path(client)
		pth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pth.add_theme_color_override("font_color", Color("777777"))
		pth.add_theme_font_size_override("font_size", _sc(10))
		box.add_child(pth)

		var row = HBoxContainer.new()
		var the_client: Dictionary = client
		var b_cfg = Button.new()
		b_cfg.text = _t("btn_auto_config")
		_style_primary_button(b_cfg)
		b_cfg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b_cfg.disabled = configured
		b_cfg.pressed.connect(func(): _do_client_add(the_client))
		row.add_child(b_cfg)
		var b_del = Button.new()
		b_del.text = _t("btn_delete")
		_style_secondary_button(b_del)
		b_del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b_del.disabled = not configured
		b_del.pressed.connect(func(): _do_client_remove(the_client))
		row.add_child(b_del)
		var b_open = Button.new()
		b_open.text = _t("btn_open_loc")
		_style_secondary_button(b_open)
		var open_dir := _client_path(client).get_base_dir()
		b_open.pressed.connect(func(): _open_dir(open_dir))
		row.add_child(b_open)
		box.add_child(row)
		tab_config.add_child(box)

	# 通用 JSON(手动配置用)+ 复制
	var cfg_text = TextEdit.new()
	cfg_text.name = "ConfigText"
	cfg_text.editable = false
	cfg_text.text = _mcp_client_config_json()
	cfg_text.custom_minimum_size = Vector2(0, _sc(80))
	cfg_text.add_theme_font_size_override("font_size", _sc(11))
	tab_config.add_child(cfg_text)
	var copy_json = Button.new()
	copy_json.text = _t("btn_copy_json")
	_style_secondary_button(copy_json)
	copy_json.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_json.pressed.connect(func(): _copy_to_clipboard(_mcp_client_config_json(), copy_json))
	tab_config.add_child(copy_json)

	# CLI 命令
	var cli_title = Label.new()
	cli_title.text = _t("cli_title")
	cli_title.add_theme_color_override("font_color", C_TEXT)
	cli_title.add_theme_font_size_override("font_size", _sc(12))
	tab_config.add_child(cli_title)
	for cmd in _cli_commands():
		var crow = HBoxContainer.new()
		var cl = Label.new()
		cl.text = String(cmd.label)
		cl.custom_minimum_size = Vector2(_sc(58), 0)
		cl.add_theme_color_override("font_color", Color("aaaaaa"))
		cl.add_theme_font_size_override("font_size", _sc(11))
		crow.add_child(cl)
		var cb = Button.new()
		cb.text = _t("btn_copy")
		_style_secondary_button(cb)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var the_cmd := String(cmd.cmd)
		cb.pressed.connect(func(): _copy_to_clipboard(the_cmd, cb))
		crow.add_child(cb)
		tab_config.add_child(crow)


# ===== VberAI 账号区(登录门禁 UI)=====

func _is_logged_in() -> bool:
	return mcp_server != null and bool(mcp_server.vber_status().get("loggedIn", false))


# 账号是否处于「可用」态(有 token + 有权益 + 未被踢)。服务器面板只在此态显示,
# 与 C++ 侧 is_authenticated 的门禁一致。
func _account_active() -> bool:
	return mcp_server != null and String(mcp_server.vber_status().get("state", "")) == "active"


# 账号区提示行(无权益/被踢等状态说明)。
func _add_account_notice(parent: VBoxContainer, text: String, color: Color) -> void:
	var l = Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", _sc(10))
	parent.add_child(l)


# 就地重绘账号区,并按「可用」态显示/隐藏整个服务器面板。事件驱动:
# 登录/退出/Google 回调/被踢/语言切换时调用,1Hz 状态刷新不会碰它,
# 输入框内容不会被打断。
func _render_account_section() -> void:
	if not dock:
		return
	var acct := dock.find_child("AccountView", true, false) as VBoxContainer
	if acct:
		_render_account_into(acct)
	var sv := dock.find_child("ServerView", true, false)
	if sv:
		sv.visible = _account_active()


func _render_account_into(acct: VBoxContainer) -> void:
	# 重绘前保留输入框内容(登录失败后不清空用户输入)。
	var prev_email := ""
	var prev_pass := ""
	var old_email := acct.find_child("AcctEmail", true, false) as LineEdit
	var old_pass := acct.find_child("AcctPassword", true, false) as LineEdit
	if old_email: prev_email = old_email.text
	if old_pass: prev_pass = old_pass.text
	# 从已登录态切回登录区(退出登录)时输入框不存在,回填上次登录用的凭证。
	if prev_email == "": prev_email = _saved_email
	for c in acct.get_children():
		acct.remove_child(c)
		c.queue_free()

	var st: Dictionary = mcp_server.vber_status() if mcp_server else {}
	# state: active(可用) / no_entitlement(无订阅权益) / kicked(被别的设备顶掉) / logged_out
	var state := String(st.get("state", "logged_out"))
	var logged_in := state != "logged_out"

	var title = Label.new()
	title.text = _t("acct_title")
	title.add_theme_color_override("font_color", C_TEXT)
	title.add_theme_font_size_override("font_size", _sc(12))
	acct.add_child(title)

	if logged_in:
		var ok := state == "active"
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", _sc(8))
		var lbl = Label.new()
		lbl.text = ("✓ " if ok else "⚠ ") + _t("acct_logged_in") + String(st.get("email", ""))
		lbl.add_theme_color_override("font_color", Color("3fb950") if ok else Color("e0a030"))
		lbl.add_theme_font_size_override("font_size", _sc(11))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		row.add_child(lbl)
		var out_btn = Button.new()
		out_btn.text = _t("btn_logout")
		_style_secondary_button(out_btn)
		out_btn.pressed.connect(_on_logout_pressed)
		row.add_child(out_btn)
		acct.add_child(row)

		if state == "no_entitlement":
			# 无订阅权益:门控 MCP 工具,引导升级(免费以上计划才可用)。
			var notice := _t("acct_no_entitlement")
			var pn := _plan_name(st.get("requiredPlan", {}))
			if pn != "":
				notice += "\n" + _t("acct_upgrade_to").format([pn])
			_add_account_notice(acct, notice, Color("e0a030"))
			# 充值/升级入口:后端在权益响应里下发了 upgradeUrl 就用它,否则用 vberai 定价页。
			var up_url := String(st.get("upgradeUrl", "")).strip_edges()
			if up_url == "":
				up_url = PRICING_URL
			var up = LinkButton.new()
			up.text = _t("acct_upgrade")
			up.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
			up.add_theme_font_size_override("font_size", _sc(11))
			up.add_theme_color_override("font_color", Color("4aa3ff"))
			up.add_theme_color_override("font_hover_color", Color("0098ff"))
			up.pressed.connect(func(): OS.shell_open(_with_utm(up_url)))
			acct.add_child(up)
			var rc = Button.new()
			rc.text = _t("acct_recheck")
			rc.disabled = _account_busy
			_style_secondary_button(rc)
			rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rc.pressed.connect(func(): _start_account_op("verify"))
			acct.add_child(rc)
		elif state == "kicked":
			# 被别的设备顶掉:提示 + 一键重新登录(重新激活会话,挤回来)。
			_add_account_notice(acct, _t("acct_kicked"), Color("dc3545"))
			var re = Button.new()
			re.text = _t("acct_logging_in") if _account_busy else _t("acct_relogin")
			re.disabled = _account_busy
			_style_primary_button(re)
			re.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			re.pressed.connect(func(): _start_account_op("verify"))
			acct.add_child(re)
	else:
		var hint = Label.new()
		hint.text = _t("acct_hint")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", C_TEXT2)
		hint.add_theme_font_size_override("font_size", _sc(10))
		acct.add_child(hint)

		var email_edit = LineEdit.new()
		email_edit.name = "AcctEmail"
		email_edit.placeholder_text = _t("acct_email_ph")
		email_edit.text = prev_email
		email_edit.add_theme_font_size_override("font_size", _sc(11))
		acct.add_child(email_edit)

		var pass_edit = LineEdit.new()
		pass_edit.name = "AcctPassword"
		pass_edit.placeholder_text = _t("acct_password_ph")
		pass_edit.secret = true
		pass_edit.text = prev_pass
		pass_edit.add_theme_font_size_override("font_size", _sc(11))
		pass_edit.text_submitted.connect(func(_txt): _on_login_pressed())
		acct.add_child(pass_edit)

		var btn_row = HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", _sc(4))
		var login_btn = Button.new()
		login_btn.text = _t("acct_logging_in") if _account_busy else _t("btn_login")
		login_btn.disabled = _account_busy
		_style_primary_button(login_btn)
		login_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		login_btn.pressed.connect(_on_login_pressed)
		btn_row.add_child(login_btn)
		var g_btn = Button.new()
		g_btn.text = _t("btn_login_google")
		g_btn.disabled = _account_busy
		_style_secondary_button(g_btn)
		g_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g_btn.pressed.connect(_on_google_login_pressed)
		btn_row.add_child(g_btn)
		acct.add_child(btn_row)

		# 注册账号(跳 web 注册页,注册完回来登录)。
		var reg = LinkButton.new()
		reg.text = _t("acct_register")
		reg.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		reg.add_theme_font_size_override("font_size", _sc(10))
		reg.add_theme_color_override("font_color", Color("4aa3ff"))
		reg.add_theme_color_override("font_hover_color", Color("0098ff"))
		reg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		reg.pressed.connect(func(): OS.shell_open(_with_utm(REGISTER_URL)))
		acct.add_child(reg)

		# 错误(红) / Google 等待提示(灰),同一位置只显示一条。
		var note := _account_error
		var note_color := Color("dc3545")
		if note == "" and _google_pending:
			note = _t("acct_google_hint")
			note_color = Color("888888")
		if note != "":
			var note_lbl = Label.new()
			note_lbl.text = note
			note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note_lbl.add_theme_color_override("font_color", note_color)
			note_lbl.add_theme_font_size_override("font_size", _sc(10))
			acct.add_child(note_lbl)

	acct.add_child(HSeparator.new())


func _on_login_pressed() -> void:
	if _account_busy or not mcp_server or not dock:
		return
	var email_edit := dock.find_child("AcctEmail", true, false) as LineEdit
	var pass_edit := dock.find_child("AcctPassword", true, false) as LineEdit
	var email := email_edit.text.strip_edges() if email_edit else ""
	var password := pass_edit.text if pass_edit else ""
	if email == "" or password == "":
		_account_error = _t("acct_need_credentials")
		_render_account_section()
		return
	# 记住邮箱,退出/重启后回填(密码出于安全不保存)。
	_saved_email = email
	settings.saved_email = email
	_save_settings()
	_account_error = ""
	_start_account_op("login", [email, password])


func _on_google_login_pressed() -> void:
	if _account_busy or not mcp_server:
		return
	# 回调(GET /auth/callback)打回本服务器 —— 服务器面板在未登录时是
	# 隐藏的,所以这里自动把服务器拉起来接回调。
	if not mcp_server.is_running():
		if not mcp_server.start():
			_account_error = _t("acct_need_server")
			_render_account_section()
			return
	# 先确认端口对外可达(防火墙没拦),可达才打开浏览器 —— 否则用户在
	# 网页上登完回调也送不进来。探测完成后走 _do_open_google_login()。
	_account_error = ""
	_start_fw_probe("google")


# 探测通过后真正打开浏览器开始 Google OAuth。
func _do_open_google_login() -> void:
	if not mcp_server or not mcp_server.is_running():
		return
	var url := String(mcp_server.vber_begin_google_login())
	OS.shell_open(_with_utm(url))
	_google_pending = true
	_account_error = ""
	_render_account_section()


func _on_logout_pressed() -> void:
	if _account_busy or not mcp_server:
		return
	mcp_server.vber_logout()
	# 退出登录 = 服务不可用:停掉服务器并收起整个服务器面板。
	if mcp_server.is_running():
		mcp_server.stop()
	_account_error = ""
	_google_pending = false
	_render_account_section()
	_update_dock_ui()


# Google 回调落地(C++ 主线程信号,已收到一次性 code)→ 把编辑器拉回前台,
# 后台线程做 code→token 交换;若账号线程正忙,记下待办等它收尾后再换。
var _pending_exchange := false

func _on_vber_oauth_code() -> void:
	_google_pending = false
	_account_error = ""
	var win := EditorInterface.get_base_control().get_window()
	if win:
		win.grab_focus()
	if _account_busy:
		_pending_exchange = true
		_render_account_section()
	else:
		_start_account_op("exchange")


# ===== 防火墙可达性探测与指引弹窗 =====

func _on_server_started_probe() -> void:
	_start_fw_probe("start")


func _start_fw_probe(reason: String) -> void:
	if not mcp_server or not mcp_server.is_running():
		return
	if _fw_probe_pid != -1:
		# 正在探测(多半是刚 start 触发的)时又点了 Google —— 复用同一次
		# 探测结果,不再排第二次。
		if reason == "google":
			_fw_pending_google = true
		return
	# 防火墙按「接收方应用」放行/拦截,必须用外部进程打回来才测得准。
	# curl: macOS 系统自带,Windows 10 1803+ 自带。退出码 0 = 端口可达
	# (HTTP 层结果无所谓),7/28 等 = 连不上。
	var null_dev := "NUL" if OS.get_name() == "Windows" else "/dev/null"
	var pid := OS.create_process("curl", ["-s", "-o", null_dev, "-m", "2",
		"http://127.0.0.1:%d/health" % _effective_port()])
	if pid <= 0:
		# curl 不可用 → 不下结论;Google 流程直接放行去试。
		if reason == "google" or _fw_pending_google:
			_fw_pending_google = false
			_do_open_google_login()
		return
	_fw_probe_pid = pid
	_fw_probe_reason = reason
	_fw_probe_deadline_msec = Time.get_ticks_msec() + 8000
	_fw_timer.start()


func _poll_fw_probe() -> void:
	if _fw_probe_pid == -1:
		_fw_timer.stop()
		return
	if OS.is_process_running(_fw_probe_pid):
		if Time.get_ticks_msec() > _fw_probe_deadline_msec:
			OS.kill(_fw_probe_pid)
			_finish_fw_probe(false, false)  # 超时且没退出 → 不下结论
		return
	var exit_code := OS.get_process_exit_code(_fw_probe_pid)
	_finish_fw_probe(exit_code == 0, true)


func _finish_fw_probe(reachable: bool, probe_valid: bool) -> void:
	var reason := _fw_probe_reason
	_fw_probe_pid = -1
	_fw_probe_reason = ""
	_fw_timer.stop()
	var want_google := reason == "google" or _fw_pending_google
	_fw_pending_google = false

	if want_google:
		# 探测失败但原因不明(curl 缺失/超时)时不拦流程,放行去试。
		if reachable or not probe_valid:
			_do_open_google_login()
		else:
			_account_error = _t("acct_fw_blocked")
			_render_account_section()
			_show_firewall_dialog()
		return

	# 服务器启动后的例行体检:只在确认被拦 且 用户没点过「不再提示」时弹。
	if probe_valid and not reachable and not bool(settings.get("fw_hint_dismissed", false)):
		_show_firewall_dialog()


func _show_firewall_dialog() -> void:
	print("[Godot MCP] port unreachable from outside — showing firewall hint dialog")
	var dlg := AcceptDialog.new()
	dlg.title = _t("fw_title")
	dlg.dialog_text = _t("fw_body_win") if OS.get_name() == "Windows" else _t("fw_body_mac")
	dlg.exclusive = false
	if OS.get_name() == "macOS":
		dlg.add_button(_t("fw_open_settings"), false, "open_fw")
	dlg.add_button(_t("fw_dismiss"), false, "dismiss")
	dlg.custom_action.connect(func(action: StringName):
		if action == StringName("open_fw"):
			# macOS 13+ 系统设置的防火墙页;旧系统会退到系统设置主页,无害。
			OS.shell_open("x-apple.systempreferences:com.apple.Firewall-Settings.extension")
		elif action == StringName("dismiss"):
			settings.fw_hint_dismissed = true
			_save_settings()
			dlg.queue_free()
	)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()


# 账号操作统一走单条后台线程(login/verify/refresh 都是阻塞网络调用)。
func _start_account_op(op: String, args: Array = []) -> void:
	if _account_busy or not mcp_server:
		return
	_account_busy = true
	_render_account_section()
	_account_thread = Thread.new()
	_account_thread.start(_account_worker.bind(op, args))


func _account_worker(op: String, args: Array) -> void:
	var result: Dictionary = {}
	match op:
		"login":
			result = mcp_server.vber_login(args[0], args[1])
		"exchange":
			result = mcp_server.vber_exchange_code()
		"verify":
			result = mcp_server.vber_verify()
		"refresh":
			result = mcp_server.vber_refresh()
		"check_session":
			result = mcp_server.vber_check_session()
	_on_account_op_done.call_deferred(op, result)


func _on_account_op_done(op: String, result: Dictionary) -> void:
	if _account_thread:
		_account_thread.wait_to_finish()
		_account_thread = null
	_account_busy = false
	if _pending_exchange:
		# 浏览器回调在上一个账号操作进行中落地 → 现在补做 code 交换。
		_pending_exchange = false
		_start_account_op("exchange")
		return
	var ok := bool(result.get("success", false))
	var kicked := op == "check_session" and bool(result.get("kicked", false))
	# Token 签发门禁下,login/exchange 无 token 的 403 经结果字典带回 denyCode;
	# 有 token 的会话/校验阶段则由 status.state=no_entitlement 反映。
	var deny_no_ent := String(result.get("denyCode", "")) == "CLIENT_NOT_ENTITLED"
	if ok:
		# 成功:清错误,让 state 提示(无权益/被踢)接管账号区展示。
		_account_error = ""
	elif kicked:
		_account_error = ""  # 被踢由 kicked 态渲染 acct_kicked,不重复
	elif deny_no_ent:
		_account_error = ""  # 权益不足由升级弹窗/账号区引导处理,不显示为红色错误
	elif not bool(result.get("offline", false)):
		# 明确失败(密码错/会话过期等);离线(offline=true)保持宽限,不打扰。
		_account_error = _localize_account_error(String(result.get("message", "")))
	if kicked:
		# 轮询仅在 active 时跑,被踢后 state=kicked 即停,故此弹框只触发一次。
		_show_kicked_dialog()
	# 权限不足:弹窗告知(点「前往升级订阅」跳充值)。只在用户可感知的账号操作
	# (登录/Google 回调/验证)后弹,后台 refresh/check_session 不弹,避免打扰。
	if op in ["login", "exchange", "verify"] and mcp_server:
		var st2: Dictionary = mcp_server.vber_status()
		if String(st2.get("state", "")) == "no_entitlement" or deny_no_ent:
			# 无 token 的签发门禁 403 用结果里的 requiredPlan/upgradeUrl;有 token 的用 status。
			var rp: Dictionary = (result.get("requiredPlan", {}) if deny_no_ent else st2.get("requiredPlan", {}))
			var up_url := String((result.get("upgradeUrl", "") if deny_no_ent else st2.get("upgradeUrl", ""))).strip_edges()
			_show_no_entitlement_dialog(up_url if up_url != "" else PRICING_URL, _plan_name(rp))
	_render_account_section()


func _localize_account_error(message: String) -> String:
	# Do not surface backend/network English directly in the localized dock UI.
	var value := message.to_lower()
	if "another device" in value or "session_replaced" in value or "session replaced" in value:
		return _t("acct_kicked")
	return _t("acct_login_failed")


func _show_kicked_dialog() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = _t("kicked_title")
	dlg.dialog_text = _t("acct_kicked")
	dlg.exclusive = false
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()


# 面板语言码 → 后端存本地化字符串用的 locale。后端只有中英文带区域,其余语言是裸码。
func _server_locale(locale: String) -> String:
	# 后端的繁中 key 是 zh-TW(连字符),面板这边是 zh_TW(下划线),要转一下 ——
	# 否则繁中用户会被当成简体,拿到 zh-CN 的文案。
	if locale == "zh_TW":
		return "zh-TW"
	if locale.begins_with("zh"):
		return "zh-CN"
	if locale.begins_with("en"):
		return "en-US"
	return locale


# 从 requiredPlan.nameLocalized 按当前面板语言取计划名(文档 §4.1);无则空串。
func _plan_name(rp: Dictionary) -> String:
	if rp.is_empty():
		return ""
	var names: Dictionary = rp.get("nameLocalized", {})
	if names.is_empty():
		return ""
	# 面板 locale(如 "zh")与后端 key(如 "zh-CN")可能不同:后端只有中英文带区域,
	# 其余语言是裸码。英文兜底排在中文之前 —— 后端没有该语言时(目前 ru/pt/ar 就没有),
	# 英文比中文更合理;旧顺序会把「基础计划」显示给俄语用户。
	for c in [_locale, _server_locale(_locale), "en-US", "zh-CN"]:
		if names.has(c) and String(names[c]) != "":
			return String(names[c])
	for v in names.values():
		if String(v) != "":
			return String(v)
	return ""


# 跳转 vberai 定价/升级页时追加来源标记(便于后端统计转化来源)。已带 utm 或空则原样返回。
func _with_utm(url: String) -> String:
	# 只给 http(s) 外链加来源标记;mailto / 微信号 / 自定义 scheme / 本地路径 / 系统 URI
	# 一律原样放行,故可安全套在所有 OS.shell_open 上。已带 utm 或空则不动。
	if not url.begins_with("http") or url.contains("utm_source="):
		return url
	return url + ("&" if url.contains("?") else "?") + "utm_source=godot-mcp"


# 权限不足弹窗:确定按钮=「前往升级订阅」→ 打开充值入口;关闭(X/Esc)则仅取消。
# plan_name 非空时追加「升级到「X」即可使用」(文档 §4.1 的 requiredPlan)。
func _show_no_entitlement_dialog(upgrade_url: String, plan_name: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = _t("no_entitlement_title")
	var body := _t("acct_no_entitlement")
	if plan_name != "":
		body += "\n" + _t("acct_upgrade_to").format([plan_name])
	dlg.dialog_text = body
	dlg.ok_button_text = _t("acct_upgrade")
	dlg.exclusive = false
	dlg.confirmed.connect(func(): OS.shell_open(_with_utm(upgrade_url)))
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()


func _update_dock_ui() -> void:
	if not dock:
		return

	# Use find_child to locate nested nodes
	var running: bool = mcp_server != null and bool(mcp_server.is_running())
	var status_value = dock.find_child("StatusValue", true, false)
	var info_label = dock.find_child("InfoLabel", true, false)

	if status_value:
		if running:
			status_value.text = _t("running")
			status_value.add_theme_color_override("font_color", Color.GREEN)
		else:
			status_value.text = _t("stopped")
			status_value.add_theme_color_override("font_color", Color.RED)

	if info_label:
		info_label.text = _t("lbl_endpoint") + ("http://%s:%d/mcp" % [settings.host, _effective_port()])

	_apply_port_fallback()



	# Grey out whichever action doesn't apply to the current state.
	var start_btn = dock.find_child("StartButton", true, false) as Button
	var stop_btn = dock.find_child("StopButton", true, false) as Button
	if start_btn: start_btn.disabled = running
	if stop_btn: stop_btn.disabled = not running

	# access token 快到期(<5 分钟)且当前无账号操作 → 后台静默续期,
	# 避免正在用的 MCP 客户端突然被登录门禁拦下。60s 退避:断网时
	# needs_refresh 一直为 true,不能 1Hz 连环发请求。
	if mcp_server != null and not _account_busy and mcp_server.vber_needs_refresh():
		var now := Time.get_ticks_msec()
		if now - _last_refresh_msec >= 60000:
			_last_refresh_msec = now
			_start_account_op("refresh")

	# 多设备踢出:处于「可用」态时每 30s 后台核对会话是否被别的设备顶掉。
	# 一旦被踢,state 变 kicked → _account_active() 为假 → 停止轮询(只查一次)。
	if mcp_server != null and not _account_busy and _account_active():
		var now2 := Time.get_ticks_msec()
		if now2 - _last_session_check_msec >= 30000:
			_last_session_check_msec = now2
			_start_account_op("check_session")


func _on_start_pressed() -> void:
	if not mcp_server:
		return

	# 每次启动重新判定,上一轮的回落提示不能留到这一轮。
	_port_fallback = {}

	# Get port from UI (PortSpinBox is inside PortContainer)
	var port_spin = dock.find_child("PortSpinBox", true, false) as SpinBox
	var requested := int(settings.port)
	if port_spin:
		var new_port := int(port_spin.value)
		# settings 是无类型 Dictionary,settings.port 取出来是 Variant,比较结果
		# 同样推断不出类型 —— 用 := 会直接让整个脚本解析失败,必须显式标注。
		var port_changed: bool = new_port != settings.port
		requested = new_port
		settings.port = new_port
		mcp_server.set_port(settings.port)
		print("[Godot MCP] Starting server on port %d" % settings.port)
		# 端口变了:已经配置过的客户端(Claude/Cursor 等)配置文件里还是旧端口——
		# "配置"按钮一旦配置过就永久 disabled,用户没有入口重新触发写入,
		# 所以这里在端口真的变化时主动重写一遍已配置过的客户端。
		if port_changed:
			_resync_configured_clients()

	mcp_server.start()
	# 端口被占用时 start() 会往上找一个能用的。那个端口就是这个项目从现在起用的端口:
	# 存回 settings、回填端口框,并 set_port 让 C++ 侧一起对齐 —— 少了最后这步,
	# 停服后 get_active_port() 会退回没绑上的旧端口,endpoint 和一键配置全跟着错。
	if mcp_server.is_running():
		var bound := int(mcp_server.get_active_port())
		if bound > 0 and bound != requested:
			_port_fallback = {"requested": requested, "actual": bound}
			settings.port = bound
			mcp_server.set_port(bound)
			if port_spin:
				port_spin.value = bound
			_resync_configured_clients()
			print("[Godot MCP] Port %d unusable, bound %d — resynced configured clients"
				% [requested, bound])
	_update_dock_ui()
	_save_settings()


func _on_stop_pressed() -> void:
	if mcp_server:
		mcp_server.stop()
	# 提示说的是"这次跑在哪个端口上",服务停了就没有意义了。
	_port_fallback = {}
	_update_dock_ui()


func _on_auto_start_toggled(pressed: bool) -> void:
	settings.auto_start = pressed
	_save_settings()


func _on_lang_selected(idx: int) -> void:
	if idx < 0 or idx >= LANG_OPTIONS.size():
		return
	settings.lang = LANG_OPTIONS[idx][0]
	_save_settings()
	_locale = _detect_locale()
	# OptionButton 的 item_selected 信号仍在派发时，不能同步销毁它所在的
	# Dock 树；否则旧控件会短暂残留，出现中英文混合。等本帧回调结束后
	# 统一重建整个 Dock。
	call_deferred("_rebuild_dock")


func _on_debug_toggled(pressed: bool) -> void:
	settings.debug_mode = pressed
	if mcp_server:
		mcp_server.set_debug_mode(pressed)
	_save_settings()


func _restore_saved_credentials() -> void:
	# 恢复上次登录的邮箱(密码出于安全不存,需重新输入)。
	_saved_email = String(settings.get("saved_email", ""))
	# 清除任何旧版本可能存过的明文密码。
	if settings.has("saved_password"):
		settings.erase("saved_password")
		_save_settings()


# 从 plugin.cfg 读版本号(单一真源)。打包/安装后路径不变,故 dev 与发布态一致。
func _read_plugin_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("res://addons/godot_mcp/plugin.cfg") == OK:
		return String(cfg.get_value("plugin", "version", "0.0.0"))
	return "0.0.0"


func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			var error = json.parse(file.get_as_text())
			if error == OK:
				var data = json.get_data()
				if data is Dictionary:
					settings.merge(data, true)
			file.close()


func _save_settings() -> void:
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()


# Public API for external access
func get_server() -> Node:
	return mcp_server


func start_server() -> void:
	_on_start_pressed()


func stop_server() -> void:
	_on_stop_pressed()


# ===== 一键配置:自动读写客户端 MCP 配置文件 =====

# AI 客户端及其配置文件路径/格式。file 不存在时一键配置会提示失败(见 _do_client_add)。
#   fmt="json": 读写 JSON;key=顶层键(mcpServers 或 servers);entry=写入的服务器条目
#   fmt="toml": Codex 的 config.toml,写 [mcp_servers.<name>] 段
func _ai_clients() -> Array:
	# `paths` = 候选路径(按序取第一个存在的;都不在则用第 1 个作默认/提示)。
	# Windows 覆盖 Roaming(%APPDATA%)/Local(%LOCALAPPDATA%)/Insiders 等变体。
	var win := OS.get_name() == "Windows"
	var home := OS.get_environment("USERPROFILE") if win else OS.get_environment("HOME")
	var roaming := ""
	var localapp := ""
	if win:
		roaming = OS.get_environment("APPDATA")
		localapp = OS.get_environment("LOCALAPPDATA")
	elif OS.get_name() == "Linux":
		roaming = home + "/.config"
		localapp = roaming
	else:
		roaming = home + "/Library/Application Support"
		localapp = roaming
	var url := "http://127.0.0.1:%d/mcp" % _effective_port()
	return [
		{"id": "cursor", "name": "Cursor", "paths": [home + "/.cursor/mcp.json"],
			"fmt": "json", "key": "mcpServers", "entry": {"url": url}},
		{"id": "windsurf", "name": "Windsurf", "paths": [home + "/.codeium/windsurf/mcp_config.json"],
			"fmt": "json", "key": "mcpServers", "entry": {"serverUrl": url}},
		{"id": "trae", "name": "Trae", "paths": [roaming + "/Trae/User/mcp.json", roaming + "/Trae CN/User/mcp.json"],
			"fmt": "json", "key": "mcpServers", "entry": {"url": url},
			"scan": {"roots": [roaming, localapp], "name": "Trae", "rel": "User/mcp.json"}},
		{"id": "vscode", "name": "VS Code", "paths": [roaming + "/Code/User/mcp.json", roaming + "/Code - Insiders/User/mcp.json"],
			"fmt": "json", "key": "servers", "entry": {"type": "http", "url": url},
			"scan": {"roots": [roaming, localapp], "name": "Code", "rel": "User/mcp.json"}},
		{"id": "kiro", "name": "Kiro", "paths": [home + "/.kiro/settings/mcp.json"],
			"fmt": "json", "key": "mcpServers", "entry": {"type": "streamable-http", "url": url, "disabled": false, "autoApprove": []}},
		{"id": "qoder", "name": "Qoder", "paths": [roaming + "/Qoder/SharedClientCache/mcp.json", localapp + "/Qoder/SharedClientCache/mcp.json"],
			"fmt": "json", "key": "mcpServers", "entry": {"url": url},
			"scan": {"roots": [roaming, localapp], "name": "Qoder", "rel": "SharedClientCache/mcp.json"}},
		{"id": "codex", "name": "Codex", "paths": [home + "/.codex/config.toml"],
			"fmt": "toml", "key": "", "entry": {}},
		{"id": "devin", "name": "Devin", "paths": [roaming + "/Devin/User/mcp.json", localapp + "/Devin/User/mcp.json"],
			"fmt": "json", "key": "servers", "entry": {"type": "http", "url": url},
			"scan": {"roots": [roaming, localapp], "name": "Devin", "rel": "User/mcp.json"}},
	]


# 从候选路径里取第一个已存在的;都不在则扫描已知父目录兜底;再不行返回第 1 个(默认,用于显示/失败提示)。
func _client_path(client: Dictionary) -> String:
	var paths: Array = client.get("paths", [])
	for p in paths:
		if FileAccess.file_exists(String(p)):
			return String(p)
	var scanned := _scan_for_config(client)
	if scanned != "":
		return scanned
	return String(paths[0]) if paths.size() > 0 else ""


# 兜底:在 scan.roots 各父目录下,找名字匹配 scan.name(如 "Code" 命中 "Code - Insiders")
# 且其内含 scan.rel 配置文件的子目录。只列一层、要求文件真实存在,避免误判。
func _scan_for_config(client: Dictionary) -> String:
	var scan: Dictionary = client.get("scan", {})
	if scan.is_empty():
		return ""
	var want := String(scan.get("name", "")).to_lower()
	var rel := String(scan.get("rel", ""))
	if want == "" or rel == "":
		return ""
	for root in scan.get("roots", []):
		var dir := DirAccess.open(String(root))
		if dir == null:
			continue
		dir.list_dir_begin()
		var sub := dir.get_next()
		while sub != "":
			if dir.current_is_dir() and sub != "." and sub != "..":
				var low := sub.to_lower()
				if low == want or low.begins_with(want + " ") or low.begins_with(want + "-"):
					var candidate := String(root).path_join(sub).path_join(rel)
					if FileAccess.file_exists(candidate):
						dir.list_dir_end()
						return candidate
			sub = dir.get_next()
		dir.list_dir_end()
	return ""


func _read_text_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _write_text_file(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return false
	f.store_string(text)
	f.close()
	return true


# Codex 的 TOML:段头 [mcp_servers.<name>]。手动增删(Godot 无内置 TOML)。
func _toml_section() -> String:
	return "[mcp_servers.%s]" % SERVER_NAME


func _toml_has_server(text: String) -> bool:
	for line in text.split("\n"):
		if line.strip_edges() == _toml_section():
			return true
	return false


func _toml_add_server(text: String, url: String) -> String:
	if _toml_has_server(text):
		return text
	var t := text
	if t != "" and not t.ends_with("\n"):
		t += "\n"
	t += "\n%s\nurl = \"%s\"\n" % [_toml_section(), url]
	return t


func _toml_remove_server(text: String) -> String:
	var out: Array = []
	var skip := false
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s == _toml_section():
			skip = true
			continue
		if skip:
			if s.begins_with("["):
				skip = false
				out.append(line)
			continue
		out.append(line)
	return "\n".join(out)


func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	return d if d is Dictionary else {}


func _write_json_file(path: String, data: Dictionary) -> bool:
	var d := path.get_base_dir()
	if d != "" and not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true


func _client_configured(client: Dictionary) -> bool:
	var path := _client_path(client)
	if not FileAccess.file_exists(path):
		return false
	if String(client.get("fmt", "json")) == "toml":
		return _toml_has_server(_read_text_file(path))
	var top = _read_json_file(path).get(String(client.get("key", "mcpServers")))
	return top is Dictionary and top.has(SERVER_NAME)


func _do_client_add(client: Dictionary) -> void:
	var path := _client_path(client)
	# 配置文件不存在 = 该客户端多半没装在默认路径 → 不臆造文件,弹窗提示失败。
	if not FileAccess.file_exists(path):
		push_warning("[Godot MCP] config file not found (client not at default path?): " + path)
		_show_message(_t("config_failed_detail").format([String(client.name)]))
		return
	var url := "http://127.0.0.1:%d/mcp" % _effective_port()
	var ok := false
	if String(client.get("fmt", "json")) == "toml":
		ok = _write_text_file(path, _toml_add_server(_read_text_file(path), url))
	else:
		var d := _read_json_file(path)
		var key := String(client.get("key", "mcpServers"))
		if not (d.get(key) is Dictionary):
			d[key] = {}
		d[key][SERVER_NAME] = client.get("entry", {"url": url})
		ok = _write_json_file(path, d)
	if ok:
		print("[Godot MCP] configured %s -> %s" % [client.name, path])
		_refresh_config_tab()
	else:
		push_warning("[Godot MCP] failed to write " + path)
		_show_message(_t("config_failed"))


# 弹出一个编辑器提示对话框(用于配置失败等提示)。
func _show_message(msg: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = _t("config_failed")
	dlg.dialog_text = msg
	dlg.exclusive = false
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()


# ===== 版本更新检查(服务端下发 → 弹窗)=====

# 产品 API 基址与 VberAI 账号 API 使用同一环境配置。
func _update_server_base() -> String:
	if mcp_server:
		var web_base := String(mcp_server.vber_status().get("webBase", "")).strip_edges()
		if web_base.contains("test.vberai.com"):
			return "https://test-studio.vberai.com/api"
		if web_base.contains("vberai.com"):
			return UPDATE_API_DEFAULT
	return UPDATE_API_DEFAULT


# 向后端查一次当前推送版本。manual=true 表示用户手动点「检查更新」。
func _check_for_update(manual: bool) -> void:
	if not _update_http:
		return
	# 编辑器启动会先自动检查。此时用户马上点「检查更新」不能直接丢弃；
	# 复用正在进行的请求，并在完成后按手动检查展示结果。
	if _update_busy:
		_update_manual = _update_manual or manual
		return
	_update_manual = manual
	_update_busy = true
	var url := "%s/v1/products/%s/version?edition=%s" % [
		_update_server_base(), UPDATE_PRODUCT_CODE, UPDATE_EDITION]
	var err := _update_http.request(url, PackedStringArray(["Accept: application/json"]))
	if err != OK:
		_update_busy = false
		if manual:
			_show_update_info(_t("update_no_update"))


func _on_update_http_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_update_busy = false
	var manual := _update_manual
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[Godot MCP] update check: 没有有效响应(result=%d, http=%d)——多半打错后端或该接口未部署" % [result, code])
		if manual:
			_show_update_info(_t("update_no_update"))
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		print("[Godot MCP] update check: 响应不是合法 JSON,已忽略")
		if manual:
			_show_update_info(_t("update_no_update"))
		return
	var root = json.get_data()
	var payload: Dictionary = root.get("data", {}) if root is Dictionary else {}
	var raw_version = payload.get("version", null)
	var latest := String(raw_version).strip_edges() if raw_version is String else ""
	var has_update := latest != "" and _version_newer(latest, PLUGIN_VERSION)
	var notes = payload.get("releaseNotes", {})
	payload["changelog"] = _localized_release_notes(notes)
	var released_at = payload.get("releasedAt", null)
	payload["releaseDate"] = String(released_at) if released_at is String else ""
	payload["downloadUrl"] = UPDATE_FALLBACK_DOWNLOAD
	payload["urgency"] = "normal"
	# 无更新 / 版本不更新 → 手动时提示「已最新」,自动时静默。
	if not has_update:
		if manual:
			_show_update_info(_t("update_no_update"))
		return
	var urgency := String(payload.get("urgency", "normal"))
	# 「跳过」抑制:自动检查且已跳过该版本且非 critical → 不弹(手动检查始终弹)。
	if not manual and urgency != "critical" and String(settings.get("skipped_version", "")) == latest:
		return
	_show_update_dialog(payload, latest, urgency)


func _localized_release_notes(notes: Variant) -> String:
	if notes is String:
		return String(notes)
	if not notes is Dictionary:
		return ""
	# 覆盖面板提供翻译的全部语言。ru/pt/ar 之前不在表里，只能靠原样透传碰运气。
	var locale_map := {
		"zh": "zh-CN", "en": "en-US", "ja": "ja", "ko": "ko",
		"es": "es", "fr": "fr", "de": "de", "vi": "vi",
		"ru": "ru", "pt": "pt", "ar": "ar", "hi": "hi"
	}
	var wanted := String(locale_map.get(_locale, _locale))
	# 英文优先于中文：服务端没有该语言版本时，英文是更合理的通用兜底。
	# 旧顺序会把中文塞给德语用户。
	for key in [wanted, "en-US", "zh-CN"]:
		var raw_value = notes.get(key, null)
		var value := String(raw_value).strip_edges() if raw_value is String else ""
		if value != "":
			return value
	for raw_value in notes.values():
		var text := String(raw_value).strip_edges() if raw_value is String else ""
		if text != "":
			return text
	return ""


# 逐段数字比较:a 严格大于 b 才算「更新」(与 cocos isNewerVersion 一致)。
func _version_newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	var n := maxi(pa.size(), pb.size())
	for i in n:
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return x > y
	return false


# 手动检查「已是最新 / 出错」时的轻提示。
func _show_update_info(msg: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = _t("brand_name")
	dlg.dialog_text = msg
	dlg.exclusive = false
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()


# 弹「发现新版本」弹窗:立即更新 / 暂不更新 / 跳过该版本。
func _show_update_dialog(info: Dictionary, latest: String, urgency: String) -> void:
	if _update_dialog and is_instance_valid(_update_dialog):
		_update_dialog.queue_free()
	var download := String(info.get("downloadUrl", "")).strip_edges()
	if download == "":
		download = UPDATE_FALLBACK_DOWNLOAD
	var changelog := String(info.get("changelog", "")).strip_edges()
	var release := String(info.get("releaseDate", "")).strip_edges()

	var dlg := AcceptDialog.new()
	_update_dialog = dlg
	dlg.exclusive = false
	# 标题按紧急程度切换。
	if urgency == "critical":
		dlg.title = _t("update_urgency_critical")
	elif urgency == "high":
		dlg.title = _t("update_urgency_high")
	else:
		dlg.title = _t("update_available_title")
	# 正文:新版本 / 当前版本 / 发布日期 / 更新日志(服务端原文)。
	var lines := PackedStringArray()
	lines.append(_t("update_new_version").format([latest]))
	lines.append(_t("update_current_version").format([PLUGIN_VERSION]))
	if release != "":
		lines.append("📅 " + release.substr(0, 10))
	if changelog != "":
		lines.append("")
		lines.append(_t("update_changelog") + ":")
		lines.append(changelog)
	dlg.dialog_text = "\n".join(lines)
	# OK 按钮 = 「立即更新」→ 打开下载页。
	dlg.ok_button_text = _t("update_now")
	dlg.confirmed.connect(func(): OS.shell_open(_with_utm(download)))
	# 「跳过该版本」自定义按钮:记录到 settings;自定义按钮不会自动关闭,需手动 hide。
	dlg.add_button(_t("update_skip_version").format([latest]), false, "skip")
	dlg.custom_action.connect(func(action):
		if String(action) == "skip":
			settings.skipped_version = latest
			_save_settings()
		dlg.hide())
	# 「暂不更新」= 取消按钮(仅关闭,下次检查还会再弹)。
	dlg.add_cancel_button(_t("update_not_now"))
	# 关闭后释放,避免堆积。
	dlg.visibility_changed.connect(func():
		if is_instance_valid(dlg) and not dlg.visible:
			if _update_dialog == dlg:
				_update_dialog = null
			dlg.queue_free())
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()


func _do_client_remove(client: Dictionary) -> void:
	var path := _client_path(client)
	if not FileAccess.file_exists(path):
		_refresh_config_tab()
		return
	if String(client.get("fmt", "json")) == "toml":
		_write_text_file(path, _toml_remove_server(_read_text_file(path)))
	else:
		var d := _read_json_file(path)
		var key := String(client.get("key", "mcpServers"))
		if d.get(key) is Dictionary and d[key].has(SERVER_NAME):
			d[key].erase(SERVER_NAME)
			_write_json_file(path, d)
	print("[Godot MCP] removed %s from %s" % [SERVER_NAME, path])
	_refresh_config_tab()


# 重新写入所有"已经配置过"该服务器的客户端。JSON 客户端的 _do_client_add 本身就是
# 直接覆盖写入,直接调用即可跟上新端口;但 Codex 用的 TOML 格式里 _toml_add_server
# 遇到已存在的段会直接跳过不写,所以 TOML 客户端要先删再加。
# 只处理已配置过的客户端,不会给从未点过"配置"的客户端凭空创建配置。
# 服务真正监听的端口。settings.port 只是首选值：被别的项目占用时 start() 会
# 往上找一个能绑的端口，客户端配置、endpoint 显示、健康检查都必须跟着实际端口走，
# 否则第二个项目里的一切都指向一个没人应答的端口。
func _effective_port() -> int:
	if mcp_server != null and mcp_server.has_method("get_active_port"):
		var p := int(mcp_server.get_active_port())
		if p > 0:
			return p
	return int(settings.port)


# 端口回落后刷新提示条并把已配置过的客户端重新指到新端口。
# 纯显示：回落的判定和客户端重同步都在 _on_start_pressed 里一次做完
# (这里是 1Hz 轮询调用的,不能在这写盘)。
func _apply_port_fallback() -> void:
	if not dock:
		return
	var notice = dock.find_child("PortFallbackLabel", true, false) as Label
	if not notice:
		return
	if _port_fallback.is_empty():
		notice.visible = false
		return
	notice.text = _t("port_fallback_notice") % [
		int(_port_fallback.get("requested", 0)), int(_port_fallback.get("actual", 0))]
	notice.visible = true


func _resync_configured_clients() -> void:
	for client in _ai_clients():
		if not _client_configured(client):
			continue
		if String(client.get("fmt", "json")) == "toml":
			_do_client_remove(client)
		_do_client_add(client)


func _refresh_config_tab() -> void:
	# 只就地重建「一键配置」页,不动整面板 / 不切页签(避免跳回服务器页)。
	if not dock:
		return
	var tc := dock.find_child("TabConfig", true, false) as VBoxContainer
	if tc:
		for c in tc.get_children():
			tc.remove_child(c)
			c.queue_free()
		_build_config_tab(tc)


func _open_dir(dir: String) -> void:
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	OS.shell_open(dir)


# ===== 多语言 =====

func _load_translations() -> void:
	_i18n.clear()
	for loc in LOCALES:
		var p := "res://addons/godot_mcp/i18n/%s.po" % loc
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f:
				_i18n[loc] = _parse_po(f.get_as_text())
				f.close()
	_locale = _detect_locale()
	if not _i18n.has(_locale):
		_locale = "en"


func _detect_locale() -> String:
	# Manual override wins; empty string means follow the editor language.
	var pinned := String(settings.get("lang", "")).strip_edges()
	if pinned != "" and pinned in LOCALES:
		return pinned
	var code := ""
	var es := EditorInterface.get_editor_settings()
	if es:
		code = String(es.get_setting("interface/editor/editor_language"))
	if code.strip_edges() == "":
		code = TranslationServer.get_locale()
	return _normalize_locale(code)


func _normalize_locale(code: String) -> String:
	code = code.strip_edges().to_lower()
	if code.begins_with("zh"):
		# 繁体在 Godot 编辑器里是独立一档(zh_TW/zh_HK),别跟简体混成一个。
		return "zh_TW" if (code.contains("tw") or code.contains("hk")) else "zh"
	# 先按整码匹配再退回两位码:"fil".substr(0, 2) 是 "fi",那是芬兰语不是菲律宾语。
	for loc in LOCALES:
		if code == String(loc).to_lower():
			return loc
	var two := code.substr(0, 2)
	return two if two in LOCALES else "en"


func _t(key: String) -> String:
	var d: Dictionary = _i18n.get(_locale, {})
	if d.has(key) and String(d[key]) != "":
		return String(d[key])
	var en: Dictionary = _i18n.get("en", {})
	if en.has(key) and String(en[key]) != "":
		return String(en[key])
	return key


# 工具分类的本地化显示名(cat_<category>);缺失则回退原始英文分类名。
func _cat_display(cat: String) -> String:
	var k := "cat_" + cat
	var v := _t(k)
	return cat if v == k else v


# 工具详情文本:优先本地化(tooldetail_<full_name>);否则去掉「标题:摘要」首段、
# 显示后续详细说明;若描述只有单段(纯标题)则返回空(工具行只显示名称)。
func _tool_detail(desc: String, name: String) -> String:
	var key := "tooldetail_" + name
	var loc := _t(key)
	if loc != key and loc != "":
		return loc
	var parts := desc.split("\n\n", false)
	if parts.size() >= 2:
		var rest := ""
		for i in range(1, parts.size()):
			rest += parts[i] + "\n\n"
		return rest.strip_edges()
	return ""


# Minimal gettext .po parser (msgid/msgstr pairs + quoted continuations).
func _parse_po(text: String) -> Dictionary:
	var out := {}
	var cur_id := ""
	var mode := ""  # "id" | "str"
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("msgid "):
			cur_id = _po_unquote(line.substr(6))
			mode = "id"
		elif line.begins_with("msgstr "):
			var s := _po_unquote(line.substr(7))
			if cur_id != "":
				out[cur_id] = s
			mode = "str"
		elif line.begins_with("\""):
			var frag := _po_unquote(line)
			if mode == "id":
				cur_id += frag
			elif mode == "str" and cur_id != "":
				out[cur_id] = String(out.get(cur_id, "")) + frag
	return out


func _po_unquote(s: String) -> String:
	s = s.strip_edges()
	if s.begins_with("\""):
		s = s.substr(1)
	if s.ends_with("\""):
		s = s.substr(0, s.length() - 1)
	s = s.replace("\\n", "\n").replace("\\t", "\t").replace("\\\"", "\"").replace("\\\\", "\\")
	return s


# ===== UI 样式辅助 =====

func _sc(n: int) -> int:
	# Scale logical px by the editor's HiDPI scale so the panel matches the
	# rest of the editor (fixed px otherwise render half-size on Retina).
	return int(round(n * maxf(EditorInterface.get_editor_scale(), 1.0)))


func _flat_style(bg: Color, border: Color, border_w: int, radius: int, pad_h: int, pad_v: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border_w > 0:
		sb.set_border_width_all(_sc(border_w))
		sb.border_color = border
	sb.set_corner_radius_all(_sc(radius))
	sb.content_margin_left = _sc(pad_h)
	sb.content_margin_right = _sc(pad_h)
	sb.content_margin_top = _sc(pad_v)
	sb.content_margin_bottom = _sc(pad_v)
	return sb


func _style_primary_button(b: Button) -> void:
	var blue := Color("007acc")
	var blue_hover := Color("0098ff")
	b.add_theme_stylebox_override("normal", _flat_style(blue, blue, 0, 4, 9, 5))
	b.add_theme_stylebox_override("hover", _flat_style(blue_hover, blue_hover, 0, 4, 9, 5))
	b.add_theme_stylebox_override("pressed", _flat_style(blue.darkened(0.1), blue, 0, 4, 9, 5))
	b.add_theme_stylebox_override("disabled", _flat_style(Color(blue, 0.5), blue, 0, 4, 9, 5))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	b.add_theme_font_size_override("font_size", _sc(12))


func _style_secondary_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _flat_style(Color("3a3a3a"), Color("505050"), 1, 4, 8, 4))
	b.add_theme_stylebox_override("hover", _flat_style(Color("454545"), Color("606060"), 1, 4, 8, 4))
	b.add_theme_stylebox_override("pressed", _flat_style(Color("303030"), Color("505050"), 1, 4, 8, 4))
	b.add_theme_color_override("font_color", Color("dddddd"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", _sc(11))


func _style_tab_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _flat_style(Color("2f2f2f"), Color("2f2f2f"), 0, 4, 9, 5))
	b.add_theme_stylebox_override("hover", _flat_style(Color("383838"), Color("383838"), 0, 4, 9, 5))
	var act := _flat_style(Color(Color("007acc"), 0.18), Color("007acc"), 1, 4, 9, 5)
	b.add_theme_stylebox_override("pressed", act)
	b.add_theme_stylebox_override("hover_pressed", act)
	b.add_theme_color_override("font_color", Color("aaaaaa"))
	b.add_theme_color_override("font_pressed_color", Color("4aa3ff"))
	b.add_theme_color_override("font_hover_color", Color("dddddd"))
	b.add_theme_font_size_override("font_size", _sc(12))


func _on_tab_pressed(tab_id: String) -> void:
	if not dock: return
	for entry in [["server", "TabServer"], ["tools", "TabTools"], ["config", "TabConfig"]]:
		var content = dock.find_child(entry[1], true, false)
		if content: content.visible = (entry[0] == tab_id)
		var btn = dock.find_child("Tab_" + entry[0], true, false) as Button
		if btn: btn.button_pressed = (entry[0] == tab_id)
	if tab_id == "tools":
		_fetch_tools_list()


func _fetch_tools_list() -> void:
	if not mcp_server or not mcp_server.is_running():
		_set_tool_list_message(_t("tools_not_running"))
		return
	if not _tools_http: return
	_tools_http.cancel_request()
	var body := JSON.stringify({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
	_tools_http.request("http://127.0.0.1:%d/mcp" % _effective_port(),
		["Content-Type: application/json", "Accept: application/json, text/event-stream"],
		HTTPClient.METHOD_POST, body)


func _on_tools_http_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var tl = dock.find_child("ToolList", true, false)
	if not tl: return
	for c in tl.get_children():
		c.queue_free()
	if code <= 0:
		_set_tool_list_message(_t("tools_fetch_failed"))
		return
	var parsed = _parse_mcp_response(body.get_string_from_utf8())
	var tools := []
	if parsed is Dictionary and parsed.has("result"):
		var r = parsed["result"]
		if r is Dictionary: tools = r.get("tools", [])

	# 按分类分组(MCP 工具名格式 = "<category>_<action>")。
	var by_cat := {}
	for t in tools:
		if not t is Dictionary: continue
		var nm := String(t.get("name", ""))
		var cat := (nm.split("_", true, 1)[0]) if nm.find("_") >= 0 else "other"
		if not by_cat.has(cat): by_cat[cat] = []
		by_cat[cat].append(t)
	if by_cat.is_empty():
		_set_tool_list_message(_t("tools_fetch_failed"))
		return
	var cats := by_cat.keys()
	cats.sort()

	# 每个分类一个可折叠的标题(▾/▸ + 本地化名称 + 数量),下面是本地化简介 + 该类工具。
	for cat in cats:
		var items: Array = by_cat[cat]
		var cat_disp := _cat_display(String(cat))
		var hdr = Button.new()
		hdr.text = "▾  %s  (%d)" % [cat_disp, items.size()]
		# Button.alignment 是物理左右,不随 layout_direction 自动镜像,得自己翻。
		hdr.alignment = HORIZONTAL_ALIGNMENT_RIGHT if _is_rtl() else HORIZONTAL_ALIGNMENT_LEFT
		hdr.toggle_mode = true
		hdr.button_pressed = true
		_style_tab_button(hdr)
		tl.add_child(hdr)
		var sub = VBoxContainer.new()
		sub.add_theme_constant_override("separation", _sc(2))
		tl.add_child(sub)
		# 分类的一句话本地化简介
		var summary := _t("catdesc_" + String(cat))
		if summary != "" and summary != "catdesc_" + String(cat):
			var sl = Label.new()
			sl.text = summary
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sl.add_theme_color_override("font_color", Color("888888"))
			sl.add_theme_font_size_override("font_size", _sc(10))
			sub.add_child(sl)
		# 工具名(标识符,不翻译)+ 详情(去掉「标题:摘要」首段,余下本地化显示)。
		for t in items:
			var nm2 = String(t.get("name", ""))
			var trow = VBoxContainer.new()
			trow.add_theme_constant_override("separation", 0)
			var nl = Label.new()
			nl.text = "    • " + nm2
			nl.add_theme_color_override("font_color", Color("cccccc"))
			nl.add_theme_font_size_override("font_size", _sc(11))
			trow.add_child(nl)
			var detail := _tool_detail(String(t.get("description", "")), nm2)
			if detail != "":
				var dl = Label.new()
				dl.text = "        " + detail
				dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				dl.add_theme_color_override("font_color", Color("888888"))
				dl.add_theme_font_size_override("font_size", _sc(10))
				trow.add_child(dl)
			sub.add_child(trow)
		var cat_name := cat_disp
		var cnt := items.size()
		# 折叠箭头指向内容展开的方向:RTL 下是向左(◂),不是向右(▸)。
		var collapsed_arrow := "◂  " if _is_rtl() else "▸  "
		hdr.toggled.connect(func(p):
			sub.visible = p
			hdr.text = ("▾  " if p else collapsed_arrow) + "%s  (%d)" % [cat_name, cnt])


func _set_tool_list_message(msg: String) -> void:
	var tl = dock.find_child("ToolList", true, false)
	if not tl: return
	for c in tl.get_children():
		c.queue_free()
	var w = Label.new()
	w.text = msg
	w.add_theme_color_override("font_color", Color("dc3545"))
	w.add_theme_font_size_override("font_size", _sc(11))
	tl.add_child(w)


func _parse_mcp_response(text: String) -> Variant:
	# /mcp may answer as plain JSON or as SSE ("data: {...}"). Handle both.
	var j = JSON.parse_string(text)
	if j != null: return j
	for line in text.split("\n"):
		var ls := line.strip_edges()
		if ls.begins_with("data:"):
			var jd = JSON.parse_string(ls.substr(5).strip_edges())
			if jd != null: return jd
	return null


func _mcp_client_config_json() -> String:
	return '{\n  "mcpServers": {\n    "godot-mcp": {\n      "url": "http://127.0.0.1:%d/mcp"\n    }\n  }\n}' % _effective_port()


func _mcp_cli_command() -> String:
	return "claude mcp add --transport http godot-mcp http://127.0.0.1:%d/mcp" % _effective_port()


# CLI 一键接入命令。
func _cli_commands() -> Array:
	var url := "http://127.0.0.1:%d/mcp" % _effective_port()
	return [
		{"label": "Claude", "cmd": "claude mcp add --transport http godot-mcp " + url},
		{"label": "Gemini", "cmd": "gemini mcp add godot-mcp " + url + " --transport http"},
	]


func _copy_to_clipboard(text: String, btn: Button) -> void:
	DisplayServer.clipboard_set(text)
	if btn:
		var old := btn.text
		btn.text = _t("copied")
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(btn): btn.text = old
