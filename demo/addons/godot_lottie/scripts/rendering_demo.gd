extends Node2D


func _ready() -> void:
	for notifier in get_tree().get_nodes_in_group("lottie_culling"):
		if notifier is VisibleOnScreenNotifier2D or notifier is VisibleOnScreenEnabler2D:
			for child in notifier.get_children():
				if child is LottieAnimation:
					notifier.screen_entered.connect(func(): _on_screen_entered(child))
					notifier.screen_exited.connect(func(): _on_screen_exited(child))
					break


func _on_screen_entered(lottie: LottieAnimation) -> void:
	lottie.show()
	print("apareceu")


func _on_screen_exited(lottie: LottieAnimation) -> void:
	lottie.hide()
	print("sumiu")
