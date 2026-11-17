class_name MusicDirector
extends Node
## Plays the level's soundtrack (MusicSettings): a single looping track, or a playlist that switches on a timer,
## when a base is destroyed, or every N kills (the "DJ death match"). Tracks crossfade through Conductor.

var _game: Game
var _index := 0
var _timer := 0.0
var _kills_seen := 0


func setup(game: Game) -> void:
	_game = game
	GameEvents.base_destroyed.connect(func(_pos: Vector3) -> void:
		if _active() and _music().mode == MusicSettings.ON_BASE_DESTROYED:
			next_track())
	GameEvents.enemy_died.connect(func(_pos: Vector3) -> void:
		if _active() and _music().mode == MusicSettings.EVERY_N_KILLS:
			_kills_seen += 1
			if _kills_seen >= _music().kills_per_switch:
				_kills_seen = 0
				next_track())


## Start the level's music from its first track.
func reset() -> void:
	_index = 0
	_kills_seen = 0
	_timer = _music().switch_seconds
	_play_current(false)


func tick(delta: float) -> void:
	var music := _music()
	if music.mode == MusicSettings.CYCLE_TIMED:
		_timer -= delta
		if _timer <= 0.0:
			_timer = music.switch_seconds
			next_track()


func next_track() -> void:
	var tracks := _music().tracks
	if tracks.size() <= 1:
		return
	_index = (_index + 1) % tracks.size()
	_play_current(true)


func _play_current(fade: bool) -> void:
	var tracks := _music().tracks
	var stream: AudioStream = tracks[_index] if _index < tracks.size() else _game.music
	if stream == null:
		Conductor.play_default(fade)
	else:
		Conductor.play_track(stream, fade)


func _music() -> MusicSettings:
	return _game.board.level.music


func _active() -> bool:
	return _game.mode == Game.Mode.PLAY and not _game.game_over
