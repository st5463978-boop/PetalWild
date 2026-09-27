extends Node

var last_tier := "offline"
var last_confidence := 0.0
var last_choice := ""
var last_question := ""
var served := {"hef-dfc": 0, "pi-cpu": 0, "hailo": 0, "offline": 0, "forced": 0}
var forced := ""

func choose(question: String, options: Array) -> String:
	if options.size() < 2:
		last_tier = "offline"
		last_confidence = 0.0
		last_choice = str(options[0]) if options.size() > 0 else ""
		last_question = question
		return last_choice
	if forced != "":
		last_tier = "forced"
		last_confidence = 1.0
		last_choice = forced if options.has(forced) else str(options[0])
		last_question = question
		served["forced"] = int(served.get("forced", 0)) + 1
		_log()
		return last_choice
	if OS.get_environment("PETAL_SMOKE") == "1" or OS.get_environment("PETAL_DECIDE") != "1":
		return _offline(question, options)
	var picked := _live(question, options)
	if picked != "":
		return picked
	return _offline(question, options)

func _offline(question: String, options: Array) -> String:
	last_tier = "offline"
	last_confidence = 0.0
	last_choice = str(options[0])
	last_question = question
	served["offline"] = int(served.get("offline", 0)) + 1
	_log()
	return last_choice

func _live(question: String, options: Array) -> String:
	var tiers: Array = _tiers()
	for entry in tiers:
		var row: Dictionary = entry
		var payload := _post(str(row.get("url", "")), question, options, float(row.get("timeout", 15.0)))
		if payload.is_empty():
			continue
		var idx := int(payload.get("index", -1))
		if idx < 0 or idx >= options.size():
			continue
		last_tier = str(row.get("name", "unknown"))
		last_confidence = float(payload.get("confidence", payload.get("margin", 0.0)))
		last_choice = str(options[idx])
		last_question = question
		served[last_tier] = int(served.get(last_tier, 0)) + 1
		_log()
		return last_choice
	return ""

func _tiers() -> Array:
	return [
		{"name": "hef-dfc", "url": _as_decide(OS.get_environment("HAILO_DECIDE_PRIMARY_URL")), "timeout": 15.0, "topic": OS.get_environment("HAILO_DECIDE_PRIMARY_DISCOVERY_URL")},
		{"name": "pi-cpu", "url": _as_decide(OS.get_environment("HAILO_DECIDE_FALLBACK_URL")), "timeout": 60.0, "topic": OS.get_environment("HAILO_DECIDE_FALLBACK_DISCOVERY_URL")},
		{"name": "hailo", "url": _as_decide(OS.get_environment("HAILO_DECIDE_LAST_URL")), "timeout": 75.0, "topic": OS.get_environment("HAILO_DECIDE_DISCOVERY_URL")},
	]

func _as_decide(url: String) -> String:
	var raw := url.strip_edges().rstrip("/")
	if raw == "":
		return ""
	if raw.ends_with("/v1/decide") or raw.ends_with("/decide"):
		return raw
	return raw + "/v1/decide"

func _post(url: String, question: String, options: Array, timeout: float) -> Dictionary:
	if url == "":
		return {}
	var host := ""
	var path := "/v1/decide"
	var port := 80
	var tls := false
	if url.begins_with("https://"):
		tls = true
		port = 443
		var rest := url.substr(8)
		var slash := rest.find("/")
		host = rest if slash < 0 else rest.substr(0, slash)
		path = "/v1/decide" if slash < 0 else rest.substr(slash)
	elif url.begins_with("http://"):
		var rest := url.substr(7)
		var slash := rest.find("/")
		host = rest if slash < 0 else rest.substr(0, slash)
		path = "/v1/decide" if slash < 0 else rest.substr(slash)
	else:
		return {}
	if host.find(":") >= 0:
		var bits := host.split(":")
		host = bits[0]
		port = int(bits[1])
	var client := HTTPClient.new()
	if client.connect_to_host(host, port, TLSOptions.client() if tls else null) != OK:
		return {}
	var started := Time.get_ticks_msec()
	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		if Time.get_ticks_msec() - started > int(timeout * 1000.0):
			client.close()
			return {}
		client.poll()
		OS.delay_msec(20)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		client.close()
		return {}
	var body := JSON.stringify({"question": question, "options": options})
	if client.request(HTTPClient.METHOD_POST, path, PackedStringArray(["Content-Type: application/json"]), body) != OK:
		client.close()
		return {}
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec() - started > int(timeout * 1000.0):
			client.close()
			return {}
		client.poll()
		OS.delay_msec(20)
	var raw := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.size() > 0:
			raw.append_array(chunk)
		else:
			OS.delay_msec(10)
		if Time.get_ticks_msec() - started > int(timeout * 1000.0):
			break
	client.close()
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _log() -> void:
	print("decide tier=%s confidence=%s choice=%s q=%s" % [last_tier, last_confidence, last_choice, last_question])
