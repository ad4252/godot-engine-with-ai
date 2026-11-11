extends Node2D
class_name BattleManager

# ── 데이터 클래스 ──
class Dice extends RefCounted:
	var min_p: int
	var max_p: int
	
	func _init(p_min: int, p_max: int) -> void:
		min_p = p_min
		max_p = p_max

	func roll(rng: RandomNumberGenerator, bonus: int = 0) -> int:
		var effective_min = min_p + bonus
		var effective_max = max_p + bonus
		return rng.randi_range(effective_min, effective_max)


class Skill extends RefCounted:
	var name: String
	var dice_list: Array[Dice] = []

	func _init(n: String, dice_data: Array) -> void:
		name = n
		for d in dice_data:
			dice_list.append(Dice.new(d[0], d[1]))

	func roll_all(rng: RandomNumberGenerator, bonus: int = 0) -> Dictionary:
		var rolls: Array[int] = []
		var total: int = 0
		for dice in dice_list:
			var val = dice.roll(rng, bonus)
			rolls.append(val)
			total += val
		return {"rolls": rolls, "total": total}


# ── 설정 상수 ──
const DICE_VALUE_MIN := 1
const DICE_VALUE_MAX := 20

# 🛠️ 속성과 버프 정의
const ATTRIBUTES := {
	"참격": "⚔️",
	"타격": "🔨",
	"관통": "🗡️"
}

const BUFFS := {
	"없음": "❌",
	"주사위+1": "🎲",
	"고정+5": "⚡"
}

# ── 노드 참조 ──
var battle_stage
var player_hp_label: Label
var enemy_hp_label: Label
var battle_button: Button
var reset_button: Button
var result_log: RichTextLabel
var attribute_display: Label        # 🛠️ 선택된 속성 표시
var buff_display: Label             # 🛠️ 적용된 버프 표시
var attribute_select: OptionButton
var buff_select: OptionButton

# ── 게임 상태 ──
var player_hp: int = 100
var enemy_hp: int = 100
var _rng := RandomNumberGenerator.new()
var player_skill: Skill
var enemy_skill: Skill

# ── 적의 속성 특성 ──
var enemy_weakness: String = "참격"
var enemy_resistance: String = "관통"

# ── 주사위 UI 참조 ──
var dice_min_boxes: Array[SpinBox] = []
var dice_max_boxes: Array[SpinBox] = []


func _ready() -> void:
	_rng.randomize()
	
	# 모든 노드를 안전하게 찾기
	battle_stage = get_node_or_null("%BattleStage")
	player_hp_label = get_node_or_null("%PlayerHPLabel") as Label
	enemy_hp_label = get_node_or_null("%EnemyHPLabel") as Label
	battle_button = get_node_or_null("%BattleButton") as Button
	reset_button = get_node_or_null("%ResetButton") as Button
	result_log = get_node_or_null("%BattleLog") as RichTextLabel
	attribute_display = get_node_or_null("%AttributeDisplay") as Label
	buff_display = get_node_or_null("%BuffDisplay") as Label
	attribute_select = get_node_or_null("%AttributeSelect") as OptionButton
	buff_select = get_node_or_null("%BuffSelect") as OptionButton

	if result_log != null:
		result_log.scroll_following = true
	else:
		push_warning("BattleLog 노드를 찾을 수 없습니다.")

	# 스킬 초기화
	player_skill = Skill.new("연속 베기", [[3, 7], [2, 6]])
	enemy_skill = Skill.new("맞대응 강타", [[3, 7], [2, 6]])

	# UI 초기화
	if attribute_select != null and buff_select != null:
		_setup_select_ui()

	_setup_dice_ui()

	# 버튼 시그널 연결
	if battle_button != null:
		battle_button.pressed.connect(_on_battle_pressed)
	if reset_button != null:
		reset_button.pressed.connect(_on_reset_pressed)
	
	# 속성/버프 선택 변경 시 즉시 표시 업데이트
	if attribute_select != null:
		attribute_select.item_selected.connect(_on_attribute_changed)
	if buff_select != null:
		buff_select.item_selected.connect(_on_buff_changed)

	_refresh_status()
	_update_displays()
	
	if result_log != null:
		result_log.text = "진행 버튼을 눌러 전투를 시작하세요!\n"


# ───────── UI 초기화 ─────────

func _setup_select_ui() -> void:
	if attribute_select == null or buff_select == null:
		return

	# 속성 설정
	for attr_name in ATTRIBUTES.keys():
		attribute_select.add_item(attr_name)
	attribute_select.selected = 0

	# 버프 설정
	for buff_name in BUFFS.keys():
		buff_select.add_item(buff_name)
	buff_select.selected = 0


# 🛠️ 속성/버프 선택 변경 시 호출
func _on_attribute_changed(_index: int) -> void:
	_update_displays()


func _on_buff_changed(_index: int) -> void:
	_update_displays()


# 🛠️ 선택된 속성과 버프를 화면에 표시
func _update_displays() -> void:
	if attribute_display == null or buff_display == null:
		return

	var attr_name = ""
	var attr_icon = ""
	if attribute_select != null and attribute_select.selected < ATTRIBUTES.size():
		attr_name = attribute_select.get_item_text(attribute_select.selected)
		attr_icon = ATTRIBUTES.get(attr_name, "")

	var buff_name = ""
	var buff_icon = ""
	if buff_select != null and buff_select.selected < BUFFS.size():
		buff_name = buff_select.get_item_text(buff_select.selected)
		buff_icon = BUFFS.get(buff_name, "")

	attribute_display.text = "%s %s" % [attr_icon, attr_name]
	buff_display.text = "%s %s" % [buff_icon, buff_name]


# ───────── 주사위 커스텀 UI ─────────

func _setup_dice_ui() -> void:
	dice_min_boxes = [
		get_node_or_null("%P1Min") as SpinBox,
		get_node_or_null("%P2Min") as SpinBox
	]
	dice_max_boxes = [
		get_node_or_null("%P1Max") as SpinBox,
		get_node_or_null("%P2Max") as SpinBox
	]

	for i in player_skill.dice_list.size():
		var d = player_skill.dice_list[i]
		var min_box: SpinBox = dice_min_boxes[i]
		var max_box: SpinBox = dice_max_boxes[i]

		if min_box == null or max_box == null:
			continue

		for box in [min_box, max_box]:
			box.min_value = DICE_VALUE_MIN
			box.max_value = DICE_VALUE_MAX
			box.step = 1
			box.rounded = true

		min_box.set_value_no_signal(d.min_p)
		max_box.set_value_no_signal(d.max_p)

		min_box.value_changed.connect(_on_dice_changed.bind(i, true))
		max_box.value_changed.connect(_on_dice_changed.bind(i, false))


func _on_dice_changed(_value: float, index: int, is_min: bool) -> void:
	var dice = player_skill.dice_list[index]
	var min_box: SpinBox = dice_min_boxes[index]
	var max_box: SpinBox = dice_max_boxes[index]

	var new_min := int(min_box.value)
	var new_max := int(max_box.value)

	if new_min > new_max:
		if is_min:
			new_max = new_min
		else:
			new_min = new_max

	dice.min_p = new_min
	dice.max_p = new_max
	min_box.set_value_no_signal(new_min)
	max_box.set_value_no_signal(new_max)


func _set_dice_ui_editable(value: bool) -> void:
	for box in dice_min_boxes + dice_max_boxes:
		if box != null:
			box.editable = value


# ───────── 전투 실행 ─────────

func _on_battle_pressed() -> void:
	if battle_stage and battle_stage.busy:
		return
	
	if battle_button != null:
		battle_button.disabled = true
	if reset_button != null:
		reset_button.disabled = true
	_set_dice_ui_editable(false)
	if attribute_select != null:
		attribute_select.disabled = true
	if buff_select != null:
		buff_select.disabled = true
	_execute_battle()


func _execute_battle() -> void:
	var selected_attr_name: String = "참격"
	if attribute_select != null:
		selected_attr_name = attribute_select.get_item_text(attribute_select.selected)

	var dice_bonus: int = 0
	var extra_damage: int = 0
	var buff_display_text: String = ""

	if buff_select != null:
		var buff_name = buff_select.get_item_text(buff_select.selected)
		if buff_name == "주사위+1":
			dice_bonus = 1
			buff_display_text = "🎲 주사위+1 적용"
		elif buff_name == "고정+5":
			extra_damage = 5
			buff_display_text = "⚡ 고정+5 피해 적용"

	# 주사위 굴리기
	var p_data: Dictionary = player_skill.roll_all(_rng, dice_bonus)
	var e_data: Dictionary = enemy_skill.roll_all(_rng, 0)

	var p_total: int = p_data["total"]
	var e_total: int = e_data["total"]

	# BattleStage 연출
	if battle_stage:
		await battle_stage.play_clash(p_total, e_total)

	# 승패 계산
	var winner: int = -1
	var base_damage: int = absi(p_total - e_total)
	var final_damage: int = 0
	var attr_msg: String = ""

	if p_total > e_total:
		winner = 0
		base_damage += extra_damage

		if selected_attr_name == enemy_weakness:
			final_damage = base_damage * 2
			attr_msg = " [⚡%s 약점 2배]" % ATTRIBUTES.get(selected_attr_name, "")
		elif selected_attr_name == enemy_resistance:
			final_damage = 0
			attr_msg = " [🛡️%s 내성 무효]" % ATTRIBUTES.get(selected_attr_name, "")
		else:
			final_damage = base_damage

		enemy_hp = maxi(0, enemy_hp - final_damage)

	elif e_total > p_total:
		winner = 1
		final_damage = base_damage
		player_hp = maxi(0, player_hp - final_damage)

	# 결과 기록
	_log_battle_result(
		p_data["rolls"], p_total,
		e_data["rolls"], e_total,
		winner, final_damage, selected_attr_name, attr_msg, buff_display_text
	)

	_refresh_status()

	# 게임 종료 판정
	if player_hp <= 0:
		if result_log != null:
			result_log.append_text("\n[☠️ 게임 오버] 패배!\n")
		_set_dice_ui_editable(false)
		if attribute_select != null:
			attribute_select.disabled = true
		if buff_select != null:
			buff_select.disabled = true
	elif enemy_hp <= 0:
		if result_log != null:
			result_log.append_text("\n[🏆 게임 승리] 적 격파!\n")
		_set_dice_ui_editable(false)
		if attribute_select != null:
			attribute_select.disabled = true
		if buff_select != null:
			buff_select.disabled = true
	else:
		if battle_button != null:
			battle_button.disabled = false
		if reset_button != null:
			reset_button.disabled = false
		_set_dice_ui_editable(true)
		if attribute_select != null:
			attribute_select.disabled = false
		if buff_select != null:
			buff_select.disabled = false


func _log_battle_result(
	p_rolls: Array, p_total: int,
	e_rolls: Array, e_total: int,
	winner: int, damage: int, attr_name: String, attr_msg: String, buff_msg: String
) -> void:
	if result_log == null:
		return

	var p_roll_str: String = "%d+%d=%d" % [p_rolls[0], p_rolls[1], p_total]
	var e_roll_str: String = "%d+%d=%d" % [e_rolls[0], e_rolls[1], e_total]

	var attr_icon = ATTRIBUTES.get(attr_name, "")

	if winner == 0:
		result_log.append_text(
			"[✅ 승리] %s (%s vs %s)%s → 적 %d 피해 %s\n"
			% [attr_icon, p_roll_str, e_roll_str, attr_msg, damage, buff_msg]
		)
	elif winner == 1:
		result_log.append_text(
			"[❌ 패배] (%s vs %s) → 내 HP %d 감소\n"
			% [p_roll_str, e_roll_str, damage]
		)
	else:
		result_log.append_text(
			"[🛡️ 무승부] (%s vs %s)\n"
			% [p_roll_str, e_roll_str]
		)


func _on_reset_pressed() -> void:
	player_hp = 100
	enemy_hp = 100
	if result_log != null:
		result_log.clear()
		result_log.append_text("게임이 초기화되었습니다!\n")
	if battle_button != null:
		battle_button.disabled = false
	if reset_button != null:
		reset_button.disabled = false
	_set_dice_ui_editable(true)
	if attribute_select != null:
		attribute_select.disabled = false
		attribute_select.selected = 0
	if buff_select != null:
		buff_select.disabled = false
		buff_select.selected = 0
	_update_displays()
	_refresh_status()


func _refresh_status() -> void:
	if player_hp_label != null:
		player_hp_label.text = "플레이어 HP: %d / 100" % player_hp
	if enemy_hp_label != null:
		enemy_hp_label.text = "적 HP: %d / 100" % enemy_hp
