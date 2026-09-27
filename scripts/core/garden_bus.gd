class_name GardenBus
extends RefCounted

signal noted(kind: String, text: String)

var log: Array = []

func note(kind: String, text: String) -> void:
	log.push_front({"kind": kind, "text": text})
	if log.size() > 32:
		log.resize(32)
	noted.emit(kind, text)

func last_text(kind: String) -> String:
	for row in log:
		if str(row.get("kind", "")) == kind:
			return str(row.get("text", ""))
	return ""
