class_name Narrator
extends AudioStreamPlayer
## Radio voice of the guide (not positional). Lines are queued, never overlap.
## - say(line): play now or after the current line
## - line_finished(line) after each line

signal line_finished(line: AudioStream)

var _queue: Array[AudioStream] = []


func _ready() -> void:
	finished.connect(_on_finished)


func say(line: AudioStream) -> void:
	if line == null:
		return
	_queue.append(line)
	if not playing and not stream_paused:
		_play_next()


## Plays the line and waits until it is over.
func say_and_wait(line: AudioStream) -> void:
	if line == null:
		return
	say(line)
	while await line_finished != line:
		pass


func stop_all() -> void:
	_queue.clear()
	stop()


func _on_finished() -> void:
	line_finished.emit(stream)
	_play_next()


func _play_next() -> void:
	if _queue.is_empty():
		return
	stream = _queue.pop_front()
	play()
