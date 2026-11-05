@tool
class_name ZoneMap
extends Node3D
## The world and rules of one zone. GameScene expects it as a child named "Map" and only talks
## to it through this class, so shared code never depends on a specific zone.
## A zone without a goal (yet) can use this script directly.

signal won
signal lost

## Time limit in seconds, shown on the wrist. 0 = no limit.
@export var time_limit := 0.0

## Set by GameScene.
var player: Player


## Called when the round begins.
func start() -> void:
	pass


## Called when the round ends.
func stop() -> void:
	pass


func set_paused(_paused: bool) -> void:
	pass
