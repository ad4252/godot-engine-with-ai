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
const MAX_TOTAL_POINTS := 3  # 부여되는 총 내성 포인트

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
var attribute_display: Label
var buff_display: Label
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


func _ready() -> void:
	_rng.randomize()
	
	# 모든 노드 참조 안전하게 가져오기
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

	# 스킬 초기화
	player_skill = Skill.new("연속 베기", [[3, 7], [2, 6]])
	enemy_skill = Skill.new("맞대응 강타", [[3, 7], [2, 6]])

	# UI 초기화
	if attribute_select != null and buff_select != null:
		_setup_select_ui()

	# 버튼 시그널 연결
	if battle_button != null:
		battle_button.pressed.connect(_on_battle_pressed)
	if reset_button != null:
		reset_button.pressed.connect(_on_reset_pressed)
	
	if attribute_select != null:
		attribute_select.item_selected.connect(_on_attribute_changed)
	if buff_select != null:
		buff_select.item_selected.connect(_on_buff_changed)
	
	# 🛠️ 내성 SpinBox 자동 감지 및 설정 (개별 0~2 제한 & 총합 3점 제한)
	_setup_resistance_spinboxes()

	_refresh_status()
	_update_displays()
	_update_resistance_display()
	
	if result_log != null:
		result_log.text = "진행 버튼을 눌러 전투를 시작하세요!\n"


# ───────── 🛠️ SpinBox 자동 검색 및 포인트 제어 ─────────

# 씬 트리를 탐색하여 모든 SpinBox 노드를 순서대로 찾아내는 함수
func _find_all_spinboxes(node: Node) -> Array[SpinBox]:
	var result: Array[SpinBox] = []
	if node is SpinBox:
		result.append(node as SpinBox)
	for child in node.get_children():
		result.append_array(_find_all_spinboxes(child))
	return result


# 내성용 SpinBox 3개 가져오기
func _get_res_boxes() -> Array[SpinBox]:
	var boxes: Array[SpinBox] = []
	var b1 = get_node_or_null("%P1Min") as SpinBox
	var b2 = get_node_or_null("%P2Min") as SpinBox
	var b3 = get_node_or_null("%P2Max") as SpinBox
	
	if b1 != null and b2 != null and b3 != null:
		boxes = [b1, b2, b3]
	else:
		# unique name 접근에 실패했을 경우 씬 내부의 모든 SpinBox 자동 탐색
		var all_boxes = _find_all_spinboxes(self)
		if all_boxes.size() >= 3:
			boxes = [all_boxes[0], all_boxes[1], all_boxes[2]]
		else:
			boxes = all_boxes
			
	return boxes


func _setup_resistance_spinboxes() -> void:
	var boxes = _get_res_boxes()
	for box in boxes:
		box.min_value = 0
		box.max_value = 2
		box.step = 1
		box.rounded = true
		box.value = 1  # 기본값: 각각 1포인트 (합 = 3)
		
		if box.value_changed.is_connected(_on_resistance_changed):
			box.value_changed.disconnect(_on_resistance_changed)
		box.value_changed.connect(_on_resistance_changed.bind(box))


# SpinBox 조절 시 총 3포인트 초과 방지
func _on_resistance_changed(_new_val: float, changed_box: SpinBox) -> void:
	var boxes = _get_res_boxes()
	var total = 0
	for b in boxes:
		total += int(b.value)
	
	# 포인트 합이 3을 초과하면 넘어간 만큼 방금 변경한 SpinBox 값을 깎음
	if total > MAX_TOTAL_POINTS:
		var excess = total - MAX_TOTAL_POINTS
		var allowed = int(changed_box.value) - excess
		changed_box.set_value_no_signal(clampi(allowed, 0, 2))
	
	_update_displays()
	_update_resistance_display()


# ───────── UI 초기화 ─────────

func _setup_select_ui() -> void:
	if attribute_select == null or buff_select == null:
		return

	attribute_select.clear()
	for attr_name in ATTRIBUTES.keys():
		attribute_select.add_item(attr_name)
	attribute_select.selected = 0

	buff_select.clear()
	for buff_name in BUFFS.keys():
		buff_select.add_item(buff_name)
	buff_select.selected = 0


func _on_attribute_changed(_index: int) -> void:
	_update_displays()


func _on_buff_changed(_index: int) -> void:
	_update_displays()


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


func _set_dice_ui_editable(value: bool) -> void:
	for box in _get_res_boxes():
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
		base_damage += extra_damage
	
		# 🛠️ 플레이어의 내성 배수 계산
		var resistance_multiplier = _get_resistance_multiplier(selected_attr_name)
		var final_enemy_damage = int(base_damage * resistance_multiplier)
	
		if resistance_multiplier == 2.0:
			attr_msg = " [⚠️ %s 취약 2배]" % selected_attr_name
		elif resistance_multiplier == 0.2:
			attr_msg = " [🛡️ %s 내성 20%%]" % selected_attr_name
		else:
			attr_msg = " [⚪ %s 보통]" % selected_attr_name
	
		final_damage = final_enemy_damage
		player_hp = maxi(0, player_hp - final_enemy_damage)

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
			"[❌ 패배] (%s vs %s)%s → 내 HP %d 감소\n"
			% [p_roll_str, e_roll_str, attr_msg, damage]
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
	
	_setup_resistance_spinboxes()
	_update_displays()
	_refresh_status()


func _refresh_status() -> void:
	if player_hp_label != null:
		player_hp_label.text = "플레이어 HP: %d / 100" % player_hp
	if enemy_hp_label != null:
		enemy_hp_label.text = "적 HP: %d / 100" % enemy_hp


# 🛠️ 속성별 내성 레벨 반환 (위에서부터 순서대로 참격=0번, 관통=1번, 타격=2번)
func _get_resistance_level(attribute: String) -> int:
	var boxes = _get_res_boxes()
	if boxes.size() < 3:
		return 1  # SpinBox가 모자라면 기본 보통(1)
	
	match attribute:
		"참격":
			return int(boxes[0].value)
		"관통":
			return int(boxes[1].value)
		"타격":
			return int(boxes[2].value)
	return 1


# 🛠️ 내성 배수 계산 (0: 취약 2.0배, 1: 보통 1.0배, 2: 내성 0.2배)
func _get_resistance_multiplier(attribute: String) -> float:
	var level = _get_resistance_level(attribute)
	match level:
		0:
			return 2.0   # 취약 (피해 2배)
		1:
			return 1.0   # 보통 (피해 1배)
		2:
			return 0.2   # 내성 (피해 0.2배)
	return 1.0


func _get_resistance_text(attribute: String) -> String:
	var level = _get_resistance_level(attribute)
	match level:
		0:
			return "⚠️ 취약 (2배)"
		1:
			return "⚪ 보통"
		2:
			return "🛡️ 내성 (20%)"
	return "⚪ 보통"


func _update_resistance_display() -> void:
	var boxes = _get_res_boxes()
	var total_used = 0
	for b in boxes:
		total_used += int(b.value)
		
	var text = "사용 포인트: %d / %d\n" % [total_used, MAX_TOTAL_POINTS]
	text += "⚔️ 참격: %s\n" % _get_resistance_text("참격")
	text += "🗡️ 관통: %s\n" % _get_resistance_text("관통")
	text += "🔨 타격: %s" % _get_resistance_text("타격")
	
	print(text)
