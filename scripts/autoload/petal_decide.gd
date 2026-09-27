extends Node

const PRIMARY_TOPIC := "https://ntfy.sh/petalwild-hailojev-decide-hef-729b47676dfdd628/raw?poll=1&since=latest"
const FALLBACK_TOPIC := "https://ntfy.sh/petalwild-hailojev-decide-picpu-78ede63f3f827400/raw?poll=1&since=latest"
const LAST_TOPIC := "https://ntfy.sh/petalwild-hailo-decide-b71128b262bf79cd/raw?poll=1&since=latest"
const LAST_URL := "http://100.126.22.71:8766/decide"

var last_tier := "offline"
var last_confidence := 0.0
var last_margin := 0.0
var last_mode := ""
var last_p_yes := 0.0
var last_choice := ""
var last_question := ""
var served := {"hef-dfc": 0, "pi-cpu": 0, "hailo": 0, "offline": 0, "forced": 0}
var forced := ""
var _resolved := {}

func body_for(question: String, options: Array, context: String = "") -> Dictionary:
	return {"question": question, "context": context, "options": options}

func choose(question: String, options: Array, context: String = "") -> String:
	if options.size() < 2:
		last_tier = "offline"
		last_confidence = 0.0
		last_margin = 0.0
		last_mode = ""
		last_p_yes = 0.0
		last_choice = str(options[0]) if options.size() > 0 else ""
		last_question = question
		return last_choice
	if forced != "":
		last_tier = "forced"
		last_confidence = 1.0
		last_margin = 1.0
		last_mode = "forced"
		last_p_yes = 1.0 if forced == str(options[0]) else 0.0
		last_choice = forced if options.has(forced) else str(options[0])
		last_question = question
		served["forced"] = int(served.get("forced", 0)) + 1
		_log()
		return last_choice
	if OS.get_environment("PETAL_SMOKE") == "1" or OS.get_environment("PETAL_DECIDE") != "1":
		return _offline(question, options)
	var picked := _live(question, options, context)
	if picked != "":
		return picked
	return _offline(question, options)

func _offline(question: String, options: Array) -> String:
	last_tier = "offline"
	last_confidence = 0.0
	last_margin = 0.0
	last_mode = "offline"
	last_p_yes = 0.0
	last_choice = str(options[0])
	last_question = question
	served["offline"] = int(served.get("offline", 0)) + 1
	_log()
	return last_choice

func _live(question: String, options: Array, context: String) -> String:
	var tiers: Array = _tiers()
	for entry in tiers:
		var row: Dictionary = entry
		var url := str(row.get("url", ""))
		if url == "":
			url = _discover(str(row.get("topic", "")))
		if url == "":
			continue
		var payload := _post(url, question, options, context, float(row.get("timeout", 15.0)))
		if payload.is_empty():
			continue
		var idx := int(payload.get("index", -1))
		if idx < 0 or idx >= options.size():
			continue
		last_tier = str(row.get("name", "unknown"))
		last_confidence = float(payload.get("confidence", payload.get("margin", 0.0)))
		last_margin = float(payload.get("margin", 0.0))
		last_mode = str(payload.get("mode", last_tier))
		last_p_yes = float(payload.get("p_yes", 0.0))
		last_choice = str(options[idx])
		last_question = question
		served[last_tier] = int(served.get(last_tier, 0)) + 1
		_log()
		return last_choice
	return ""

func _tiers() -> Array:
	return [
		{"name": "hef-dfc", "url": _as_decide(_env("HAILO_DECIDE_PRIMARY_URL")), "timeout": 15.0, "topic": _env("HAILO_DECIDE_PRIMARY_DISCOVERY_URL", PRIMARY_TOPIC)},
		{"name": "pi-cpu", "url": _as_decide(_env("HAILO_DECIDE_FALLBACK_URL")), "timeout": 60.0, "topic": _env("HAILO_DECIDE_FALLBACK_DISCOVERY_URL", FALLBACK_TOPIC)},
		{"name": "hailo", "url": _as_decide(_env("HAILO_DECIDE_LAST_URL", LAST_URL)), "timeout": 75.0, "topic": _env("HAILO_DECIDE_DISCOVERY_URL", LAST_TOPIC)},
	]

func _env(name: String, fallback: String = "") -> String:
	var raw := OS.get_environment(name).strip_edges()
	return raw if raw != "" else fallback

func _as_decide(url: String) -> String:
	var raw := url.strip_edges().rstrip("/")
	if raw == "":
		return ""
	if raw.ends_with("/v1/decide") or raw.ends_with("/decide"):
		return raw
	return raw + "/decide"

func _discover(topic: String) -> String:
	if topic == "":
		return ""
	if _resolved.has(topic):
		return str(_resolved[topic])
	var text := _http("GET", topic, "", 12.0)
	var found := ""
	for line in text.split("\n"):
		var bit := line.strip_edges()
		if bit.begins_with("https://"):
			found = _as_decide(bit)
	_resolved[topic] = found
	return found

func _post(url: String, question: String, options: Array, context: String, timeout: float) -> Dictionary:
	var payload := _try_post(url, question, options, context, timeout)
	if payload.get("_code", 0) == 503:
		OS.delay_msec(1500)
		payload = _try_post(url, question, options, context, timeout)
	if int(payload.get("_code", 0)) != 200:
		if url.ends_with("/decide") and not url.ends_with("/v1/decide"):
			return _post(url.trim_suffix("/decide") + "/v1/decide", question, options, context, timeout)
		return {}
	payload.erase("_code")
	return payload

func _try_post(url: String, question: String, options: Array, context: String, timeout: float) -> Dictionary:
	var raw := _http("POST", url, JSON.stringify(body_for(question, options, context)), timeout)
	if raw == "":
		return {}
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _http(method: String, url: String, body: String, timeout: float) -> String:
	if url == "":
		return ""
	var host := ""
	var path := "/decide"
	var port := 80
	var tls := false
	if url.begins_with("https://"):
		tls = true
		port = 443
		var rest := url.substr(8)
		var slash := rest.find("/")
		host = rest if slash < 0 else rest.substr(0, slash)
		path = "/" if slash < 0 else rest.substr(slash)
	elif url.begins_with("http://"):
		var rest := url.substr(7)
		var slash := rest.find("/")
		host = rest if slash < 0 else rest.substr(0, slash)
		path = "/" if slash < 0 else rest.substr(slash)
	else:
		return ""
	if host.find(":") >= 0:
		var bits := host.split(":")
		host = bits[0]
		port = int(bits[1])
	var client := HTTPClient.new()
	if client.connect_to_host(host, port, TLSOptions.client() if tls else null) != OK:
		return ""
	var started := Time.get_ticks_msec()
	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		if Time.get_ticks_msec() - started > int(timeout * 1000.0):
			client.close()
			return ""
		client.poll()
		OS.delay_msec(20)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		client.close()
		return ""
	var headers := PackedStringArray(["Content-Type: application/json"]) if method == "POST" else PackedStringArray()
	var verb := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	if client.request(verb, path, headers, body) != OK:
		client.close()
		return ""
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec() - started > int(timeout * 1000.0):
			client.close()
			return ""
		client.poll()
		OS.delay_msec(20)
	var code := client.get_response_code()
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
	var text := raw.get_string_from_utf8()
	if method == "POST":
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		var row: Dictionary = parsed
		row["_code"] = code
		return JSON.stringify(row)
	return JSON.stringify({"_code": code})
	return text

func _log() -> void:
	print("decide tier=%s confidence=%s margin=%s mode=%s p_yes=%s choice=%s q=%s" % [
		last_tier, last_confidence, last_margin, last_mode, last_p_yes, last_choice, last_question
	])
