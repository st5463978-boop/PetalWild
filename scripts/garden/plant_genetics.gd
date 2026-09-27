class_name PlantGenetics
extends RefCounted

static func mix(a: Dictionary, b: Dictionary, salt: int = 0) -> Dictionary:
	return {
		"hue": _blend(float(a.get("hue", 0.5)), float(b.get("hue", 0.5)), salt),
		"stature": _blend(float(a.get("stature", 1.0)), float(b.get("stature", 1.0)), salt + 3),
		"crop_yield": _blend(float(a.get("crop_yield", 1.0)), float(b.get("crop_yield", 1.0)), salt + 7),
	}

static func from_cell(cell: SoilCell) -> Dictionary:
	return {
		"hue": cell.hue,
		"stature": cell.stature,
		"crop_yield": cell.crop_yield,
	}

static func apply_cell(cell: SoilCell, traits: Dictionary) -> void:
	cell.hue = float(traits.get("hue", 0.5))
	cell.stature = float(traits.get("stature", 1.0))
	cell.crop_yield = float(traits.get("crop_yield", 1.0))

static func price(base: int, crop_yield: float) -> int:
	return maxi(1, int(round(float(base) * crop_yield)))

static func _blend(a: float, b: float, salt: int) -> float:
	var mid := (a + b) * 0.5
	var mut := 0.06 * sin(float(salt) * 12.9898)
	return clampf(mid + mut, 0.12, 1.7)
