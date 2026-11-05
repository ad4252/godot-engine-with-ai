extends Node2D
class_name BattleManager


# ── 데이터 클래스 ──
class Dice extends RefCounted:
	var min_p: int
	var max_p: int

	func _init(p_min: int, p_max: int) -> void:
		min_p = p_min
		max_p = p_max

	func roll(
		rng: RandomNumberGenerator,
		min_boost: int = 0,
		max_boost: int = 0
	) -> int:
		var effective_max: int = max_p + max_boost
		var effective_min: int = mini(
			effective_max,
			min_p + min_boost
		)

		return rng.randi_range(effective_min, effective_max)


class Skill extends RefCounted:
	var name: String
	var dice_list: Array[Dice] = []

	func _init(n: String, dice_data: Array) -> void:
		name = n

		for d in dice_data:
			dice_list.append(Dice.new(d[0], d[1]))

	func roll_all(rng: RandomNumberGenerator) -> Dictionary:
		var rolls: Array[int] = []
		var total: int = 0

		for dice in dice_list:
			var value: int = dice.roll(rng)
			rolls.append(value)
			total += value

		return {
			"rolls": rolls,
			"total": total
		}


# ── 주사위 설정 UI 배치 ──
# 게임 화면 왼쪽 위를 기준으로 한 위치입니다.
@export var dice_ui_position: Vector2 = Vector2(450, 490)


# ── 기존 노드 참조 ──
# BattleStage가 없어도 주사위 전투는 진행됩니다.
@onready var battle_stage = get_node_or_null("BattleStage")
@onready var player_hp_label: Label = %PlayerHPLabel
@onready var enemy_hp_label: Label = %EnemyHPLabel
@onready var battle_button: Button = %BattleButton
@onready var reset_button: Button = %ResetButton
@onready var card_ui: Control = %card_ui
@onready var result_log: RichTextLabel = (
	card_ui.get_node("BattleLog") as RichTextLabel
)


# ── 코드에서 자동 생성하는 UI ──
var dice_ui_layer: CanvasLayer
var dice_settings_panel: PanelContainer

var dice1_min: SpinBox
var dice1_max: SpinBox
var dice2_min: SpinBox
var dice2_max: SpinBox

var apply_dice_button: Button
var dice_settings_message: Label


# ── 게임 상태 ──
var player_hp: int = 100
var enemy_hp: int = 100

var _rng := RandomNumberGenerator.new()
var _battle_running: bool = false

var player_skill: Skill
var enemy_skill: Skill


func _ready() -> void:
	_rng.randomize()
	result_log.scroll_following = true

	# 플레이어: 첫 번째 주사위 3~7, 두 번째 주사위 2~6
	player_skill = Skill.new(
		"연속 베기",
		[[3, 7], [2, 6]]
	)

	# 적 주사위는 기존 범위 유지
	enemy_skill = Skill.new(
		"맞대응 강타",
		[[3, 7], [2, 6]]
	)

	# 주사위 설정 UI 자동 생성
	_create_dice_settings_ui()
	_sync_dice_ui()

	# 기존 버튼 시그널 연결
	if not battle_button.pressed.is_connected(_on_battle_pressed):
		battle_button.pressed.connect(_on_battle_pressed)

	if not reset_button.pressed.is_connected(_on_reset_pressed):
		reset_button.pressed.connect(_on_reset_pressed)

	_refresh_status()
	_refresh_controls()

	result_log.text = "진행 버튼을 눌러 전투를 시작하세요!\n"


# ── 주사위 설정 UI 생성 ──
func _create_dice_settings_ui() -> void:
	# 별도의 CanvasLayer를 사용하므로 기존 card_ui의
	# 위치나 Container 배치에 영향을 받지 않습니다.
	dice_ui_layer = CanvasLayer.new()
	dice_ui_layer.name = "DiceSettingsLayer"
	dice_ui_layer.layer = 10
	add_child(dice_ui_layer)

	dice_settings_panel = PanelContainer.new()
	dice_settings_panel.name = "DiceSettingsPanel"
	dice_settings_panel.position = dice_ui_position
	dice_settings_panel.custom_minimum_size = Vector2(420, 0)
	dice_ui_layer.add_child(dice_settings_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	dice_settings_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "플레이어 주사위 설정"
	vbox.add_child(title)

	# 첫 번째 주사위 입력 행
	var first_row := HBoxContainer.new()
	first_row.add_theme_constant_override("separation", 10)
	vbox.add_child(first_row)

	var first_label := Label.new()
	first_label.text = "첫 번째 주사위"
	first_label.custom_minimum_size.x = 130
	first_row.add_child(first_label)

	dice1_min = _create_spin_box()
	first_row.add_child(dice1_min)

	var first_separator := Label.new()
	first_separator.text = "~"
	first_row.add_child(first_separator)

	dice1_max = _create_spin_box()
	first_row.add_child(dice1_max)

	# 두 번째 주사위 입력 행
	var second_row := HBoxContainer.new()
	second_row.add_theme_constant_override("separation", 10)
	vbox.add_child(second_row)

	var second_label := Label.new()
	second_label.text = "두 번째 주사위"
	second_label.custom_minimum_size.x = 130
	second_row.add_child(second_label)

	dice2_min = _create_spin_box()
	second_row.add_child(dice2_min)

	var second_separator := Label.new()
	second_separator.text = "~"
	second_row.add_child(second_separator)

	dice2_max = _create_spin_box()
	second_row.add_child(dice2_max)

	# 적용 버튼
	apply_dice_button = Button.new()
	apply_dice_button.text = "설정 적용"
	apply_dice_button.pressed.connect(_on_apply_dice_pressed)
	vbox.add_child(apply_dice_button)

	# 안내 및 오류 메시지
	dice_settings_message = Label.new()
	dice_settings_message.text = "숫자 변경 후 설정 적용을 눌러주세요."
	dice_settings_message.add_theme_font_size_override(
		"font_size",
		14
	)
	vbox.add_child(dice_settings_message)


func _create_spin_box() -> SpinBox:
	var spin := SpinBox.new()

	spin.min_value = 1
	spin.max_value = 100
	spin.step = 1
	spin.rounded = true
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.custom_minimum_size = Vector2(90, 32)

	return spin


# ── 실제 주사위 값을 입력칸에 표시 ──
func _sync_dice_ui() -> void:
	var first_dice: Dice = player_skill.dice_list[0]
	var second_dice: Dice = player_skill.dice_list[1]

	dice1_min.value = first_dice.min_p
	dice1_max.value = first_dice.max_p

	dice2_min.value = second_dice.min_p
	dice2_max.value = second_dice.max_p


# ── 설정 적용 ──
func _on_apply_dice_pressed() -> void:
	if _battle_running or _is_battle_over():
		return

	# 직접 입력한 텍스트도 확정합니다.
	# apply()가 없는 Godot 버전에서는 Enter 입력 신호로 확정합니다.
	_commit_spin_box(dice1_min)
	_commit_spin_box(dice1_max)
	_commit_spin_box(dice2_min)
	_commit_spin_box(dice2_max)

	var first_min: int = int(dice1_min.value)
	var first_max: int = int(dice1_max.value)
	var second_min: int = int(dice2_min.value)
	var second_max: int = int(dice2_max.value)

	# 두 주사위가 모두 정상이어야 적용합니다.
	if first_min > first_max:
		dice_settings_message.text = (
			"첫 번째 주사위: 최솟값 ≤ 최댓값이어야 합니다."
		)
		return

	if second_min > second_max:
		dice_settings_message.text = (
			"두 번째 주사위: 최솟값 ≤ 최댓값이어야 합니다."
		)
		return

	# 실제 전투 데이터 변경
	var first_dice: Dice = player_skill.dice_list[0]
	var second_dice: Dice = player_skill.dice_list[1]

	first_dice.min_p = first_min
	first_dice.max_p = first_max

	second_dice.min_p = second_min
	second_dice.max_p = second_max

	dice_settings_message.text = "적용 완료! 다음 전투부터 반영됩니다."

	result_log.append_text(
		"[주사위 설정] 첫 번째: %d~%d / 두 번째: %d~%d\n"
		% [first_min, first_max, second_min, second_max]
	)


func _commit_spin_box(spin: SpinBox) -> void:
	if spin.has_method("apply"):
		spin.call("apply")
	else:
		var line_edit: LineEdit = spin.get_line_edit()
		line_edit.text_submitted.emit(line_edit.text)


# ── 전투 진행 ──
func _on_battle_pressed() -> void:
	if _battle_running or _is_battle_over():
		return

	if battle_stage and battle_stage.busy:
		return

	_battle_running = true
	_refresh_controls()

	await _execute_battle()

	_battle_running = false
	_refresh_controls()


func _execute_battle() -> void:
	# 1. 주사위 굴리기
	var p_data: Dictionary = player_skill.roll_all(_rng)
	var e_data: Dictionary = enemy_skill.roll_all(_rng)

	var p_total: int = p_data["total"]
	var e_total: int = e_data["total"]

	# 2. 전투 연출 대기
	# BattleStage에는 play_clash(p_total, e_total)가 있어야 합니다.
	if battle_stage:
		await battle_stage.play_clash(p_total, e_total)

	# 3. 승패 및 피해 판정
	var winner: int = -1
	var damage: int = absi(p_total - e_total)

	if p_total > e_total:
		winner = 0
		enemy_hp = maxi(0, enemy_hp - damage)

	elif e_total > p_total:
		winner = 1
		player_hp = maxi(0, player_hp - damage)

	# 4. 결과 기록
	_log_battle_result(
		p_data["rolls"],
		p_total,
		e_data["rolls"],
		e_total,
		winner,
		damage
	)

	# 5. 상태 갱신
	_refresh_status()

	if player_hp <= 0:
		result_log.append_text(
			"\n[게임 오버] 플레이어 패배!\n"
		)
		dice_settings_message.text = "전투 종료! 초기화를 눌러주세요."

	elif enemy_hp <= 0:
		result_log.append_text(
			"\n[게임 승리] 적을 격파했습니다!\n"
		)
		dice_settings_message.text = "전투 종료! 초기화를 눌러주세요."


func _log_battle_result(
	p_rolls: Array,
	p_total: int,
	e_rolls: Array,
	e_total: int,
	winner: int,
	damage: int
) -> void:
	var p_parts := PackedStringArray()
	var e_parts := PackedStringArray()

	for value in p_rolls:
		p_parts.append(str(value))

	for value in e_rolls:
		e_parts.append(str(value))

	var p_roll_str: String = " + ".join(p_parts)
	var e_roll_str: String = " + ".join(e_parts)

	var result_text: String = (
		"플레이어 (%s = %d) vs 적 (%s = %d)\n"
		% [p_roll_str, p_total, e_roll_str, e_total]
	)

	if winner == 0:
		result_log.append_text(
			"[승리] %s→ 플레이어 승리! (%d 피해)\n"
			% [result_text, damage]
		)

	elif winner == 1:
		result_log.append_text(
			"[패배] %s→ 적 승리! (%d 피해)\n"
			% [result_text, damage]
		)

	else:
		result_log.append_text(
			"[무승부] %s→ 무승부!\n" % result_text
		)


# ── 초기화 ──
func _on_reset_pressed() -> void:
	# 연출 도중 초기화되는 상황 방지
	if _battle_running:
		return

	player_hp = 100
	enemy_hp = 100

	# 플레이어와 적 모두 기본 주사위로 복구
	player_skill = Skill.new(
		"연속 베기",
		[[3, 7], [2, 6]]
	)

	enemy_skill = Skill.new(
		"맞대응 강타",
		[[3, 7], [2, 6]]
	)

	_sync_dice_ui()

	result_log.clear()
	result_log.append_text(
		"게임이 초기화되었습니다! 주사위도 기본값으로 복구됩니다.\n"
	)

	dice_settings_message.text = "숫자 변경 후 설정 적용을 눌러주세요."

	_refresh_status()
	_refresh_controls()


# ── 공통 상태 처리 ──
func _is_battle_over() -> bool:
	return player_hp <= 0 or enemy_hp <= 0


func _refresh_controls() -> void:
	var settings_locked: bool = (
		_battle_running or _is_battle_over()
	)

	battle_button.disabled = settings_locked
	apply_dice_button.disabled = settings_locked

	# 전투 종료 후에는 초기화 가능
	reset_button.disabled = _battle_running

	dice1_min.editable = not settings_locked
	dice1_max.editable = not settings_locked
	dice2_min.editable = not settings_locked
	dice2_max.editable = not settings_locked


func _refresh_status() -> void:
	player_hp_label.text = "플레이어 HP: %d / 100" % player_hp
	enemy_hp_label.text = "적 HP: %d / 100" % enemy_hp
