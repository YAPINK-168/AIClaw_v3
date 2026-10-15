# HANDOVER-001 表现模块 B 与业务流程模块 A 协作交接

- 审查日期：2026-10-15
- 项目：`E:\GodotProjects\ai-claw-v-3`（Godot 工程名 `AIClaw_v3`）
- 引擎：Godot 4.7.2 stable mono（日志标识 `v4.7.2.stable.mono.official.ed1daf0bf`）
- 审查方式：只读核对当前脚本、场景、资源和本机已有运行日志。本次未改代码，未重跑测试，未调用云端接口。
- 放置说明：仓库里没有独立的开发文档目录。现有设计文档与本文件同在项目根目录。本次未新建目录。

状态用词：

| 标记 | 含义 |
| --- | --- |
| 已实现 | 当前源码中存在可执行路径 |
| 已测试 | 2026-10-15 的 Godot 日志里能对上当前源码行为 |
| 尚未验证 | 源码或命令存在，但没有与当前源码对应的通过记录 |
| 结果过期 | 磁盘上有旧输出，其内容对不上当前源码 |
| 尚未实现 | 当前工程中没有对应脚本、场景或调用 |

根目录另有三份 Word 文档：`DEV-PLAN-001_AI数字人交互系统开发蓝图.docx`、`TECH-DESIGN-001_AI数字人交互系统技术设计文档.docx`、`AI数字人交互系统_硬件待确认事项更新表.docx`。本交接只依据当前代码和日志，不把这些文档里的规划当成已实现功能。

---

## A. 项目现状清单

### A.1 总览

表现预览是当前唯一可运行的产品路径，全部为 GDScript。`project.godot` 写了 `[dotnet] project/assembly_name="AIClaw_v3"`，编辑器记录的可执行文件是 `D:/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64.exe`，但工程内没有 `.cs`、`.csproj`、`.sln`。业务流程模块 A、小游戏模块、语音播放都尚未实现。

主场景：

| 项 | 值 |
| --- | --- |
| 主场景 | `res://scenes/youyou/youyou_preview.tscn` |
| 根节点 | `YouyouPreview`（`Node3D`） |
| 根脚本 | `res://Scripts/youyou_preview.gd`（无 `class_name`） |
| 模型 | `res://柚柚.glb`，运行时实例名 `YouyouModel` |
| 骨架 | `Armature/Skeleton3D`，根骨 `mixamorig_Hips` |
| 动画播放器 | 运行时创建的 `YouyouModel/PreviewAnimationPlayer`（空库名 `""`） |
| 面部节点 | 运行时创建的 `YouyouFacePresenter` |
| 姿态节点 | 运行时创建的 `YouyouPerformancePoseController` |
| 镜头 | `ObservePivot/Camera3D`，脚本 `res://Scripts/youyou_observe_camera.gd`（无 `class_name`） |

`project.godot` 的 `run/main_scene` 指向上述预览场景。`res://Scripts/first.gd` 是空模板，未挂到任何场景。`assets/` 目录为空。

### A.2 表现能力

| 能力 | 状态 | 文件与入口 | 测试 | 已知问题 |
| --- | --- | --- | --- | --- |
| 加载柚柚、隐藏名为 `耳机` 的网格、循环播放 `Basic_Idle` | 已实现，交互已跑通 | `youyou_preview.gd`：`_load_model`、`_hide_headphones`、`_start_idle` | 2026-10-15 `godot.log` 有“播放待机 Basic_Idle” | 基础待机或招揽 01 加载失败时 `_ready` 直接返回，没有对外失败信号 |
| 轻待机调度 | 已实现，交互已跑通 | `_arm_wait`、`_on_light_wait_timeout`、`_play_auto_light`；定时器节点 `LightIdleWait` | 同日日志有 2–4 秒后自动轻待机并回到基础待机 | 自动化 `--schedule-check` / `--blend-check` 无当前通过记录 |
| 玩家经过后的招揽 | 已实现，交互已跑通 | 键盘 `M` → `_on_player_passed` → `_queue_pending_attract` → `_play_auto_attract` | 同日日志有“已记录玩家经过”以及轻招揽 `hello01`、`youyou_Hello_Idle06/07/09` | `M` 只是预览里的模拟，没有业务事件入口 |
| 手动动作与打断 | 已实现，交互已跑通 | `_enter_manual`、`_play_idle_variant`、`_play_batch_oneshot`、`_start_hello`、`_resume_auto_from_i` | 2026-10-15 10:35 日志有招揽结束、手动时忽略 `M` | 手动结束后停在 `MANUAL_TEST`，不会自己恢复自动调度 |
| 拆分表情与口型混合 | 已实现；口型协调自动化已通过 | `YouyouFacePresenter` | 见 A.6 | 舌头拆分补丁失败，7/8 |
| 动作绑定表情 | 已实现 | `YouyouPerformancePoseController` | 交互日志能看到招揽播放；`--performance-expression-check` 无当前通过行 | 口型未清时 `apply_pose` 直接返回，不改表情 |
| 观察镜头 | 已实现 | `youyou_observe_camera.gd`：`reset_view` | `--camera-check` 的数值日志对不上当前拆分表情，结果过期 | 检查脚本仍读取复合键 `surprise` |
| 语音播放 | 尚未实现 | `配音/` 有 mp3，脚本无引用 | 无 | 没有 `AudioStreamPlayer` |
| 由音频驱动口型 | 尚未实现 | `YouyouLipSyncController` 存在但没有任何场景实例化 | 无 | 与正式面部写入器会抢同一组口型键 |
| 小游戏 | 尚未实现 | 无场景、无脚本、无对外函数 | 无 | 仅配音文件名出现“小游戏” |
| 业务流程 A | 尚未实现 | 无状态机、无业务事件、无 C# 源码 | 无 | 不能从本仓库调用 |

### A.3 动画资源与调度池

片段由 `_take_clip` / `_add_mapped_clip` 从 GLB 拷入运行时库。展示名与源动画名不一致时走 `CLIP_ALIASES`。

已接入并参与自动池：

| 展示名 | 场景路径 | 循环 | 池 |
| --- | --- | --- | --- |
| `Basic_Idle` | `res://待机Animation/Basic_Idle.glb` | `LOOP_LINEAR` | 基础待机，不进轻待机池 |
| `Basic_Idle01` … `Basic_Idle05` | `res://待机Animation/<同名>.glb` | 手动播放为循环；自动轻待机时临时改为 `LOOP_NONE` | 轻待机 |
| `youyou_Basic_Idle01` | `res://待机Animation/youyou_Basic_Idle01.001.glb`，源名 `youyou_Basic_Idle01_001` | 同上 | 轻待机 |
| `youyou_Basic_Idle02` … `youyou_Basic_Idle05` | `res://待机Animation/<同名>.glb` | 同上 | 轻待机 |
| `youyou_Hello_Idle01` | `res://待机Animation/youyou_Hello_Idle01.glb` | `LOOP_NONE` | 招揽；也是键盘 `H` |
| `youyou_Hello_Idle02/03/06/07/08/09` | `res://待机Animation/<同名>.glb` | `LOOP_NONE` | 招揽 |
| `hello01` | `res://待机Animation/hello01.glb` | `LOOP_NONE` | 招揽 |
| `Hand Wave_rig_01` | `res://待机Animation/Hand Wave_rig_01.glb` | `LOOP_NONE` | 招揽 |

已能手动播放、未进自动池：

| 展示名 | 路径 | 说明 |
| --- | --- | --- |
| `youyou_Basic_Idle06` | `res://待机Animation/youyou_Basic_Idle06.glb` | 键盘 `Z`。`--schedule-check` 会断言它不在轻待机池 |

磁盘上有、预览未加载：

| 文件 | 说明 |
| --- | --- |
| `res://待机Animation/youyou_Hello_Idle04.glb` | `--new-anim-check` 断言播放器里没有该名字 |
| `res://待机Animation/youyou_Hello_Idle05.glb` | 同上 |
| `res://待机Animation/头发轻风.glb` | 脚本无引用 |

调度常量（`youyou_preview.gd`）：

| 常量 | 值 | 用途 |
| --- | --- | --- |
| `BLEND_BASE_TO_LIGHT` | 0.25 秒 | 基础待机 → 轻待机 |
| `BLEND_LIGHT_TO_BASE` | 0.30 秒 | 轻待机 → 基础待机 |
| `BLEND_BASE_TO_ATTRACT` | 0.25 秒 | 基础待机 → 自动招揽 |
| `BLEND_LIGHT_TO_ATTRACT` | 0.20 秒 | 轻待机自然结束后 → 招揽 |
| `BLEND_ATTRACT_TO_BASE` | 0.30 秒 | 招揽 → 基础待机 |
| `BLEND_MANUAL` | 0.25 秒 | 键盘手动动作 |
| 轻待机等待 | `randf_range(2.0, 4.0)` | 仅 `ScheduleMode.BASE_IDLE` |

`ScheduleMode`：`BASE_IDLE`、`LIGHT_IDLE`、`ATTRACT`、`MANUAL_TEST`。

挑选规则在 `_pick_name`：池内至少两条时不连续重复上一条。基础待机上的待处理招揽要等到播放头从长度的 70% 之后绕回 30% 之内（`_poll_pending_attract_on_basic_idle_cycle`）。轻待机上的待处理招揽等到该段 `animation_finished`。

### A.4 预览键盘入口

这些按键都在 `youyou_preview.gd` 的 `_unhandled_input`，不是业务接口。

| 输入 | 调用 | 行为 |
| --- | --- | --- |
| `I` | `_resume_auto_from_i` 或 `_start_idle(false)` | 自动调度开启时回到基础待机并重新武装等待 |
| `H` | `_start_hello` | 进入手动，播放 `youyou_Hello_Idle01`，表情切到大笑 |
| `M` | `_on_player_passed` | 仅自动调度开启时记录“玩家经过” |
| `Q W E T A` | `_play_idle_variant` | `Basic_Idle01`–`05`，进入手动 |
| `X S D F G Z` | `_play_idle_variant` | `youyou_Basic_Idle01`–`06`，进入手动 |
| `4 5 6 7 8 9 B N` | `_play_batch_oneshot` | `hello01`、挥手、招揽 02/03/06/07/08/09 |
| `1 2 3 C V P` | `_apply_emote` | 拆分情绪 smile / surprise / laugh / angry / sad / grin |
| `J K L` | `_apply_emote` | 视线复合键 wink / lookleft / lookright |
| `0` | `_restore_default_expression` | 恢复微笑；若口型还在，则先清口型 |
| `[ ] ; ' /` | `_apply_viseme` | 口型 a e i o u |
| Backspace | `_clear_viseme` | 异步清口型 |
| `U` | `_request_missing_animation` | 故意请求不存在的 `missing_animation_probe` |
| `Y` | `_apply_emote("missing_expression_probe")` | 故意请求不存在的表情 |
| `R` | 镜头 `reset_view` | 不改动画和表情 |
| Shift+F12 | `_run_viseme_diagnose` | 诊断输出 |

中键拖动旋转，滚轮缩放，Shift+中键平移。镜头脚本与预览脚本都会处理 `R`，镜头脚本把该键标成已处理。

### A.5 面部、口型与并行写入器

正式预览只应通过 `YouyouFacePresenter` 写面部。姿态控制器也只调用它。

`res://Scripts/youyou_face_presenter.gd`，`class_name YouyouFacePresenter`。

| 现有函数 | 签名与即时返回 | 异步 |
| --- | --- | --- |
| `setup` | `(meshes: Array[MeshInstance3D], default_shapes: Dictionary = {}) -> void` | 无 |
| `apply_approved_coefficients` | `() -> void` | 把嘴部情绪系数设为 0.35，口型系数 0.75，过渡 0.27 秒 |
| `configure_performance_blend` | `(duration: float) -> void` | 预览启动时设为 0.40 秒 |
| `set_emotion` | `(emotion_id: String, duration: float = -1.0) -> bool` | `true` 表示已接受并开始 Tween。`duration < 0` 时用 0.27 秒。情绪：`smile` `surprise` `laugh` `angry` `sad` `grin` |
| `set_gaze` | `(gaze_id: String, duration: float = -1.0) -> bool` | 接受 `wink` `lookleft` `lookright` 或空字符串。会清空当前拆分情绪 |
| `set_primary` | `(shape_name: String, duration: float = -1.0) -> bool` | 按名字转调 `set_emotion` 或 `set_gaze` |
| `set_viseme` | `(viseme_id: String, duration: float = -1.0) -> bool` | 只接受 `a e i o u`。内部强度固定 1，再乘 0.75。形态键名为 `A E i o u` |
| `clear_viseme` | `(duration: float = -1.0) -> void` | 清口型并按当前情绪重算嘴部权重 |
| `reset_all` / `reset_to_default` | `(duration: float = -1.0) -> void` | 默认情绪 `smile`，清空视线和口型 |
| `is_emotion_available` | `(emotion_id: String) -> bool` | 眼睛键和嘴键都存在才为真 |
| `get_active_emotion` / `get_active_viseme` / `get_active_primary` | `() -> String` | 读内部状态，不是网格采样 |
| `is_transition_running` | `() -> bool` | Tween 仍有效且进度 < 0.999 |
| `read_shape_on_body` | `(shape_name: String) -> float` | 只读名为 `人体_001` 的网格；找不到返回 -1 |

拆分形态来自 `res://youyou_assets/expressions_split/expressions.json` 与 `youyou_blendshapes.bin`。写入器是 `res://youyou_assets/expressions_split/apply_youyou_blendshapes.gd`，`class_name YouyouBlendshapeApplier`。预览只调用静态方法 `YouyouFacePresenter.apply_split_patch_to_model`，补丁节点随后 `queue_free`。运行时不要再调用 `set_expression` 或 `set_split_expression`。

混合规则（`_build_targets`）：

- 复合主键 `smile` `surprise` `laugh` `angry` `sad` `grin` 被写成 0。
- 无口型时，当前情绪的 `Eyes_*` 与 `Mouth_*` 目标为 1。
- 有口型时，眼睛保持 1，嘴巴改为 0.35，当前元音写成 0.75，其余元音写成 0。
- 视线键激活时，拆分情绪目标为 0，视线键目标为 1；口型仍可叠加。
- 过渡是三次方缓入缓出的并行 Tween。新请求会杀掉上一轮 Tween。没有“过渡完成”信号。

口型参与网格：`人体_001`、`上牙`、`下牙`、`舌头`。2026-10-15 10:22 补丁日志确认 glTF 名 `人体.001` 在运行时节点名是 `人体_001`。

`res://Scripts/youyou_performance_pose.gd`，`class_name YouyouPerformancePoseController`。

| 现有函数 | 行为 |
| --- | --- |
| `POSE_BASE_IDLE` / `POSE_ATTRACT` | 分别对应拆分情绪 `smile`、`laugh` |
| `apply_pose(pose: String, force: bool = false) -> bool` | 口型仍激活时返回 `false`，不写表情。`false` 也可能表示姿态未变 |
| `begin_hello_performance() -> int` | 代数 +1，强制切到招揽表情 |
| `consume_hello_end(generation: int) -> bool` | 代数匹配才消费，并再次 +1，用来丢掉过期的结束回调 |
| `begin_auto_attract_performance() -> int` | 自动招揽同样切到大笑 |
| `consume_auto_finish(generation: int) -> bool` | 自动轻待机/招揽结束的一次性消费 |
| `invalidate_hello` / `invalidate_auto` | 手动打断时使旧结束回调失效 |
| `bump_auto_session() -> int` | 轻待机只换代数，不改表情 |

预览里的结束检测有两条内部路径，都不是对外信号：

- `AnimationPlayer.animation_finished` → `_on_animation_finished(anim_name: StringName)`
- `_process` 轮询“当前片段已停止”

代数消费保证两条路径只有一条真正恢复待机。恢复时只写状态标签和 `print`，没有业务可订阅的信号。

另外三个写入器当前不能和正式预览同时驱动同一张脸：

| 类 | 路径 | 现状 |
| --- | --- | --- |
| `YouyouExpressionController` | `res://Scripts/youyou_expression.gd` | 只被 `youyou_expression_transition_test.tscn` 使用。它把复合主键写成 1，并给 `sad` 加 `noseSneer*`、`jawForward`。与 `YouyouFacePresenter` 写同一组复合键 |
| `YouyouLipSyncController` | `res://Scripts/youyou_lip_sync.gd` | 没有任何场景实例化。`set_viseme(viseme_id, strength = 1.0, duration = 0.2)` 会写 `A/E/i/o/u`。正式预览的口型已由 `YouyouFacePresenter` 负责 |
| `YouyouEmotionLipsyncMixer` | `res://Scripts/youyou_emotion_lipsync_mixer.gd` | 空子类，注释写明与 `YouyouFacePresenter` 相同。当前测试脚本直接 `new()` 父类，不实例化这个子类 |

`youyou_expression_transition_test.gd` 文件头写明：该场景只驱动旧复合表情控制器，不接入口型、调度和业务。

### A.6 音频

`res://配音/` 约有 60 个 mp3，类别包括轻待机、招揽、投币、操作、抓取、抓取成功/失败、游戏开始、引导回抓娃娃、小游戏得分、成功/失败引导小游戏、惊喜大奖。另有一个无中文名的 `ebd9d1992333452696346e74f22c9972.mp3`。

全工程 `.gd` / `.tscn` / `.godot` 没有 `AudioStreamPlayer`，也没有对这些 mp3 的路径引用。语音播放、语音结束、音量与口型时间轴都尚未实现。

### A.7 小游戏

没有小游戏场景、脚本、分数接口或退出回调。配音文件名不能当作模块已完成。

### A.8 测试脚本、命令与已有结果

用户参数要写在 Godot 的 `--` 之后，脚本读取 `OS.get_cmdline_user_args()`。下面命令里的可执行文件路径来自 `.godot/editor/project_metadata.cfg`。本次审查没有重跑。

```text
D:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe --path E:\GodotProjects\ai-claw-v-3 res://scenes/youyou/youyou_preview.tscn -- --viseme-coord-check
```

把场景和最后一个参数换成下表即可。需要看窗口的检查不要加 `--headless`。会截 PNG 的检查会写到 `C:\Users\29385\AppData\Local\Temp\`。

预览场景 `res://scenes/youyou/youyou_preview.tscn`：

| 用户参数 | 函数 | 当前证据 |
| --- | --- | --- |
| 无参数 | `_ready` 开启自动调度 | 2026-10-15 `godot.log`、`godot2026-10-15T10.35.01.log`：补丁 7/8、自动轻待机、待处理招揽、手动忽略 `M`。这是交互日志，没有总通过行 |
| `--phase-a-check` | `_run_phase_a_check` | 结果过期。`%APPDATA%\Godot\app_userdata\AIClaw_v3\phase_a_check.txt` 写于 2026-10-14 17:31，其中 `hello_pose_changed=false`、`laugh_during_hello=0`、`hello_overrides_manual_emote=false`，对不上当前“招揽切大笑” |
| `--batch-check` | `_run_batch_check` | 尚未验证。会写 `youyou_batch_*.png`；Temp 里同类 PNG 是 2026-10-14 |
| `--idle-check` | `_run_idle_check` | 尚未验证。Temp PNG 为 2026-10-14 |
| `--new-anim-check` | `_run_new_anim_check` | 尚未验证。Temp PNG 为 2026-10-14 |
| `--schedule-check` | `_run_schedule_check` | 尚未验证 |
| `--blend-check` | `_run_blend_check` | 尚未验证 |
| `--pending-attract-check` | `_run_pending_attract_check` | 尚未验证 |
| `--expression-check` | `_run_expression_check` | 尚未验证。通过行格式：`=== face_expression_check_pass=true ===` |
| `--expression-isolation-check` | `_run_expression_isolation_check` | 尚未验证。只打印每条 `ok=`，没有总通过行 |
| `--viseme-check` | `_run_viseme_check` | 尚未验证。没有总通过行 |
| `--viseme-coord-check` | `_run_viseme_coord_check` | 已测试。2026-10-15 10:29 日志：`=== viseme_coord_check_pass=true ===`。惊讶加 A 时眼睛 1.000、嘴 0.351、A 0.749，清除后口型归零 |
| `--viseme-diagnose` | `_run_viseme_diagnose` | 诊断输出，不是通过/失败测试 |
| `--performance-expression-check` | `_run_performance_expression_check` | 尚未验证。通过行格式：`=== performance_expression_check_pass=true ===` |
| `--camera-check` | `youyou_observe_camera.gd` 的 `_run_camera_check` | 数值结果过期。`C:\Users\29385\AppData\Local\Temp\youyou_camera_check.log` 里有 `surprise_after_key=1.0`，这是复合键被写成 1 的旧行为。当前正式路径会把复合 `surprise` 归零。该日志后半只是各场景启动时追加的 `ready args` |

表情口型测试场景 `res://scenes/youyou/youyou_emotion_lipsync_test.tscn`，脚本 `res://Scripts/youyou_emotion_lipsync_test.gd`：

| 用户参数 | 函数 | 当前证据 |
| --- | --- | --- |
| 无参数 | HUD：情绪按钮、口型按钮、系数滑条、序列播放 | 可人工看，无自动通过记录 |
| `--split-patch-check` | `_run_patch_only_check` | 今日日志没有单独的 `split_patch_check_pass` 行。补丁结果已包含在下一条里 |
| `--emotion-lipsync-check` | `_run_automation_check` | 已测试。2026-10-15 10:22：`=== emotion_lipsync_check_pass=true ===`，同时 `patch_ok=false`、`meshes=7/8`、`patch_full_8of8=false` |
| `--face-baseline=A` 到 `E`，或 `--face-baseline-all` | `_run_face_baseline` | 尚未验证。只打印权重，没有通过行 |

旧复合表情过渡场景 `res://scenes/youyou/youyou_expression_transition_test.tscn`，脚本 `res://Scripts/youyou_expression_transition_test.gd`：

| 用户参数 | 函数 | 当前证据 |
| --- | --- | --- |
| `--expression-transition-check` | `_run_expression_transition_check` | 尚未验证。通过行格式：`=== expression_transition_check_pass=true ===`。该场景通过旧控制器写复合主键，不能当作正式预览的回归 |

工程内没有 gdUnit、NUnit 或 C# 测试项目。

### A.9 已知问题

1. 舌头拆分补丁失败。2026-10-15 10:22 日志：`舌头 -> 舌头 | 失败：顶点和现有模型对不上（坐标/压缩）`，`patch_v=39`，`godot_v=84`。眼睛/嘴拆分键没有写到舌头。舌头上的原 GLB 口型键仍被正式口型路径驱动（同日协调检查里 `tongue=0.749`）。
2. 正式预览没有自定义 `signal`。动作结束、招揽结束、自动表演结束只 `print` 并改内部状态。
3. 播放失败只走 `_fail`：`push_error` 加状态标签。调用方拿不到返回码，也没有失败信号。
4. 手动模式结束后不会恢复 2–4 秒轻待机。必须再按 `I`（`_resume_auto_from_i`）。
5. 表情键和口型键不改变 `ScheduleMode`。回到基础待机时 `_sync_performance_base_idle` 会把表情拉回微笑，除非口型仍占着写入权。
6. `set_viseme` 不接受外部强度。强度恒为 1，显示权重再乘 0.75。
7. `YouyouFacePresenter.set_emotion` 默认过渡 0.27 秒；姿态控制器使用 0.40 秒。两套时长已经同时存在。
8. 视线与拆分情绪互斥。`set_gaze` 清空 `_active_emotion`，`set_emotion` 清空 `_active_gaze`。
9. 轻待机不改表情。只有招揽/招揽 01 把姿态设为 `attract`（大笑），回到基础待机再设回微笑。
10. `phase_a_check.txt` 与相机检查里的 `surprise=1.0` 不能用来判断当前构建。
11. 2026-10-15 10:21 的交互日志把过渡印成 0.15 秒，早于当前源码的 0.27 秒，不能当作当前常数的测试结果。10:29 的协调检查已经是 0.27 秒路径。

---

## B. B 模块职责边界

### B.1 表现模块负责

- 实例化 `柚柚.glb`，播放已登记的骨骼动画，处理混合时长与循环模式。
- 独占写这批面部属性：`Eyes_*`、`Mouth_*`、复合主键、`wink` / `lookleft` / `lookright`、口型 `A` / `E` / `i` / `o` / `u`。
- 维护一个面部写入器。正式路径是 `YouyouFacePresenter`。姿态控制器只能调用它。
- 把“片段播完”转换成一次结束通知。代数去重留在 B 内部。
- 镜头观察、耳机隐藏、状态标签。这些不属于业务状态。
- 资源缺失、形态键缺失、补丁部分失败时给出失败原因。是否重试、是否降级业务流程，由 A 决定。

### B.2 业务层负责

当前工程里还没有这一层。落地后应由 A 持有：

- 招揽是否该发生、投币、操作、抓取成败、结果反馈、进入/退出小游戏。现在的 `M` 和 2–4 秒轻待机计时是预览内部模拟，不是业务状态机。
- 选择哪一句配音、哪一个业务语义的动作。B 只按 A 给出的资源 id 播放。
- 会话、分数、硬件、权限、云端请求。
- 小游戏自己的胜负与 UI。B 不读取小游戏内部变量。

### B.3 禁止并行的状态

| 状态或属性 | 唯一写入者 | 说明 |
| --- | --- | --- |
| `ScheduleMode`、待处理招揽、轻待机计时器、结束代数 | 预览脚本内部。建议以后只由一个表现门面持有 | A 不要再保存一份“当前动画模式”并据此抢播 |
| `Eyes_*` / `Mouth_*` / 复合主键 / 视线键 / `A E i o u` | 正式场景中只有 `YouyouFacePresenter` | 不要同时启用 `YouyouExpressionController` 或 `YouyouLipSyncController` |
| 业务阶段（待机招揽、游戏中、结算、小游戏中） | A | B 不因为动画播完就自行进入下一业务阶段 |
| 配音文件选择与播放次数 | A 决定播哪条；B 负责播出和报告结束 | 现在两条都还没有代码 |

预览场景与 `youyou_expression_transition_test.tscn` 不要叠在同一棵角色树上。后者会把复合主键写成 1，前者会把它们写成 0。

---

## C. 对外接口建议

正式预览根脚本没有 `class_name`，业务函数全部带下划线，A 现在无法稳定调用。下面把“今天就能调用的类方法”和“建议新增的门面”分开。

建议新增一个节点，例如挂在预览根下的 `YouyouPerformanceFacade`（名称可再定）。A 只连这个节点。门面内部再调用现有的 `YouyouFacePresenter` 与动画播放器。

约定：

- 立刻返回值只表示“是否接受请求”，不表示播完。
- `request_id` 从 1 递增。返回 `0` 表示拒绝，同时应发出失败信号。
- 完成、打断、失败都走信号。同一个 `request_id` 最终只发出一次终态信号。
- 原因字符串建议限定为 `completed`、`interrupted`、`failed`、`rejected`。
- 现有 Tween 和 `animation_finished` 仍是内部实现，不直接暴露给 A。

### C.1 动作播放

建议新增：

```gdscript
func play_action(action_id: String, options: Dictionary = {}) -> int
```

- `action_id`：当前库中的展示名，例如 `Basic_Idle`、`youyou_Hello_Idle01`、`hello01`。
- `options` 可选键：
  - `loop: bool`，缺省按该片段现在的池规则（基础/轻待机变体为循环，招揽为单次）。
  - `blend: float`，缺省时由 B 按来源片段选择 0.20–0.30 秒，A 不传业务秒数也可以。
  - `interrupt: String`，`"immediate"` 或 `"after_natural_end"`。缺省值待确认，见 F。
  - `package_id: int`，0 表示不属于整套表现。
- 返回：接受则为新的 `request_id`；未知片段、角色未就绪、或当前优先级拒绝时返回 `0`。
- 异步：函数立即返回。播完、被打断或失败时发 `action_finished`。

现有接口（B 内部，A 不要直接当业务 API 用）：

| 函数 | 位置 | 即时语义 | 异步 |
| --- | --- | --- | --- |
| `_play_clip(anim_name: String, blend: float) -> void` | 预览脚本 | 无返回值；同片段会 `seek(0)` | 结束靠 `animation_finished` 或 `_process` |
| `_start_idle(from_hello_end: bool) -> void` | 预览脚本 | 片段缺失时只 `_fail` | 基础待机循环，没有结束信号 |
| `_start_hello() -> void` | 预览脚本 | 无返回值；内部拿代数 | 结束时 `consume_hello_end` 后回到待机 |
| `_play_batch_oneshot(anim_name: String) -> void` | 预览脚本 | 缺失则 `_fail` 并尝试回待机 | 结束时回到待机，模式仍是手动 |
| `_play_auto_light() -> void` / `_play_auto_attract() -> void` | 预览脚本 | 池空则 `_fail` 并返回 | 结束后 `_return_auto_base` |
| `AnimationPlayer.animation_finished(anim_name: StringName)` | 引擎信号，已连到 `_on_animation_finished` | 片段自然结束 | 循环片段不会在每圈发出一次给业务用的事件 |
| `begin_hello_performance() -> int` | `YouyouPerformancePoseController` | 返回代数，不是业务请求号 | 只切表情，不播动画 |
| `consume_hello_end(generation: int) -> bool` | 同上 | `true` 表示这次结束仍有效 | 内部去重 |
| `consume_auto_finish(generation: int) -> bool` | 同上 | 同上 | 内部去重 |

### C.2 语音播放

建议新增：

```gdscript
func play_voice(voice_id: String, options: Dictionary = {}) -> int
```

- `voice_id`：`res://配音/` 下的文件名（不含扩展名），或双方另表约定的逻辑 id。当前没有这张表。
- `options` 可选键：`package_id: int`，`interrupt: String`（`"immediate"` / `"after_natural_end"`），`viseme: String`。`viseme` 缺省为 `"none"`。`"none"` 表示只播声音、不改口型。其它取值尚未实现，不得假装已有音素对齐。
- 返回：文件能加载且优先级允许则为 `request_id`，否则 `0`。
- 异步：立即返回。`AudioStreamPlayer.finished` 由 B 转成一次 `voice_finished`。加载失败立即 `performance_failed`，不发 `voice_finished`。

现有接口：无。`YouyouLipSyncController.set_viseme(viseme_id: String, strength: float = 1.0, duration: float = 0.2) -> bool` 是另一套口型写入器，标记为现有接口，正式场景不要和 `YouyouFacePresenter` 一起用。

### C.3 表情设置

建议新增：

```gdscript
func set_expression(expression_id: String, duration: float = -1.0) -> bool
```

- `expression_id`：`smile` `surprise` `laugh` `angry` `sad` `grin` `wink` `lookleft` `lookright`。
- `duration`：秒。`< 0` 时使用 B 的默认过渡。姿态驱动用 0.40 秒，键盘/直接情绪用 0.27 秒；门面默认哪一个待确认。
- 返回：`true` 表示已接受并开始过渡；未知 id、形态未就绪返回 `false`，并 `performance_failed`。
- 异步：`true` 不是过渡结束。建议另发 `expression_settled(expression_id: String)`，在对应 Tween 完成时一次。过渡被新请求打断时，旧 id 不再发 settled。

现有接口（门面应转调这些，A 不直接写网格）：

| 函数 | 即时语义 | 异步 |
| --- | --- | --- |
| `YouyouFacePresenter.set_emotion(emotion_id: String, duration: float = -1.0) -> bool` | 未就绪或不在表内返回 `false` | Tween，无完成信号 |
| `YouyouFacePresenter.set_gaze(gaze_id: String, duration: float = -1.0) -> bool` | 非法或网格没有该键返回 `false` | 同上；会清掉拆分情绪 |
| `YouyouFacePresenter.set_primary(shape_name: String, duration: float = -1.0) -> bool` | 不能识别则 `false` | 转调上面两个 |
| `YouyouFacePresenter.set_viseme(viseme_id: String, duration: float = -1.0) -> bool` | 非 `a/e/i/o/u` 返回 `false` | 与当前情绪同时写入 |
| `YouyouFacePresenter.clear_viseme(duration: float = -1.0) -> void` | 无返回值 | 预览的 `_run_clear_viseme_coordinator` 还会再等 `duration + 0.08` 秒，必要时瞬时清零 |
| `YouyouFacePresenter.reset_to_default(duration: float = -1.0) -> void` | 无返回值 | 回到微笑并清口型、视线 |
| `YouyouPerformancePoseController.apply_pose(pose: String, force: bool = false) -> bool` | 口型占用时返回 `false` | 使用 0.40 秒 |

`YouyouExpressionController.set_primary(shape_name: String, duration: float = -1.0) -> bool` 也是现有接口，只属于旧测试场景。正式门面不要调用它。

### C.4 停止表现

建议新增：

```gdscript
func stop_performance(scope: String, reason: String = "") -> void
```

- `scope`：`"action"`、`"voice"`、`"expression"`、`"all"`。
- 即时：停止对应播放器或把表情/口型 Tween 收到中性/当前姿态默认。函数返回时请求已被标记为结束，画面混合可能还要 0.20–0.40 秒。
- 异步：对每个被停掉的活动请求发对应的 `action_finished` 或 `voice_finished`，`reason = "interrupted"`。`scope == "all"` 或整套被停时再发一次 `performance_finished`。不要对同一个请求既发 `interrupted` 终态又再发 `completed`。
- 本函数不自动开始下一段待机。恢复待机由 A 再调 `play_action("Basic_Idle", ...)`，或由双方确认后的默认恢复策略执行。

现有近似行为（没有这个函数）：

| 现有路径 | 实际效果 |
| --- | --- |
| `_enter_manual` | 停计时器、清待处理招揽、`invalidate_hello`、`invalidate_auto`。不发信号 |
| `_start_idle` | 混合回 `Basic_Idle`。手动模式下不重新 `_arm_wait` |
| `_resume_auto_from_i` | 回到基础待机并重新武装 2–4 秒等待 |
| `_clear_viseme` | 只清口型 |

### C.5 结束与失败信号

全部为建议新增。当前脚本里不存在这些信号名。

```gdscript
signal action_finished(request_id: int, action_id: String, reason: String)
signal voice_finished(request_id: int, voice_id: String, reason: String)
signal expression_settled(expression_id: String)
signal performance_finished(package_id: int, reason: String)
signal performance_failed(request_id: int, code: String, message: String)
```

语义：

| 信号 | 何时发出 | 不表示什么 |
| --- | --- | --- |
| `action_finished` | 单次动作播完，或被 `stop_performance` / 更高优先级请求打断 | 不表示语音已结束，也不表示业务可以进入下一阶段 |
| `voice_finished` | 音频自然播完，或被打断 | 不表示口型 Tween 已经归零。若要等嘴型收回，需另等 `expression_settled` 或 B 在清口型完成后再发语音终态。后者待确认 |
| `expression_settled` | 一次表情/口型过渡到达目标 | 循环待机不会周期性发出 |
| `performance_finished` | 同一 `package_id` 下已接受的动作和语音都进入终态 | `package_id == 0` 的零散调用不发这个信号 |
| `performance_failed` | 拒绝或中途失败 | 已失败的 `request_id` 不再发 `*_finished(..., "completed")` |

`code` 建议从现有失败路径映射，而不是新发明业务错误：

| code | 对应现有行为 |
| --- | --- |
| `model_not_ready` | `_load_model` / `_load_clips` 失败后预览停止初始化 |
| `animation_missing` | `_fail("无法播放…")`、`_request_missing_animation` |
| `expression_missing` | `set_emotion` / `set_gaze` / `set_viseme` 返回 `false` |
| `voice_missing` | 建议新增；当前没有播放器 |
| `patch_partial` | 启动日志“拆分补丁部分成功 7/8”。这是警告还是失败，待确认。今天的口型检查在 7/8 时仍判通过 |
| `busy_rejected` | 建议新增；当前 `M` 在招揽和手动模式会忽略，没有错误码 |

整套播放建议新增：

```gdscript
func play_package(package: Dictionary) -> int
```

- `package` 键：`action_id: String`、`voice_id: String`、`expression_id: String`。空字符串表示该路不播。
- 返回：包 id（同时作为 `performance_finished` 的 `package_id`）。任一必填资源缺失则返回 `0` 并发 `performance_failed`。
- 异步：动作与语音并行开始。包结束条件见 F，未确认前不要实现成“谁先结束整包就结束”。

---

## D. 表现优先级与打断规则

本节前半是当前代码已经在做的事，后半是尚未定案的建议。当前代码没有“结果反馈”和“小游戏”分支。

### D.1 当前预览已经实现的规则

优先级从高到低，指“谁可以打断谁”：

1. 手动测试（`MANUAL_TEST`）：待机变体键、单次动作键、`H`、`U`。`_enter_manual` 立刻停等待计时器，清掉待处理招揽，使招揽/自动结束代数失效。
2. 自动招揽（`ATTRACT`）：播放期间忽略新的 `M`。播完回到基础待机并重新武装等待。
3. 轻待机（`LIGHT_IDLE`）：`M` 不立刻切断，只记下待处理招揽；本段结束后再播招揽，混合 0.20 秒。
4. 基础待机（`BASE_IDLE`）：循环。`M` 等到本圈后段绕回前段再播招揽。等待 2–4 秒后播轻待机；若已有待处理招揽，等待超时被忽略。
5. 表情键和口型键：不改变调度模式，可以在任何模式下改脸。
6. 口型占用：`apply_pose` 返回 `false`，招揽开始和回到待机都不会改情绪，直到口型清掉。直接 `set_emotion` 不受这道限制，所以键盘表情仍能在口型存在时改眼睛和嘴系数。

其它已实现细节：

- 同一招揽或单次动作未播完时再次请求，会以 0.25 秒混合从头播放。
- 基础待机已经在播时，非结束路径的 `_start_idle(false)` 会忽略重复请求。
- 手动动作自然结束后回到 `Basic_Idle`，但模式保持 `MANUAL_TEST`，计时器保持停止。
- 轻待机本身不切换表情。招揽把表情推向大笑；自动回到基础待机再推向微笑。
- 待处理招揽只保留一份，重复 `M` 被忽略。

### D.2 建议的业务优先级（未定案）

建议 A 只发意图，B 按一张优先级表决定播不播。下面的数字越小越优先。这是建议，不是已实现行为。

| 优先级 | 类型 | 建议打断 | 结束后的画面 |
| --- | --- | --- | --- |
| 1 | A 调用 `stop_performance("all")`，或进入/退出小游戏的切换指令 | 立即停动作和语音 | 由该指令单独给出下一段；B 不自选 |
| 2 | 结果反馈（抓取成功/失败、大奖） | 立即打断招揽、轻待机和普通动作；语音是否立刻掐断待确认 | 反馈包终态之后，A 再决定回待机还是进小游戏引导 |
| 3 | A 点名的普通动作 + 可选语音 | 立即打断轻待机和基础待机；是否打断另一条普通动作待确认 | 动作 `action_finished` 后不自动招揽 |
| 4 | A 发起的招揽 | 基础待机可等到本圈结束；轻待机可等到本段结束。这与当前 `M` 一致 | 仅当 A 仍处于“可招揽”时，B 才回到基础待机表现 |
| 5 | 基础待机 / 轻待机 | 不打断 2–4 | 轻待机结束回基础待机。这个自动循环是否还留在 B，待确认 |

语音与口型：

- 有语音时，B 可以保留当前眼睛情绪，并把嘴部系数降到 0.35、元音 0.75。这是现有混合。
- 没有音素时间轴之前，`play_voice` 的 `viseme` 保持 `"none"`，避免用错误口型对上整段配音。
- 口型存在时，姿态控制器今天不会把招揽改成大笑。业务上“说话期间招揽还要不要换脸”尚未确认。

结果反馈和小游戏：

- 结果反馈建议走 `play_package`，动作 id 与 `配音/` 里的成功、失败、大奖文件由 A 选择。B 不判断抓取是否成功。
- 进入小游戏时建议 `stop_performance("all")`，原因 `"minigame"`。小游戏场景若使用另一个视口，B 停止骨骼与音频即可。
- 退出小游戏后恢复哪一段，当前代码没有记忆。不要默认“回到被打断的那一帧”。

### D.3 明确尚未确认、本次不代为定案的规则

- 自动轻待机循环留在 B，还是改成 A 的定时事件。
- “玩家经过”由谁判定。现在只有键盘 `M`。
- 招揽等待本圈结束，还是业务要求立刻挥手。
- 结果反馈能否打断正在说的语音。
- 两条语音重叠时是交叉淡化、立刻替换，还是拒绝第二条。
- 说话时姿态表情让不让写脸。
- 小游戏进行中，数字人是隐藏、停在最后一帧，还是播一套独立待机。
- 小游戏退出后恢复“进游戏前的业务阶段”，还是一律基础待机微笑。
- 手动预览热键在正式业务场景是否关闭。

---

## E. 联调验收清单

环境：Windows，Godot `D:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe`，项目 `E:\GodotProjects\ai-claw-v-3`。正式联调用窗口模式。对比日志时以控制台里的 `request_id` 为准。

今天就能做的，是预览回归，用来确认 B 没有退步。A 的标准事件要等 C 节的建议接口落地后才能测；落地前把下列 B 组标成阻塞，不要用键盘 `M` 代替 A 的事件并宣称联调通过。

### E.1 今天可执行的 B 回归

工作目录任意。每条命令单独开一次 Godot，进程会在检查结束时 `quit`。

```text
D:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe --path E:\GodotProjects\ai-claw-v-3 res://scenes/youyou/youyou_preview.tscn -- --viseme-coord-check
```

| 步骤 | 操作 | 通过标准 |
| --- | --- | --- |
| B1 | 上条命令 | 输出含 `=== viseme_coord_check_pass=true ===`，且启动行仍是“拆分补丁部分成功 7/8” |
| B2 | 同一可执行文件，场景改为 `res://scenes/youyou/youyou_emotion_lipsync_test.tscn`，参数 `--emotion-lipsync-check` | `emotion_lipsync_check_pass=true`。同时允许 `patch_full_8of8=false` |
| B3 | 预览场景无参数，启动后不要按键，观察至少两轮 | 日志出现“基础待机，x 秒后播放轻待机”，x 在 2–4；轻待机结束后出现“自动表演结束，回到基础待机” |
| B4 | 基础待机时按 `M`，等到本圈结束 | 先出现“已记录玩家经过”，之后出现“自动轻招揽”，再回到基础待机 |
| B5 | 招揽播放中连按 `M` | 出现“当前不能插入招揽，忽略 M”。动作不被重启 |
| B6 | 按 `4` 播放 `hello01`，未结束时按 `I` | 回到 `Basic_Idle`。再按 `M` 应能重新记录招揽，而不是继续被手动模式吞掉 |
| B7 | 按 `H`，等招揽 01 播完 | 日志“收到招揽结束信号”或“招揽播放结束”，然后是待机。只应恢复一次 |
| B8 | 微笑脸上按 `[` 再按 Backspace | 先“口型 a”，后“已清除口型”。脸回到清除前的情绪，而不是把眼睛也清成 0 |

预期失败/限制，记下即可，不算 B 回归失败：

- 舌头补丁仍是 7/8。
- `--performance-expression-check`、`--expression-check`、`--schedule-check`、`--expression-transition-check` 本次审查没有当前通过记录。若补跑，把完整控制台存档，不要只保留截图。

### E.2 接口落地后的 A/B 联调

用一个临时调用脚本或 A 的测试桩，只调用门面，不调用 `_start_hello` 一类下划线函数，也不直接 `set_blend_shape_value`。

| 步骤 | A 发出 | B 应出现 | 通知 |
| --- | --- | --- | --- |
| J1 | `play_action("Basic_Idle", {loop=true})` | 骨骼循环基础待机，表情为微笑 | 循环动作不发 `action_finished`。可用 `get_active` 一类查询核对，若查询函数尚未加入，则看播放器当前片段名 |
| J2 | 在 J1 之上 `play_action("youyou_Hello_Idle02", {interrupt="after_natural_end"})` | 当前这一圈基础待机走完才切招揽，混合约 0.25 秒 | 基础待机不另发完成；招揽播完恰好一次 `action_finished(id, "youyou_Hello_Idle02", "completed")` |
| J3 | 招揽未完时 `play_action("hello01", {interrupt="immediate"})` | 0.25 秒内切到 `hello01` | 旧 id：`action_finished(..., "interrupted")` 一次。新 id 结束时 `completed` 一次。没有第三次 |
| J4 | `play_voice("招揽1-小惊喜", {viseme="none"})` | 能听到该 mp3，嘴部口型权重保持接近 0 | 播完一次 `voice_finished(..., "completed")`。没有 `action_finished` |
| J5 | `set_expression("surprise", 0.4)` 后立刻 `set_expression("sad", 0.4)` | 复合 `surprise` 保持 0，`Eyes_surprise` 不跳变成 0 再突然为 1 | 只有 `expression_settled("sad")`。`set_expression` 的返回值两次都为 `true` |
| J6 | `set_expression("missing_expression_probe")` | 脸保持 J5 的 sad | 返回 `false`，一次 `performance_failed(..., "expression_missing", ...)` |
| J7 | `play_package({action_id="hello01", voice_id="招揽1-小惊喜", expression_id="laugh"})` | 动作、声音同时开始，表情走向大笑 | 各发自己的 finished；两者都终态后恰好一次 `performance_finished(package_id, "completed")` |
| J8 | J7 进行中 `stop_performance("all", "operator")` | 声音停止，动作开始混合回 A 指定的下一段；若 A 没给下一段，则停在 B 文档化的保持姿态 | 动作与语音都是 `interrupted`，包是 `performance_finished(package_id, "interrupted")`。没有 `completed` |
| J9 | `play_action("missing_animation_probe")` | 保持 J8 之后的姿态，不黑屏、不销毁模型 | 返回 `0`，`performance_failed(..., "animation_missing", ...)` |
| J10 | 结果反馈桩：`play_package` 使用一条现有“抓取成功”配音和一条已登记招揽动作 | B 不读取任何抓取分数 | 终态信号与 J7 相同。A 的业务状态由测试桩自己断言 |
| J11 | `stop_performance("all", "minigame")`，测试桩切换到占位场景再返回，然后 `play_action("Basic_Idle", {loop=true})` | 返回后是新的基础待机，不是被打断片段的中间帧 | 进入时有 interrupted；返回后的新 `request_id` 与旧 id 不同 |
| J12 | 口型测试：`set_expression` 路径改走 `YouyouFacePresenter.set_viseme("a")` 的门面包装（若 C.3 只暴露表情，则另加建议中的口型调用） | `人体_001` 上 `A` 约 0.75，`Eyes_*` 仍大于 0.85，复合 `smile` 小于 0.05 | 清除后 `voice_finished` 或约定的口型信号只来一次 |

J12 的口型门面如果没做，就不要临时让 A 调用 `YouyouLipSyncController`。

### E.3 记录格式

每条保存：Godot 版本行、命令行、相关信号的 `request_id/reason`、失败时的 `code`。截图只作辅助。旧的 `phase_a_check.txt` 和 10 月 14 日 Temp PNG 不作为本次联调证据。

---

## F. 交接待确认事项

1. 业务状态由谁持有。当前 `ScheduleMode` 在 B 的预览脚本里。A 若再维护“正在招揽/正在待机”，两边会同时改调度。需要约定 A 只发事件、B 只回终态信号，还是暂时让 B 继续自治轻待机。
2. 事件名单与 id 表。动作展示名、`配音/` 文件名、情绪 id 三套名字今天并不对齐（例如招揽动画 `youyou_Hello_Idle02` 与配音 `招揽2-battle` 没有代码映射）。
3. 表现结束语义。单次动作结束、语音结束、整包结束是三个信号。整包是“都完成才算完成”，还是“主动作完成即算完成，语音可被掐掉”。循环待机不算结束。
4. 打断策略。立即打断与“本圈结束再打断”分别用于哪些业务事件。结果反馈是否高于招揽。拒绝时返回 `0` 并 `busy_rejected`，还是排队。当前代码只会对多余的 `M` 忽略。
5. 手动预览结束后的恢复。今天回到待机但不恢复自动计时。正式场景里，操作员打断之后要不要自动回到 A 的当前业务阶段。
6. 说话与表情谁赢。口型占用时 `apply_pose` 已经不写情绪；键盘 `set_emotion` 却仍会写。正式规则需要二选一，并规定清口型后是否回到“进语音前的表情”还是“当前姿态默认表情”。
7. 过渡时长。直接表情 0.27 秒，姿态 0.40 秒，旧口型控制器 0.20 秒，旧复合表情测试 0.40 秒。门面默认值需要一处定数。
8. 舌头补丁 7/8 算启动警告还是 `patch_partial` 失败。当前自动化在补丁不完整时仍可让口型检查通过。
9. 小游戏退出后的恢复。没有存档点。需要决定恢复业务阶段、一律基础待机，还是恢复进小游戏前的动作种类（不是中间帧）。小游戏进行中数字人是否继续渲染。
10. 结果反馈的资源配对。成功、失败、引导回抓娃娃、引导小游戏、大奖，各用哪条动作和哪条 mp3。B 没有这张表，A 也还没有选择逻辑。
11. 语音口型。确认首期 `viseme="none"`，直到有单独的时间轴。不要在联调里要求音频分析。
12. 视线与情绪。当前互斥。若业务要“微笑同时看左”，需要新的叠加规则；在此之前门面应按现有互斥执行。
13. 热键去留。`M`、`H`、表情键若留在正式场景，会绕过 A。建议正式场景关闭预览热键，只保留镜头 `R`。是否关闭待确认。
14. C# 边界。工程具备 Mono 设置，但没有 C# 工程。A 若用 C#，信号仍建议落在上述 GDScript 门面上，由 C# `Connect`；不要在 C# 里再写一套 BlendShape。
15. 未接入动画。`youyou_Hello_Idle04/05`、`youyou_Basic_Idle06`、`头发轻风` 是否进入正式池，由内容设计决定，当前调度故意排除了前两者中的 04/05 和轻待机池中的 06。

---

## 审查范围说明

读过的执行路径：`project.godot`，`scenes/youyou/` 下三个场景，`Scripts/` 下全部 `.gd`，`youyou_assets/expressions_split/` 的脚本与 `expressions.json`，待机 GLB 文件名，`配音/` 文件名。

对照过的运行痕迹：`%APPDATA%\Godot\app_userdata\AIClaw_v3\logs\` 中 2026-10-15 的 `godot.log` 与四份按时间戳保存的日志，`phase_a_check.txt`，`youyou_camera_check.log`。Temp 下的 PNG 时间早于当前拆分表情日志，未当作当前通过证据。

未做：重跑 Godot、修改任何源文件或场景、读取或改写凭证、请求云端 API、把其它项目的实现拷进本仓库。
