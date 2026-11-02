extends WorldEnvironment

# Not in git, see tools/install.txt
const STAR_MAP_PATH = "res://data/source/starmap_2020_4k.exr"

func _ready() -> void:
	var image := Image.load_from_file(STAR_MAP_PATH)
	if image == null:
		push_warning("No star map at %s, the sky stays black" % STAR_MAP_PATH)
		return
	image.convert(Image.FORMAT_RGBH)
	image.generate_mipmaps()
	var material := environment.sky.sky_material as ShaderMaterial
	material.set_shader_parameter("star_map", ImageTexture.create_from_image(image))
