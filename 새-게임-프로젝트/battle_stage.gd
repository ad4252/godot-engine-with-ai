class_name BattleStage
extends Control

# 슬롯머신 연출 기본값 (범위 미지정 시 기본 2~14)
@export var roll_min := 2
@export var roll_max := 14

@onready var world: Node2D = $World
@onready var player: AnimatedSprite2D = $World/PlayerSprite
@onready var enemy: AnimatedSprite2D = $World/EnemySprite
@onready var player_roll: Label = $World/PlayerRoll
@onready var enemy_roll: Label = $World/EnemyRoll

var player_home := Vector2.ZERO
var enemy_home := Vector2.ZERO
var busy := false


func _ready() -> void:
	# SpriteFrames가 비어 있거나 idle이 없으면 임시 네모 캐릭터 사용
	if _needs_placeholder(player):
		player.sprite_frames = _make_placeholder(Color(0.3, 0.55, 1.0))
	if _needs_placeholder(enemy):
		enemy.sprite_frames = _make_placeholder(Color(1.0, 0.3, 0.4))

	player.scale = Vector2(4, 4)
	enemy.scale = Vector2(4, 4)
	enemy.flip_h = true

	player_roll.text = ""
	enemy_roll.text = ""
	player_roll.pivot_offset = player_roll.size / 2
	enemy_roll.pivot_offset = enemy_roll.size / 2

	resized.connect(_layout)
	_layout()
	_play(player, "idle")
	_play(enemy, "idle")


# ───────── 안전 장치 ─────────

func _needs_placeholder(sprite: AnimatedSprite2D) -> bool:
	return sprite.sprite_frames == null or not sprite.sprite_frames.has_animation("idle")


func _play(sprite: AnimatedSprite2D, anim: String) -> void:
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)


func _layout() -> void:
	if busy:
		return
	player_home = Vector2(size.x * 0.2, size.y * 0.6)
	enemy_home = Vector2(size.x * 0.8, size.y * 0.6)
	player.position = player_home
	enemy.position = enemy_home
	player_roll.position = player_home + Vector2(-20, -140)
	enemy_roll.position = enemy_home + Vector2(-20, -140)


# ─────────────────────────────────────────────
# 메인 함수: 플레이어/적의 (최종값, 최소범위, 최대범위)를 받아서 전투 연출
# 반환값: 1 = 플레이어 승, -1 = 적 승, 0 = 무승부
# ─────────────────────────────────────────────
func play_clash(p_val: int, e_val: int, p_min: int = 2, p_max: int = 14, e_min: int = 2, e_max: int = 14) -> int:
	busy = true
	var result := signi(p_val - e_val)
	var diff := absi(p_val - e_val)
	var center := size / 2.0 + Vector2(0, size.y * 0.1)

	# 1) 주사위 슬롯머신 연출 (전달받은 범위 반영)
	await _dice_roll_effect(p_val, e_val, p_min, p_max, e_min, e_max)

	# 2) 중앙으로 돌진
	_play(player, "attack")
	_play(enemy, "attack")
	var dash := create_tween().set_parallel(true)
	dash.tween_property(player, "position", center + Vector2(-40, 0), 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	dash.tween_property(enemy, "position", center + Vector2(40, 0), 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await dash.finished

	# 3) 충돌: 번쩍 + 화면 흔들림 + 히트스톱
	_flash(center)
	_shake(8.0 + diff * 2.0, 0.25)
	await _hit_stop(0.08)

	# 4) 결과 연출
	if result == 0:
		await _draw_effect(center)
	elif result > 0:
		await _hit_effect(enemy, 1, diff)
	else:
		await _hit_effect(player, -1, diff)

	# 5) 제자리로 복귀
	var back := create_tween().set_parallel(true)
	back.tween_property(player, "position", player_home, 0.3).set_ease(Tween.EASE_OUT)
	back.tween_property(enemy, "position", enemy_home, 0.3).set_ease(Tween.EASE_OUT)
	await back.finished
	_play(player, "idle")
	_play(enemy, "idle")
	player.modulate = Color.WHITE
	enemy.modulate = Color.WHITE

	await get_tree().create_timer(0.3).timeout
	player_roll.text = ""
	enemy_roll.text = ""
	busy = false
	return result


# ───────── 연출 부품들 ─────────

func _dice_roll_effect(p_val: int, e_val: int, p_min: int, p_max: int, e_min: int, e_max: int) -> void:
	var elapsed := 0.0
	var interval := 0.04
	
	# 주사위가 굴러가는 동안 무작위 값 틱틱 변경
	while elapsed < 0.7:
		player_roll.text = str(randi_range(p_min, p_max))
		enemy_roll.text = str(randi_range(e_min, e_max))
		await get_tree().create_timer(interval).timeout
		elapsed += interval
		
	# 최종 수치 확정
	player_roll.text = str(p_val)
	enemy_roll.text = str(e_val)
	
	# 팝(Pop) 스케일 강조 연출
	for lb in [player_roll, enemy_roll]:
		lb.pivot_offset = lb.size / 2
		lb.scale = Vector2(2.2, 2.2)
		create_tween().tween_property(lb, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			
	await get_tree().create_timer(0.4).timeout


func _hit_effect(target: AnimatedSprite2D, dir: int, dmg: int) -> void:
	_play(target, "hurt")
	target.modulate = Color(1, 0.4, 0.4)
	var knock := create_tween().set_parallel(true)
	knock.tween_property(target, "position:x", target.position.x + dir * 60, 0.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_popup("-%d" % dmg, target.position + Vector2(0, -90), Color(1, 0.3, 0.3))
	await knock.finished
	await get_tree().create_timer(0.25).timeout


func _draw_effect(center: Vector2) -> void:
	_popup("무승부!", center + Vector2(0, -90), Color(1, 1, 0.5))
	var bounce := create_tween().set_parallel(true)
	bounce.tween_property(player, "position:x", player.position.x - 50, 0.2)
	bounce.tween_property(enemy, "position:x", enemy.position.x + 50, 0.2)
	await bounce.finished
	await get_tree().create_timer(0.2).timeout


func _flash(pos: Vector2) -> void:
	var f := ColorRect.new()
	f.color = Color(1, 1, 1, 0.9)
	f.size = Vector2(60, 60)
	f.pivot_offset = f.size / 2
	f.position = pos - f.size / 2
	world.add_child(f)
	var t := create_tween().set_parallel(true)
	t.tween_property(f, "scale", Vector2(3, 3), 0.2)
	t.tween_property(f, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(f.queue_free)


func _shake(strength: float, duration: float) -> void:
	var t := create_tween()
	var steps := 8
	for i in steps:
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength
		t.tween_property(world, "position", off, duration / steps)
	t.tween_property(world, "position", Vector2.ZERO, 0.03)


func _hit_stop(duration: float) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _popup(text: String, pos: Vector2, color: Color) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = pos
	lb.add_theme_font_size_override("font_size", 32)
	lb.add_theme_color_override("font_color", color)
	lb.add_theme_color_override("font_outline_color", Color.BLACK)
	lb.add_theme_constant_override("outline_size", 6)
	world.add_child(lb)
	var t := create_tween().set_parallel(true)
	t.tween_property(lb, "position:y", pos.y - 50, 0.8).set_ease(Tween.EASE_OUT)
	t.tween_property(lb, "modulate:a", 0.0, 0.8).set_delay(0.3)
	t.chain().tween_callback(lb.queue_free)


func _make_placeholder(color: Color) -> SpriteFrames:
	var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex := ImageTexture.create_from_image(img)
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in ["idle", "attack", "hurt"]:
		frames.add_animation(anim)
		frames.add_frame(anim, tex)
		frames.set_animation_loop(anim, anim == "idle")
	return frames
