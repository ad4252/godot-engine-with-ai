extends Node2D
class_name BattleManager

class Dice extends RefCounted:
	var min_p: int
	var max_p: int
	func _init(p_min: int, p_max: int) -> void:
		min_p = p_min
		max_p = p_max
	func roll(rng: RandomNumberGenerator, bonus: int = 0) -> int:
		return rng.randi_range(min_p + bonus, max_p + bonus)

class Skill extends RefCounted:
	var skill_name: String
	var dice_list: Array[Dice] = []
	func _init(n: String, dice_data: Array) -> void:
		skill_name = n
		for pair in dice_data:
			dice_list.append(Dice.new(int(pair[0]), int(pair[1])))
	func roll_all(rng: RandomNumberGenerator, bonus: int = 0) -> Dictionary:
		var rolls: Array[int] = []
		var total := 0
		for dice in dice_list:
			var value := dice.roll(rng, bonus)
			rolls.append(value)
			total += value
		return {"rolls": rolls, "total": total}

const MAX_TOTAL_POINTS := 3
const ATTRIBUTES := {"참격": "⚔", "타격": "✦", "관통": "➶"}
const BUFFS := {"없음": "—", "주사위+1": "🎲", "고정+5": "+5"}
const STARTING_DICE := [[3, 7], [2, 6]]
const ENEMY_WEAKNESS := "참격"
const ENEMY_RESISTANCE := "관통"

var battle_stage: BattleStage
var player_hp_label: Label
var enemy_hp_label: Label
var player_hp_bar: ProgressBar
var enemy_hp_bar: ProgressBar
var battle_button: Button
var reset_button: Button
var result_log: RichTextLabel
var attribute_display: Label
var buff_display: Label
var attribute_select: OptionButton
var buff_select: OptionButton
var resistance_display: RichTextLabel
var resistance_total_label: Label
var ai_status_label: Label
var resistance_boxes: Array[SpinBox] = []

var player_hp := 100
var enemy_hp := 100
var _rng := RandomNumberGenerator.new()
var player_skill: Skill
var enemy_skill: Skill
var enemy_ai: EnemyAI
var battle_history: Array[Dictionary] = []
var current_enemy_dice: Array = STARTING_DICE.duplicate(true)
var battle_finished := false

func _ready() -> void:
	_rng.randomize()
	_apply_trpg_theme()
	battle_stage = get_node_or_null("%BattleStage") as BattleStage
	player_hp_label = get_node_or_null("%PlayerHPLabel") as Label
	enemy_hp_label = get_node_or_null("%EnemyHPLabel") as Label
	player_hp_bar = get_node_or_null("%PlayerHPBar") as ProgressBar
	enemy_hp_bar = get_node_or_null("%EnemyHPBar") as ProgressBar
	battle_button = get_node_or_null("%BattleButton") as Button
	reset_button = get_node_or_null("%ResetButton") as Button
	result_log = get_node_or_null("%BattleLog") as RichTextLabel
	attribute_display = get_node_or_null("%AttributeDisplay") as Label
	buff_display = get_node_or_null("%BuffDisplay") as Label
	attribute_select = get_node_or_null("%AttributeSelect") as OptionButton
	buff_select = get_node_or_null("%BuffSelect") as OptionButton
	resistance_display = get_node_or_null("%ResistanceDisplay") as RichTextLabel
	resistance_total_label = get_node_or_null("%ResistanceTotal") as Label
	ai_status_label = get_node_or_null("%AIStatus") as Label
	resistance_boxes = _get_res_boxes()

	player_skill = Skill.new("연속 베기", STARTING_DICE)
	enemy_skill = Skill.new("맞대응 강타", STARTING_DICE)
	enemy_ai = EnemyAI.new()
	enemy_ai.name = "EnemyAI"
	add_child(enemy_ai)

	_setup_select_ui()
	_setup_resistance_spinboxes()
	if battle_button and not battle_button.pressed.is_connected(_on_battle_pressed):
		battle_button.pressed.connect(_on_battle_pressed)
	if reset_button and not reset_button.pressed.is_connected(_on_reset_pressed):
		reset_button.pressed.connect(_on_reset_pressed)
	if attribute_select:
		attribute_select.item_selected.connect(_on_selection_changed)
	if buff_select:
		buff_select.item_selected.connect(_on_selection_changed)
	if result_log:
		result_log.bbcode_enabled = true
		result_log.scroll_following = true
		result_log.text = "[color=#d8bd83]전투 기록[/color]\n운명의 주사위를 굴려 전투를 시작하세요.\n"
	_refresh_status()
	_update_displays()
	_update_resistance_display()
	_set_ai_status("AI 대기 · 기본 전략")

func _apply_trpg_theme() -> void:
	var theme := Theme.new()
	var normal := _panel_style(Color("28221d"), Color("806b4c"), 2, 10)
	var hover := _panel_style(Color("403326"), Color("d0ad70"), 2, 10)
	var pressed := _panel_style(Color("171411"), Color("e1c18a"), 2, 10)
	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, normal)
		theme.set_stylebox("hover", type_name, hover)
		theme.set_stylebox("pressed", type_name, pressed)
		theme.set_stylebox("disabled", type_name, normal)
		theme.set_color("font_color", type_name, Color("eadfc9"))
		theme.set_color("font_hover_color", type_name, Color("fff0c9"))
		theme.set_font_size("font_size", type_name, 16)
	for type_name in ["SpinBox", "Label", "RichTextLabel"]:
		theme.set_color("font_color", type_name, Color("eadfc9"))
		if type_name != "RichTextLabel":
			theme.set_font_size("font_size", type_name, 16)
	var ui := get_node_or_null("UI_Layout") as Control
	if ui:
		ui.theme = theme

func _panel_style(bg: Color, border_color: Color, border_size: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border_color
	style.set_border_width_all(border_size)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _get_res_boxes() -> Array[SpinBox]:
	var result: Array[SpinBox] = []
	for node_name in ["Slash", "Pierce", "Strike"]:
		var box := get_node_or_null("%" + node_name) as SpinBox
		if box:
			result.append(box)
	return result

func _setup_resistance_spinboxes() -> void:
	for box in resistance_boxes:
		box.min_value = 0
		box.max_value = 2
		box.step = 1
		box.rounded = true
		box.allow_greater = false
		box.allow_lesser = false
		if not box.value_changed.is_connected(_on_resistance_changed):
			box.value_changed.connect(_on_resistance_changed.bind(box))
		box.value = 1

func _on_resistance_changed(_new_value: float, changed_box: SpinBox) -> void:
	var total := 0
	for box in resistance_boxes:
		total += int(box.value)
	if total > MAX_TOTAL_POINTS:
		changed_box.set_value_no_signal(maxi(0, int(changed_box.value) - (total - MAX_TOTAL_POINTS)))
	_update_resistance_display()

func _setup_select_ui() -> void:
	if attribute_select:
		attribute_select.clear()
		for key in ATTRIBUTES.keys():
			attribute_select.add_item(key)
		attribute_select.select(0)
	if buff_select:
		buff_select.clear()
		for key in BUFFS.keys():
			buff_select.add_item(key)
		buff_select.select(0)

func _on_selection_changed(_index: int) -> void:
	_update_displays()

func _update_displays() -> void:
	if attribute_display and attribute_select:
		var key := attribute_select.get_item_text(attribute_select.selected)
		attribute_display.text = "%s  %s" % [ATTRIBUTES.get(key, ""), key]
	if buff_display and buff_select:
		var key := buff_select.get_item_text(buff_select.selected)
		buff_display.text = "%s  %s" % [BUFFS.get(key, ""), key]

func _set_controls_enabled(enabled: bool) -> void:
	if battle_button:
		battle_button.disabled = not enabled
	if reset_button:
		reset_button.disabled = not enabled
	if attribute_select:
		attribute_select.disabled = not enabled
	if buff_select:
		buff_select.disabled = not enabled
	for box in resistance_boxes:
		box.editable = enabled

func _on_battle_pressed() -> void:
	if battle_finished or (battle_stage and battle_stage.busy):
		return
	_set_controls_enabled(false)
	await _execute_battle()

func _execute_battle() -> void:
	var selected_attr := "참격"
	if attribute_select:
		selected_attr = attribute_select.get_item_text(attribute_select.selected)
	var buff_name := "없음"
	if buff_select:
		buff_name = buff_select.get_item_text(buff_select.selected)
	var dice_bonus := 1 if buff_name == "주사위+1" else 0
	var extra_damage := 5 if buff_name == "고정+5" else 0

	# 직전 전투 기록을 바탕으로 적 주사위 범위를 선택합니다.
	_set_ai_status("AI 전략 분석 중…")
	var ai_result: Dictionary = await enemy_ai.choose_action(battle_history, player_hp, enemy_hp)
	current_enemy_dice = ai_result.get("dice_data", STARTING_DICE).duplicate(true)
	enemy_skill = Skill.new("적 대응 주사위", current_enemy_dice)
	_set_ai_status("%s · %s" % [str(ai_result.get("source", "AI")), str(ai_result.get("reason", "전략 선택 완료"))])

	var p_data := player_skill.roll_all(_rng, dice_bonus)
	var e_data := enemy_skill.roll_all(_rng)
	var p_total: int = p_data.total
	var e_total: int = e_data.total
	var p_min := 0
	var p_max := 0
	for die in player_skill.dice_list:
		p_min += die.min_p + dice_bonus
		p_max += die.max_p + dice_bonus
	var e_min := 0
	var e_max := 0
	for die in enemy_skill.dice_list:
		e_min += die.min_p
		e_max += die.max_p
	if battle_stage:
		await battle_stage.play_clash(p_total, e_total, p_min, p_max, e_min, e_max)

	var winner := 0
	var damage := 0
	var attr_msg := ""
	var base_damage := absi(p_total - e_total)
	if p_total > e_total:
		winner = 1
		base_damage += extra_damage
		var enemy_multiplier := 1.0
		if selected_attr == ENEMY_WEAKNESS:
			enemy_multiplier = 2.0
			attr_msg = "[적 약점 · 피해 2배]"
		elif selected_attr == ENEMY_RESISTANCE:
			enemy_multiplier = 0.0
			attr_msg = "[적 내성 · 피해 무효]"
		else:
			attr_msg = "[적에게 정상 피해]"
		damage = int(round(base_damage * enemy_multiplier))
		enemy_hp = maxi(0, enemy_hp - damage)
	elif e_total > p_total:
		winner = -1
		base_damage += extra_damage
		var multiplier := _get_resistance_multiplier(selected_attr)
		damage = int(round(base_damage * multiplier))
		player_hp = maxi(0, player_hp - damage)
		attr_msg = "[%s · %s]" % [selected_attr, _get_resistance_text(selected_attr)]
	else:
		winner = 0

	_log_battle_result(p_data.rolls, p_total, e_data.rolls, e_total, winner, damage, selected_attr, attr_msg, buff_name)
	battle_history.append({
		"turn": battle_history.size() + 1,
		"player_rolls": p_data.rolls,
		"player_total": p_total,
		"enemy_rolls": e_data.rolls,
		"enemy_total": e_total,
		"attribute": selected_attr,
		"buff": buff_name,
		"player_hp_after": player_hp,
		"enemy_hp_after": enemy_hp
	})
	if battle_history.size() > 8:
		battle_history.pop_front()
	_refresh_status()
	if player_hp <= 0:
		battle_finished = true
		_append_log("[color=#e77c70]☠ 패배 · 플레이어의 HP가 0이 되었습니다.[/color]")
	elif enemy_hp <= 0:
		battle_finished = true
		_append_log("[color=#e4c47c]✦ 승리 · 적을 쓰러뜨렸습니다![/color]")
	if not battle_finished:
		_set_controls_enabled(true)

func _log_battle_result(p_rolls: Array, p_total: int, e_rolls: Array, e_total: int, winner: int, damage: int, attr_name: String, attr_msg: String, buff_name: String) -> void:
	var p_str := "%s + %s = %d" % [str(p_rolls[0]), str(p_rolls[1]), p_total]
	var e_str := "%s + %s = %d" % [str(e_rolls[0]), str(e_rolls[1]), e_total]
	var buff_text := " · 강화: %s" % buff_name if buff_name != "없음" else ""
	if winner > 0:
		_append_log("[color=#e4c47c]승리[/color]  플레이어 %s  vs  적 %s\n[color=#d6c6a6]적에게 %d 피해 · %s%s[/color]" % [p_str, e_str, damage, attr_msg, buff_text])
	elif winner < 0:
		_append_log("[color=#df8175]패배[/color]  플레이어 %s  vs  적 %s\n[color=#d6c6a6]플레이어가 %d 피해 · %s%s[/color]" % [p_str, e_str, damage, attr_msg, buff_text])
	else:
		_append_log("[color=#b8b8a8]무승부[/color]  플레이어 %s  vs  적 %s\n[color=#d6c6a6]두 주사위 합이 같아 피해가 없습니다.[/color]" % [p_str, e_str])

func _append_log(message: String) -> void:
	if result_log:
		result_log.append_text("\n" + message + "\n")

func _on_reset_pressed() -> void:
	player_hp = 100
	enemy_hp = 100
	battle_finished = false
	battle_history.clear()
	current_enemy_dice = STARTING_DICE.duplicate(true)
	enemy_skill = Skill.new("맞대응 강타", STARTING_DICE)
	if result_log:
		result_log.clear()
		result_log.text = "[color=#d8bd83]전투 기록[/color]\n새로운 전투가 시작됩니다.\n"
	if attribute_select:
		attribute_select.select(0)
	if buff_select:
		buff_select.select(0)
	_setup_resistance_spinboxes()
	_refresh_status()
	_update_displays()
	_update_resistance_display()
	_set_ai_status("AI 대기 · 기본 전략")
	_set_controls_enabled(true)

func _refresh_status() -> void:
	if player_hp_label:
		player_hp_label.text = "플레이어  ·  %d / 100 HP" % player_hp
	if enemy_hp_label:
		enemy_hp_label.text = "적  ·  %d / 100 HP" % enemy_hp
	if player_hp_bar:
		player_hp_bar.value = player_hp
	if enemy_hp_bar:
		enemy_hp_bar.value = enemy_hp

func _get_resistance_level(attribute: String) -> int:
	var index := 0
	match attribute:
		"참격": index = 0
		"관통": index = 1
		"타격": index = 2
	if index < resistance_boxes.size():
		return int(resistance_boxes[index].value)
	return 1

func _get_resistance_multiplier(attribute: String) -> float:
	match _get_resistance_level(attribute):
		0: return 2.0
		1: return 1.0
		2: return 0.2
	return 1.0

func _get_resistance_text(attribute: String) -> String:
	match _get_resistance_level(attribute):
		0: return "취약 · 피해 2배"
		1: return "보통 · 피해 1배"
		2: return "내성 · 피해 20%"
	return "보통"

func _update_resistance_display() -> void:
	var total := 0
	for box in resistance_boxes:
		total += int(box.value)
	if resistance_total_label:
		resistance_total_label.text = "내성 포인트  %d / %d" % [total, MAX_TOTAL_POINTS]
	if resistance_display:
		resistance_display.text = "⚔ 참격   %s\n➶ 관통   %s\n✦ 타격   %s" % [_get_resistance_text("참격"), _get_resistance_text("관통"), _get_resistance_text("타격")]

func _set_ai_status(message: String) -> void:
	if ai_status_label:
		ai_status_label.text = "◆ " + message
