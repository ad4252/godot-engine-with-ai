extends Node2D

class_name BattleManager

# ── 데이터 클래스 ──
class Dice extends RefCounted:
	var min_p: int
	var max_p: int
	
	func _init(p_min: int, p_max: int) -> void:
		min_p = p_min
		max_p = p_max

	func roll(rng: RandomNumberGenerator, min_boost: int = 0, max_boost: int = 0) -> int:
		var effective_min = mini(max_p + max_boost, min_p + min_boost)
		var effective_max = max_p + max_boost
		return rng.randi_range(effective_min, effective_max)


class Skill extends RefCounted:
	var name: String
	var dice_list: Array = []

	func _init(n: String, dice_data: Array) -> void:
		name = n
		for d in dice_data:
			dice_list.append(Dice.new(d[0], d[1]))

	func dice_info() -> String:
		var s: String = ""
		for d in dice_list:
			s += "[%d~%d] " % [d.min_p, d.max_p]
		return s.strip_edges()


# ── UI 참조 (나중에 할당) ──
var player_hp_label: Label
var enemy_hp_label: Label
var battle_button: Button
var reset_button: Button
var result_log: RichTextLabel # 주의: append_text를 사용하시려면 RichTextLabel이어야 합니다.
var card_ui: Control

# ── 게임 상태 ──
var player_hp: int = 100
var enemy_hp: int = 100
var _rng := RandomNumberGenerator.new()
var player_skill: Skill
var enemy_skill: Skill


func _ready() -> void:
	_rng.randomize()
	
	# 노드 찾기
	player_hp_label = get_node("%PlayerHPLabel")
	enemy_hp_label = get_node("%EnemyHPLabel")
	battle_button = get_node("%BattleButton")
	reset_button = get_node("%ResetButton")
	
	# 🛠️ 수정된 부분: card_ui를 먼저 찾고, 그 자식인 BattleLog를 찾습니다.
	card_ui = get_node("%card_ui")
	result_log = card_ui.get_node("BattleLog")
	
	result_log.scroll_following = true
	
	# 스킬 초기화
	player_skill = Skill.new("연속 베기", [[3, 7], [2, 6]])
	enemy_skill = Skill.new("맞대응 강타", [[3, 7], [2, 6]])
	
	# 버튼 연결
	battle_button.pressed.connect(_on_battle_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	
	# UI 업데이트
	_refresh_status()
	result_log.text = "진행 버튼을 눌러 전투를 시작하세요!\n"


func _on_battle_pressed() -> void:
	_execute_battle()


func _execute_battle() -> void:
	# 플레이어 주사위 굴리기
	var p_rolls: Array = []
	var p_total: int = 0
	for dice in player_skill.dice_list:
		var val = dice.roll(_rng, 0, 0)
		p_rolls.append(val)
		p_total += val
	
	# 적 주사위 굴리기
	var e_rolls: Array = []
	var e_total: int = 0
	for dice in enemy_skill.dice_list:
		var val = dice.roll(_rng, 0, 0)
		e_rolls.append(val)
		e_total += val
	
	# 승패 판정
	var winner: int = -1
	var damage: int = 0
	
	if p_total > e_total:
		winner = 0
		damage = p_total - e_total
		enemy_hp = max(0, enemy_hp - damage)
	elif e_total > p_total:
		winner = 1
		damage = e_total - p_total
		player_hp = max(0, player_hp - damage)
	
	# 주사위 결과 문자열
	var p_roll_str = " + ".join(p_rolls.map(func(x): return str(x)))
	var e_roll_str = " + ".join(e_rolls.map(func(x): return str(x)))
	
	var result_text = "플레이어 (%s = %d) vs 적 (%s = %d)\n" % [
		p_roll_str, p_total, e_roll_str, e_total
	]
	
	# 결과 판정
	if winner == 0:
		result_text += "→ 플레이어 승리! (%d 피해)" % damage
		result_log.append_text("[✅ 승리] %s\n" % result_text)
	elif winner == 1:
		result_text += "→ 적 승리! (%d 피해)" % damage
		result_log.append_text("[❌ 패배] %s\n" % result_text)
	else:
		result_text += "→ 무승부!"
		result_log.append_text("[🛡️ 무승부] %s\n" % result_text)
	
	# 상태 업데이트
	_refresh_status()
	
	# 게임 종료 판정
	if player_hp <= 0:
		result_log.append_text("\n[☠️ 게임 오버] 플레이어 패배!\n")
		battle_button.disabled = true
	elif enemy_hp <= 0:
		result_log.append_text("\n[🏆 게임 승리] 적을 격파했습니다!\n")
		battle_button.disabled = true


func _on_reset_pressed() -> void:
	player_hp = 100
	enemy_hp = 100
	result_log.clear()
	result_log.append_text("게임이 초기화되었습니다!\n")
	battle_button.disabled = false
	_refresh_status()


func _refresh_status() -> void:
	player_hp_label.text = "플레이어 HP: %d / 100" % player_hp
	enemy_hp_label.text = "적 HP: %d / 100" % enemy_hp
