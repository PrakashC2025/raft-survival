extends AudioStreamPlayer

## Quiet looping ocean bed for the gameplay scene. The low mix leaves room for
## footsteps and interaction sounds, and the MP3 resource is small enough for
## mobile builds.
const OCEAN_STREAM: AudioStream = preload("res://audio/ocean_ambience.mp3")

func _ready() -> void:
	stream = OCEAN_STREAM
	var mp3 := stream as AudioStreamMP3
	if mp3 != null:
		mp3.loop = true
	volume_db = -20.0
	play()
