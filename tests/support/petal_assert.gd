class_name PetalAssert
extends RefCounted

## Tiny SceneTree helper. Prints `ok` / `FAIL` lines like tests/smoke.gd.

var suite := "test"
var passed := 0
var failed := 0


func _init(p_suite: String = "test") -> void:
	suite = p_suite


func expect(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("ok  ", label)
		return
	failed += 1
	print("FAIL ", label)


func done() -> void:
	if failed > 0:
		print("%s FAIL %d/%d" % [suite, failed, passed + failed])
		var loop: MainLoop = Engine.get_main_loop()
		loop.quit(1)
		return
	print("%s OK %d" % [suite, passed])
	var tree: MainLoop = Engine.get_main_loop()
	tree.quit(0)
