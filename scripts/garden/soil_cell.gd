class_name SoilCell
extends RefCounted

var ix: int = 0
var iz: int = 0
var tilled: bool = false
var moisture: float = 0.28
var fertility: float = 0.3
var chem: String = "base"
var plant_id: String = ""
var growth: float = 0.0
var wilt: float = 0.0
var taken: bool = false
var eaten_by: String = ""
var grow_from_day: int = 1
var hue: float = 0.5
var stature: float = 1.0
var crop_yield: float = 1.0

func to_dict() -> Dictionary:
	return {
		"ix": ix,
		"iz": iz,
		"tilled": tilled,
		"moisture": moisture,
		"fertility": fertility,
		"chem": chem,
		"plant_id": plant_id,
		"growth": growth,
		"wilt": wilt,
		"taken": taken,
		"eaten_by": eaten_by,
		"grow_from_day": grow_from_day,
		"hue": hue,
		"stature": stature,
		"crop_yield": crop_yield,
	}

func apply_dict(data: Dictionary) -> void:
	tilled = bool(data.get("tilled", tilled))
	moisture = float(data.get("moisture", moisture))
	fertility = float(data.get("fertility", fertility))
	chem = str(data.get("chem", chem))
	plant_id = str(data.get("plant_id", plant_id))
	growth = float(data.get("growth", growth))
	wilt = float(data.get("wilt", 0.0))
	taken = bool(data.get("taken", false))
	eaten_by = str(data.get("eaten_by", ""))
	grow_from_day = int(data.get("grow_from_day", 1))
	hue = float(data.get("hue", 0.5))
	stature = float(data.get("stature", 1.0))
	crop_yield = float(data.get("crop_yield", 1.0))
