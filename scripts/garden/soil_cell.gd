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
	}

func apply_dict(data: Dictionary) -> void:
	tilled = bool(data.get("tilled", tilled))
	moisture = float(data.get("moisture", moisture))
	fertility = float(data.get("fertility", fertility))
	chem = str(data.get("chem", chem))
	plant_id = str(data.get("plant_id", plant_id))
	growth = float(data.get("growth", growth))
