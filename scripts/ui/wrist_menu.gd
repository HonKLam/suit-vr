class_name WristMenu
extends Control

signal resume_pressed
signal restart_pressed
signal lobby_pressed

@onready var title: Label = %Title
@onready var buttons: Control = %Buttons
@onready var resume_button: Button = %Resume

func _ready() -> void:
	resume_button.pressed.connect(resume_pressed.emit)
	%Restart.pressed.connect(restart_pressed.emit)
	%Lobby.pressed.connect(lobby_pressed.emit)

func show_time(seconds: float) -> void:
	title.text = "%d s" % ceili(seconds)
	buttons.hide()

func show_menu(text: String, can_resume: bool) -> void:
	title.text = text
	resume_button.visible = can_resume
	buttons.show()
