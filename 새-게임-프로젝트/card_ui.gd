# card_ui.gd
extends Control

class_name CardUI

# ── 신호 ──
signal card_selected(card: BattleManager.Card)

# ── UI 참조 ──
@onready var card_container: HBoxContainer = $CardContainer
@onready var battle_log: TextEdit = $BattleLog

# ── 카드 버튼들 ──
var card_buttons: Array = []

# ── 현재 손패 ──
var current_hand: Array = []


func _ready() -> void:
	# CardContainer에 카드 버튼 5개 생성
	_create_card_buttons()
	
	# BattleLog 설정
	if battle_log:
		battle_log.read_only = true
		battle_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
		battle_log.text = "전투 로그\n"


func _create_card_buttons() -> void:
	# 기존 버튼 삭제
	for btn in card_buttons:
		btn.queue_free()
	card_buttons.clear()
	
	# 5개의 카드 버튼 생성
	for i in range(5):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(80, 120)
		btn.text = "카드 %d" % (i + 1)
		btn.pressed.connect(_on_card_button_pressed.bindv([i]))
		card_container.add_child(btn)
		card_buttons.append(btn)


func update_hand(hand: Array) -> void:
	current_hand = hand
	
	# 버튼 텍스트 업데이트
	for i in range(card_buttons.size()):
		if i < current_hand.size():
			var card = current_hand[i]
			card_buttons[i].text = "%s\n[%s]" % [card.name, card.power_type.to_upper()]
		else:
			card_buttons[i].text = "비어있음"


func _on_card_button_pressed(index: int) -> void:
	if index < current_hand.size():
		var card = current_hand[index]
		print("카드 선택: %s (index: %d)" % [card.name, index])
		card_selected.emit(card)
	else:
		print("유효하지 않은 카드 인덱스: %d" % index)
