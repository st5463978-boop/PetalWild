extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")

## Thirty sim days of the live parish: services, painted districts, policies,
## demand, the stall, the food web, and blight-moths. Prints one SOAK_REPORT
## line, then fails if a bar, the purse, pests, or the population pins or runs away.


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var t: PetalAssert = PA.new("balance_soak")
	var runner: Object = load("res://scripts/city/balance_soak.gd").new()
	var report: Dictionary = runner.call("run", root)
	print("SOAK_REPORT %s" % JSON.stringify(report))
	_expect_band(t, report, "bloom")
	_expect_band(t, report, "hive")
	_expect_band(t, report, "market")
	var coins: Dictionary = report.get("coins", {})
	var start := int(coins.get("start", 0))
	var end := int(coins.get("end", 0))
	t.expect(int(coins.get("min", 0)) >= 8, "coins stay off zero")
	t.expect(int(coins.get("max", 0)) <= 280, "coins do not run away")
	t.expect(end >= 20 and end <= 220, "coins finish the month in a working band")
	t.expect(absi(end - start) >= 4, "coins actually move")
	var pests: Dictionary = report.get("pests", {})
	t.expect(int(pests.get("max", 0)) > int(pests.get("min", 0)), "pest pressure is not pinned")
	t.expect(float(pests.get("mean", 0.0)) >= 0.15, "pests are present across the month")
	t.expect(float(pests.get("mean", 99.0)) <= 3.2, "pests do not sit on the cap")
	var people: Dictionary = report.get("population", {})
	var residents: Array = people.get("residents", [0, 0])
	var web: Array = people.get("web", [0, 0])
	t.expect(int(residents[0]) >= 1 and int(residents[1]) <= 8, "residents stay in the parish band")
	t.expect(int(web[0]) >= 2 and int(web[1]) <= 16, "the food web stays off zero and under the caps")
	t.expect(int(web[1]) > int(web[0]) or int(residents[1]) > int(residents[0]), "population moves")
	t.done()


func _expect_band(t: PetalAssert, report: Dictionary, kind: String) -> void:
	var span: Array = report.get(kind, [0, 0])
	var low := int(span[0])
	var high := int(span[1])
	t.expect(low >= 5, "%s stays off zero" % kind)
	t.expect(high <= 95, "%s stays off 100" % kind)
	t.expect(high - low >= 6, "%s moves across the month" % kind)

