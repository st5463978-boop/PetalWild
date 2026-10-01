"""Fresh root-split wall. Each case is proved by the interpreter. No modulo."""

from __future__ import annotations

from jevh_teacher_swarm.verifiers.deterministic.interpret import interpret


def _raw(cid, root, mech, kind, lane, question, options, answer, facts, rule) -> dict:
    if interpret(rule, facts) != answer:
        raise RuntimeError(f"root300 label mismatch {cid}")
    return {
        "id": cid,
        "lane": lane,
        "domain": kind,
        "subdomain": root,
        "attack_family": root,
        "root_family": root,
        "mechanism_id": mech,
        "kind": kind,
        "question": question,
        "options": options,
        "teacher_answer": answer,
        "teacher_confidence": 1.0,
        "teacher_rationale": f"{root} selects {answer}.",
        "required_evidence": [f"deterministic:{rule['op']}"],
        "source_refs": ["jevh_teacher_swarm/verifiers/deterministic/interpret.py"],
        "facts": facts,
        "rule": rule,
        "probe": False,
        "training_eligible": False,
    }


def cmp_case(cid, root, mech, lane, question, yes, no, left, right, rel, flip_options=False):
    facts = {"a": left, "b": right}
    holds = {"gt": left > right, "ge": left >= right, "lt": left < right, "le": left <= right, "eq": left == right, "ne": left != right}[rel]
    answer = yes if holds else no
    options = [yes, no] if flip_options else [no, yes]
    rule = {"op": "cmp", "left": "a", "right": "b", "rel": rel, "if_true": yes, "if_false": no}
    return _raw(cid, root, mech, root, lane, question, options, answer, facts, rule)


def scale_case(cid, root, mech, lane, question, yes, no, n, scale, limit, rel, flip_options=False):
    facts = {"n": n, "scale": scale, "limit": limit}
    value = n * scale
    holds = {"gt": value > limit, "ge": value >= limit, "lt": value < limit, "le": value <= limit}[rel]
    answer = yes if holds else no
    options = [yes, no] if flip_options else [no, yes]
    rule = {"op": "scale_cmp", "left": "n", "scale": "scale", "right": "limit", "rel": rel, "if_true": yes, "if_false": no}
    return _raw(cid, root, mech, root, lane, question, options, answer, facts, rule)


def div_case(cid, root, mech, lane, question, yes, no, n, denom, line, rel, flip_options=False):
    facts = {"n": n, "denom": denom, "line": line}
    value = n // denom
    holds = {"gt": value > line, "ge": value >= line, "lt": value < line, "le": value <= line, "eq": value == line}[rel]
    answer = yes if holds else no
    options = [yes, no] if flip_options else [no, yes]
    rule = {"op": "div_cmp", "left": "n", "denom": "denom", "right": "line", "rel": rel, "if_true": yes, "if_false": no}
    return _raw(cid, root, mech, root, lane, question, options, answer, facts, rule)


def percent_case(cid, root, mech, lane, question, yes, no, part, whole, line, rel, flip_options=False):
    facts = {"part": part, "whole": whole, "line": line}
    value = (part * 100) // whole
    holds = {"gt": value > line, "ge": value >= line, "lt": value < line, "le": value <= line, "eq": value == line}[rel]
    answer = yes if holds else no
    options = [yes, no] if flip_options else [no, yes]
    rule = {"op": "percent_cmp", "part": "part", "whole": "whole", "line": "line", "rel": rel, "if_true": yes, "if_false": no}
    return _raw(cid, root, mech, root, lane, question, options, answer, facts, rule)


def root300_cases() -> list[dict]:
    rows: list[dict] = []
    rows.extend(_units())
    rows.extend(_time())
    rows.extend(_bounds())
    rows.extend(_division())
    rows.extend(_percent_rows())
    rows.extend(_ratios())
    rows.extend(_conservation())
    rows.extend(_signs())
    rows.extend(_stale())
    rows.extend(_authority())
    rows.extend(_permission())
    rows.extend(_transitions())
    rows.extend(_order())
    rows.extend(_completion())
    rows.extend(_concurrency())
    rows.extend(_save())
    rows.extend(_identity())
    rows.extend(_capacity())
    rows.extend(_rounding())
    rows.extend(_index())
    rows.extend(_more())
    return rows


def _ratio(cid, root, mech, lane, question, yes, no, a_num, a_den, b_num, b_den, rel, flip_options=False):
    facts = {"a_num": a_num, "a_den": a_den, "b_num": b_num, "b_den": b_den}
    left = a_num * b_den
    right = b_num * a_den
    holds = {"gt": left > right, "lt": left < right, "eq": left == right}[rel]
    answer = yes if holds else no
    options = [yes, no] if flip_options else [no, yes]
    rule = {
        "op": "ratio_cmp",
        "a_num": "a_num",
        "a_den": "a_den",
        "b_num": "b_num",
        "b_den": "b_den",
        "rel": rel,
        "if_true": yes,
        "if_false": no,
    }
    return _raw(cid, root, mech, root, lane, question, options, answer, facts, rule)


def _more():
    out = []
    root = "inclusive_exclusive_error"
    specs = [
        ("pass-ge", "Mark is {a}. The bar is {b}. Policy: a mark greater than or equal to the bar passes. Does it pass?", "pass", "fail", "ge", ((40, 40), (39, 40))),
        ("pass-gt", "Mark is {a}. The bar is {b}. Policy: only a mark greater than the bar passes. Does it pass?", "pass", "fail", "gt", ((40, 40), (41, 40))),
        ("full-ge", "Count is {a}. The cap is {b}. Policy: count greater than or equal to the cap is full. Is it full?", "full", "room", "ge", ((8, 8), (6, 8))),
        ("full-gt", "Count is {a}. The cap is {b}. Policy: only a count greater than the cap is full. Is it full?", "full", "room", "gt", ((8, 8), (9, 8))),
        ("late-ge", "Delay is {a} minutes. The line is {b} minutes. Policy: delay greater than or equal to the line is late. Is it late?", "late", "on_time", "ge", ((15, 15), (10, 15))),
        ("late-gt", "Delay is {a} minutes. The line is {b} minutes. Policy: only delay greater than the line is late. Is it late?", "late", "on_time", "gt", ((15, 15), (18, 15))),
        ("adult-ge", "Age is {a}. Adulthood starts at {b}. Policy: age greater than or equal to the start is adult. Is this adult?", "adult", "minor", "ge", ((18, 18), (17, 18))),
        ("adult-gt", "Age is {a}. Adulthood starts at {b}. Policy: only age greater than the start is adult. Is this adult?", "adult", "minor", "gt", ((18, 18), (19, 18))),
    ]
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-incl-{name}-{j}", root, f"incl-{name}", "institutions", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 1))
    root = "probability_comparison_error"
    probs = [
        ("rain", "Rain happens {a_num} times in {a_den}. Shine happens {b_num} times in {b_den}. Is rain more likely than shine?", ((1, 5, 1, 2), (1, 2, 1, 5))),
        ("fault", "A fault happens {a_num} times in {a_den}. A miss happens {b_num} times in {b_den}. Is a fault more likely than a miss?", ((1, 10, 1, 4), (1, 3, 1, 8))),
        ("hit", "A hit happens {a_num} times in {a_den}. A miss happens {b_num} times in {b_den}. Is a hit more likely than a miss?", ((3, 4, 1, 4), (1, 4, 3, 4))),
        ("catch", "A catch happens {a_num} times in {a_den}. A drop happens {b_num} times in {b_den}. Is a catch more likely than a drop?", ((2, 3, 1, 3), (1, 3, 2, 3))),
        ("cure", "A cure happens {a_num} times in {a_den}. A relapse happens {b_num} times in {b_den}. Is a cure more likely than a relapse?", ((4, 5, 1, 5), (1, 5, 4, 5))),
        ("sprout", "A sprout happens {a_num} times in {a_den}. A rot happens {b_num} times in {b_den}. Is a sprout more likely than a rot?", ((5, 6, 1, 6), (1, 6, 5, 6))),
    ]
    for i, (name, template, pairs) in enumerate(probs):
        for j, (a_num, a_den, b_num, b_den) in enumerate(pairs):
            question = template.format(a_num=a_num, a_den=a_den, b_num=b_num, b_den=b_den)
            out.append(_ratio(f"r3-prob-{name}-{j}", root, f"prob-{name}", "epistemics", question, "more", "not_more", a_num, a_den, b_num, b_den, "gt", flip_options=i % 2 == 0))
    root = "causal_inversion"
    causes = [
        ("pay", "The effect time is {a}. The cause time is {b}. Policy: the story is inverted when the effect time is less than the cause time. Is it inverted?", "inverted", "ordered", "lt", ((2, 8), (8, 2))),
        ("ship", "Ship time is {a}. Pay time is {b}. Policy: the shipment is inverted when ship time is less than pay time. Is it inverted?", "inverted", "ordered", "lt", ((1, 5), (5, 1))),
        ("harvest", "Harvest time is {a}. Sow time is {b}. Policy: the harvest is inverted when harvest time is less than sow time. Is it inverted?", "inverted", "ordered", "lt", ((3, 9), (9, 3))),
        ("unlock", "Unlock time is {a}. Lock time is {b}. Policy: the unlock is inverted when unlock time is less than lock time. Is it inverted?", "inverted", "ordered", "lt", ((2, 6), (6, 2))),
    ]
    for name, template, yes, no, rel, pairs in causes:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-inv-{name}-{j}", root, f"inv-{name}", "epistemics", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 0))
    return out


def _units():
    root = "unit_conversion_error"
    specs = [
        ("hours-min", "There are 60 minutes in one hour. Work took {n} hours. The cap is {limit} minutes. Is the work over the cap?", 60, ((2, 90), (1, 90))),
        ("days-hours", "There are 24 hours in one day. The wait is {n} days. The cap is {limit} hours. Is the wait over the cap?", 24, ((2, 30), (1, 30))),
        ("min-sec", "There are 60 seconds in one minute. The beep lasts {n} minutes. The cap is {limit} seconds. Is the beep over the cap?", 60, ((2, 90), (1, 150))),
        ("kg-g", "There are 1000 grams in one kilogram. The sack weighs {n} kilograms. The cap is {limit} grams. Is the sack over the cap?", 1000, ((2, 1500), (1, 1500))),
        ("km-m", "There are 1000 metres in one kilometre. The path is {n} kilometres. The cap is {limit} metres. Is the path over the cap?", 1000, ((2, 1500), (1, 2500))),
        ("m-cm", "There are 100 centimetres in one metre. The cloth is {n} metres. The cap is {limit} centimetres. Is the cloth over the cap?", 100, ((2, 150), (1, 250))),
        ("ft-in", "There are 12 inches in one foot. The plank is {n} feet. The cap is {limit} inches. Is the plank over the cap?", 12, ((3, 30), (2, 30))),
        ("yd-ft", "There are 3 feet in one yard. The rope is {n} yards. The cap is {limit} feet. Is the rope over the cap?", 3, ((4, 10), (2, 10))),
        ("l-ml", "There are 1000 millilitres in one litre. The jug holds {n} litres. The cap is {limit} millilitres. Is the jug over the cap?", 1000, ((2, 1500), (1, 2500))),
        ("wk-day", "There are 7 days in one week. The hire is {n} weeks. The cap is {limit} days. Is the hire over the cap?", 7, ((2, 10), (1, 10))),
        ("hr-min-b", "There are 60 minutes in one hour. Baking takes {n} hours. The cap is {limit} minutes. Is baking over the cap?", 60, ((3, 100), (1, 100))),
        ("day-hr-b", "There are 24 hours in one day. The voyage is {n} days. The cap is {limit} hours. Is the voyage over the cap?", 24, ((3, 50), (1, 50))),
        ("g-mg", "There are 1000 milligrams in one gram. The dose is {n} grams. The cap is {limit} milligrams. Is the dose over the cap?", 1000, ((2, 1500), (1, 2500))),
        ("min-hr", "There are 60 minutes in one hour. A shift is {n} hours. The cap is {limit} minutes. Is the shift over the cap?", 60, ((4, 200), (2, 200))),
        ("cm-mm", "There are 10 millimetres in one centimetre. The nail is {n} centimetres. The cap is {limit} millimetres. Is the nail over the cap?", 10, ((3, 25), (2, 25))),
        ("lb-oz", "There are 16 ounces in one pound. The parcel is {n} pounds. The cap is {limit} ounces. Is the parcel over the cap?", 16, ((2, 20), (1, 20))),
        ("st-lb", "There are 14 pounds in one stone. The sack is {n} stone. The cap is {limit} pounds. Is the sack over the cap?", 14, ((2, 20), (1, 20))),
        ("gal-pt", "There are 8 pints in one gallon. The churn holds {n} gallons. The cap is {limit} pints. Is the churn over the cap?", 8, ((2, 10), (1, 10))),
        ("gal-qt", "There are 4 quarts in one gallon. The pot holds {n} gallons. The cap is {limit} quarts. Is the pot over the cap?", 4, ((3, 10), (1, 10))),
        ("qt-pt", "There are 2 pints in one quart. The jug holds {n} quarts. The cap is {limit} pints. Is the jug over the cap?", 2, ((3, 4), (1, 4))),
        ("fathom-ft", "There are 6 feet in one fathom. The depth is {n} fathoms. The cap is {limit} feet. Is the depth over the cap?", 6, ((3, 12), (1, 12))),
        ("fortnight", "There are 14 days in one fortnight. The hire is {n} fortnights. The cap is {limit} days. Is the hire over the cap?", 14, ((2, 20), (1, 20))),
        ("century", "There are 100 years in one century. The span is {n} centuries. The cap is {limit} years. Is the span over the cap?", 100, ((2, 150), (1, 150))),
        ("decade", "There are 10 years in one decade. The span is {n} decades. The cap is {limit} years. Is the span over the cap?", 10, ((3, 20), (1, 20))),
        ("hr-sec", "There are 3600 seconds in one hour. The burn is {n} hours. The cap is {limit} seconds. Is the burn over the cap?", 3600, ((2, 5000), (1, 5000))),
        ("cup-tbsp", "There are 16 tablespoons in one cup. The recipe uses {n} cups. The cap is {limit} tablespoons. Is the recipe over the cap?", 16, ((2, 20), (1, 20))),
        ("tbsp-tsp", "There are 3 teaspoons in one tablespoon. The dose is {n} tablespoons. The cap is {limit} teaspoons. Is the dose over the cap?", 3, ((4, 10), (2, 10))),
        ("bushel-peck", "There are 4 pecks in one bushel. The harvest is {n} bushels. The cap is {limit} pecks. Is the harvest over the cap?", 4, ((3, 8), (1, 8))),
        ("furlong", "There are 220 yards in one furlong. The course is {n} furlongs. The cap is {limit} yards. Is the course over the cap?", 220, ((2, 300), (1, 300))),
        ("chain-yd", "There are 22 yards in one chain. The field is {n} chains. The cap is {limit} yards. Is the field over the cap?", 22, ((2, 30), (1, 30))),
    ]
    out = []
    for i, (name, template, scale, pairs) in enumerate(specs):
        for j, (n, limit) in enumerate(pairs):
            question = template.format(n=n, limit=limit)
            out.append(scale_case(f"r3-unit-{name}-{j}", root, f"unit-{name}", "software", question, "over", "inside", n, scale, limit, "gt", flip_options=i % 2 == 0))
    return out


def _time():
    root = "time_arithmetic_error"
    rows = []
    # start + duration vs deadline, expressed as already-summed facts the question states
    items = [
        ("start {a} plus duration ends at the deadline {b}. The job is late when the end is greater than the deadline. Start is 10 and duration is 5, so the end is 15. Deadline is {b}. Is the job late?", 15, 12, "gt"),
    ]
    # Keep questions self-contained with both numbers in facts. Use direct comparisons of elapsed vs allowed.
    pairs = [
        ("clock-a", "The clock started at minute {a}. It is now minute {b}. Elapsed is now minus start. Is elapsed greater than 4?", 1, 8, "gt"),
    ]
    # Simpler: two explicit totals.
    specs = [
        ("sum-hours", "Morning work is {a} hours and afternoon work is {b} hours. The cap is 7 hours. Is the total over the cap?", ((4, 4), (2, 3))),
        ("sum-min", "Setup is {a} minutes and run is {b} minutes. The cap is 30 minutes. Is the total over the cap?", ((20, 15), (10, 10))),
        ("sum-days", "Travel is {a} days and rest is {b} days. The cap is 6 days. Is the total over the cap?", ((4, 3), (2, 2))),
        ("sum-sec", "Warmup is {a} seconds and measure is {b} seconds. The cap is 20 seconds. Is the total over the cap?", ((12, 10), (5, 5))),
    ]
    # These need add then compare. Use sum of two facts vs a third. Add op via scale? No.
    # Encode cap in the question and facts as c, and use a custom rule by putting sum in a cmp of pre-stated? 
    # I'll use div/scale only where I have ops. For sums, facts a, b and question states cap number which must be in facts as c.
    return rows


def _bounds():
    root = "threshold_boundary_error"
    specs = [
        ("age-gte", "Age is {a}. The stale line is {b}. Policy: age greater than or equal to the line is stale. Is it stale?", "stale", "fresh", "ge", ((6, 6), (4, 6))),
        ("age-gt", "Age is {a}. The stale line is {b}. Policy: only age greater than the line is stale. Is it stale?", "stale", "fresh", "gt", ((6, 6), (8, 6))),
        ("heat-ge", "Heat is {a}. The alarm is {b}. Policy: heat greater than or equal to the alarm pages. Does it page?", "page", "quiet", "ge", ((90, 90), (70, 90))),
        ("heat-gt", "Heat is {a}. The alarm is {b}. Policy: only heat greater than the alarm pages. Does it page?", "page", "quiet", "gt", ((90, 90), (95, 90))),
        ("fill-ge", "Filled units are {a}. Capacity is {b}. Policy: filled greater than or equal to capacity is full. Is it full?", "full", "room", "ge", ((10, 10), (7, 10))),
        ("fill-gt", "Filled units are {a}. Capacity is {b}. Policy: only filled greater than capacity is full. Is it full?", "full", "room", "gt", ((10, 10), (12, 10))),
        ("score-ge", "Score is {a}. The pass mark is {b}. Policy: score greater than or equal to the mark passes. Does it pass?", "pass", "fail", "ge", ((50, 50), (40, 50))),
        ("score-gt", "Score is {a}. The pass mark is {b}. Policy: only a score greater than the mark passes. Does it pass?", "pass", "fail", "gt", ((50, 50), (60, 50))),
        ("lag-ge", "Lag is {a} ms. The line is {b} ms. Policy: lag greater than or equal to the line is late. Is it late?", "late", "on_time", "ge", ((20, 20), (10, 20))),
        ("lag-gt", "Lag is {a} ms. The line is {b} ms. Policy: only lag greater than the line is late. Is it late?", "late", "on_time", "gt", ((20, 20), (30, 20))),
        ("votes-ge", "Votes are {a}. Need is {b}. Policy: votes greater than or equal to the need carries. Does it carry?", "carry", "fall", "ge", ((5, 5), (3, 5))),
        ("votes-gt", "Votes are {a}. Need is {b}. Policy: only votes greater than the need carries. Does it carry?", "carry", "fall", "gt", ((5, 5), (6, 5))),
        ("disk-ge", "Disk use is {a} percent. The page line is {b} percent. Policy: use greater than or equal to the line pages. Does it page?", "page", "quiet", "ge", ((90, 90), (40, 90))),
        ("disk-gt", "Disk use is {a} percent. The page line is {b} percent. Policy: only use greater than the line pages. Does it page?", "page", "quiet", "gt", ((90, 90), (95, 90))),
        ("fee-ge", "Fee is {a} cents. Balance is {b} cents. Policy: a fee greater than the balance is refused. Is it refused?", "refused", "accepted", "gt", ((10, 10), (12, 10))),
        ("fee-eq", "Code is {a}. Expected code is {b}. Policy: equal codes are accepted. Is it accepted?", "accepted", "rejected", "eq", ((4, 4), (4, 9))),
    ]
    out = []
    for i, (name, template, yes, no, rel, pairs) in enumerate(specs):
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-bound-{name}-{j}", root, f"bound-{name}", "software", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 1))
    return out


def _division():
    root = "integer_division_error"
    specs = [
        ("groups", "There are {n} items. A full group holds {denom}. Full groups are the integer quotient. Is that count greater than {line}?", ((17, 5, 2), (9, 5, 2))),
        ("seats", "There are {n} people. A table seats {denom}. Full tables are the integer quotient. Is that count greater than {line}?", ((23, 6, 3), (10, 6, 3))),
        ("pages", "There are {n} lines. A page holds {denom} lines. Full pages are the integer quotient. Is that count greater than {line}?", ((25, 10, 2), (15, 10, 2))),
        ("boxes", "There are {n} bottles. A box holds {denom}. Full boxes are the integer quotient. Is that count greater than {line}?", ((20, 6, 3), (11, 6, 3))),
        ("weeks", "There are {n} days. A week is {denom} days. Full weeks are the integer quotient. Is that count greater than {line}?", ((20, 7, 2), (10, 7, 2))),
        ("dozens", "There are {n} eggs. A dozen is {denom}. Full dozens are the integer quotient. Is that count greater than {line}?", ((30, 12, 2), (15, 12, 2))),
        ("racks", "There are {n} loaves. A rack holds {denom}. Full racks are the integer quotient. Is that count greater than {line}?", ((14, 4, 3), (7, 4, 3))),
        ("reels", "There are {n} metres of line. A reel holds {denom} metres. Full reels are the integer quotient. Is that count greater than {line}?", ((25, 8, 3), (9, 8, 3))),
        ("shifts", "There are {n} hours. A shift is {denom} hours. Full shifts are the integer quotient. Is that count greater than {line}?", ((26, 8, 3), (12, 8, 3))),
        ("packs", "There are {n} nails. A pack holds {denom}. Full packs are the integer quotient. Is that count greater than {line}?", ((19, 5, 3), (8, 5, 3))),
        ("buses", "There are {n} riders. A bus seats {denom}. Full buses are the integer quotient. Is that count greater than {line}?", ((45, 12, 3), (20, 12, 3))),
        ("trays", "There are {n} buns. A tray holds {denom}. Full trays are the integer quotient. Is that count greater than {line}?", ((22, 6, 3), (10, 6, 3))),
    ]
    out = []
    for i, (name, template, triples) in enumerate(specs):
        for j, (n, denom, line) in enumerate(triples):
            question = template.format(n=n, denom=denom, line=line)
            out.append(div_case(f"r3-div-{name}-{j}", root, f"div-{name}", "software", question, "yes", "no", n, denom, line, "gt", flip_options=i % 2 == 0))
    return out


def _percent_rows():
    root = "percentage_reasoning_error"
    specs = [
        ("share", "The part is {part} and the whole is {whole}. Integer percent is the part times one hundred, divided by the whole. Is that percent greater than {line}?", ((40, 200, 15), (10, 200, 15))),
        ("discount", "The cut is {part} off a price of {whole}. Integer percent is the cut times one hundred, divided by the price. Is that percent greater than {line}?", ((25, 100, 20), (10, 100, 20))),
        ("yield", "Good units are {part} out of {whole}. Integer percent is good times one hundred, divided by the whole. Is that percent greater than {line}?", ((90, 100, 80), (50, 100, 80))),
        ("loss", "Lost units are {part} out of {whole}. Integer percent is lost times one hundred, divided by the whole. Is that percent greater than {line}?", ((30, 100, 20), (10, 100, 20))),
        ("fill", "Filled volume is {part} of a tank of {whole}. Integer percent is filled times one hundred, divided by the tank. Is that percent greater than {line}?", ((75, 100, 50), (25, 100, 50))),
        ("attendance", "Present people are {part} of a roll of {whole}. Integer percent is present times one hundred, divided by the roll. Is that percent greater than {line}?", ((18, 20, 80), (10, 20, 80))),
        ("scrap", "Scrap pieces are {part} of a run of {whole}. Integer percent is scrap times one hundred, divided by the run. Is that percent greater than {line}?", ((8, 40, 15), (2, 40, 15))),
        ("battery", "Charge left is {part} of a full {whole}. Integer percent is charge times one hundred, divided by full. Is that percent greater than {line}?", ((15, 60, 20), (6, 60, 20))),
        ("votes", "Ayes are {part} of {whole} ballots. Integer percent is ayes times one hundred, divided by ballots. Is that percent greater than {line}?", ((60, 100, 50), (30, 100, 50))),
        ("moisture", "Water weight is {part} of a sample of {whole}. Integer percent is water times one hundred, divided by the sample. Is that percent greater than {line}?", ((12, 40, 20), (4, 40, 20))),
        ("uptime", "Up minutes are {part} of a window of {whole}. Integer percent is up times one hundred, divided by the window. Is that percent greater than {line}?", ((95, 100, 90), (70, 100, 90))),
        ("error", "Failed calls are {part} of {whole} calls. Integer percent is failed times one hundred, divided by calls. Is that percent greater than {line}?", ((6, 20, 20), (2, 20, 20))),
    ]
    out = []
    for i, (name, template, triples) in enumerate(specs):
        for j, (part, whole, line) in enumerate(triples):
            question = template.format(part=part, whole=whole, line=line)
            out.append(percent_case(f"r3-pct-{name}-{j}", root, f"pct-{name}", "economy", question, "yes", "no", part, whole, line, "gt", flip_options=j == 1))
    return out


def _ratios():
    root = "ratio_rate_error"
    # rate = distance/time integer. Is rate greater than line?
    specs = [
        ("walk", "The walk is {n} metres and takes {denom} seconds. Integer speed is metres divided by seconds. Is that speed greater than {line}?", ((20, 4, 4), (10, 4, 4))),
        ("pump", "The pump moves {n} litres in {denom} minutes. Integer rate is litres divided by minutes. Is that rate greater than {line}?", ((30, 5, 5), (12, 5, 5))),
        ("type", "The clerk types {n} words in {denom} minutes. Integer rate is words divided by minutes. Is that rate greater than {line}?", ((40, 5, 6), (15, 5, 6))),
        ("kiln", "The kiln finishes {n} pots in {denom} hours. Integer rate is pots divided by hours. Is that rate greater than {line}?", ((18, 3, 5), (9, 3, 5))),
        ("press", "The press prints {n} sheets in {denom} minutes. Integer rate is sheets divided by minutes. Is that rate greater than {line}?", ((24, 4, 5), (8, 4, 5))),
        ("cart", "The cart covers {n} miles in {denom} hours. Integer rate is miles divided by hours. Is that rate greater than {line}?", ((28, 4, 6), (12, 4, 6))),
        ("well", "The well yields {n} buckets in {denom} hours. Integer rate is buckets divided by hours. Is that rate greater than {line}?", ((16, 4, 3), (8, 4, 3))),
        ("loom", "The loom weaves {n} ells in {denom} hours. Integer rate is ells divided by hours. Is that rate greater than {line}?", ((15, 3, 4), (6, 3, 4))),
    ]
    out = []
    for i, (name, template, triples) in enumerate(specs):
        for j, (n, denom, line) in enumerate(triples):
            question = template.format(n=n, denom=denom, line=line)
            out.append(div_case(f"r3-rate-{name}-{j}", root, f"rate-{name}", "economy", question, "yes", "no", n, denom, line, "gt", flip_options=i % 2 == 0))
    return out


def _conservation():
    root = "resource_conservation_error"
    specs = [
        ("stock", "Stock in is {a}. Stock out is {b}. Policy: out greater than in breaks conservation. Does it break?", "breaks", "holds", "gt", ((4, 6), (8, 3))),
        ("till", "Counted cash is {a} pence. The book says {b} pence. Policy: counted less than the book is short. Is it short?", "short", "whole", "lt", ((90, 100), (100, 100))),
        ("crates", "Crates loaded are {a}. The manifest says {b}. Policy: loaded not equal to the manifest is a break. Is it a break?", "break", "match", "ne", ((7, 9), (9, 9))),
        ("flour", "Flour used is {a} kg. Flour drawn is {b} kg. Policy: used greater than drawn is a loss. Is it a loss?", "loss", "kept", "gt", ((6, 4), (3, 4))),
        ("water", "Water poured is {a} litres. The jug held {b} litres. Policy: poured greater than held is impossible waste. Is it waste?", "waste", "kept", "gt", ((5, 3), (2, 3))),
        ("seats", "Tickets sold are {a}. Seats are {b}. Policy: sold greater than seats oversells. Does it oversell?", "oversell", "fits", "gt", ((12, 10), (8, 10))),
        ("ration", "Rations issued are {a}. Rations baked are {b}. Policy: issued greater than baked is a shortfall. Is it a shortfall?", "shortfall", "covered", "gt", ((9, 6), (4, 6))),
        ("oil", "Oil burned is {a} hours. Oil bought is {b} hours. Policy: burned greater than bought is a deficit. Is it a deficit?", "deficit", "covered", "gt", ((7, 5), (3, 5))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-cons-{name}-{j}", root, f"cons-{name}", "economy", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 0))
    return out


def _signs():
    root = "negative_sign_error"
    specs = [
        ("bal", "The balance change is {a}. A loss is a change less than {b}. Is this a loss?", "loss", "gain", "lt", ((-4, 0), (3, 0))),
        ("temp", "The temperature change is {a} degrees. A drop is a change less than {b}. Is this a drop?", "drop", "rise", "lt", ((-2, 0), (5, 0))),
        ("stock", "The stock change is {a}. A shrink is a change less than {b}. Is this a shrink?", "shrink", "grow", "lt", ((-6, 0), (2, 0))),
        ("debt", "The ledger change is {a} pence. A debt is a change less than {b}. Is this a debt?", "debt", "credit", "lt", ((-8, 0), (8, 0))),
        ("level", "The water change is {a} cm. A fall is a change less than {b}. Is this a fall?", "fall", "rise", "lt", ((-3, 0), (1, 0))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            # questions contain the minus sign; the digit still has to be in facts
            out.append(cmp_case(f"r3-sign-{name}-{j}", root, f"sign-{name}", "economy", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 1))
    return out


def _stale():
    root = "stale_state_preference"
    specs = [
        ("cache", "Cache age is {a} minutes. Max age is {b} minutes. Policy: age greater than max age is stale. Is the cache stale?", "stale", "fresh", "gt", ((40, 15), (5, 15))),
        ("lease", "Lease age is {a} hours. Life is {b} hours. Policy: age greater than life is dead. Is the lease dead?", "dead", "alive", "gt", ((9, 6), (2, 6))),
        ("cert", "Certificate age is {a} days. Life is {b} days. Policy: age greater than life is expired. Is it expired?", "expired", "current", "gt", ((400, 365), (10, 365))),
        ("backup", "Hours since backup are {a}. The RPO is {b} hours. Policy: hours greater than the RPO is too old. Is it too old?", "too_old", "fresh", "gt", ((30, 12), (4, 12))),
        ("menu", "Menu age is {a} hours. The kitchen refreshes every {b} hours. Policy: age greater than the refresh is stale. Is the menu stale?", "stale", "fresh", "gt", ((8, 4), (1, 4))),
        ("map", "Map age is {a} days. The survey is good for {b} days. Policy: age greater than that is stale. Is the map stale?", "stale", "fresh", "gt", ((20, 7), (2, 7))),
        ("token", "Token age is {a} minutes. The fresh window is {b} minutes. Policy: age greater than the window is stale. Is the token stale?", "stale", "fresh", "gt", ((30, 10), (4, 10))),
        ("quote", "Quote age is {a} hours. The quote lives {b} hours. Policy: age greater than life is stale. Is the quote stale?", "stale", "fresh", "gt", ((48, 24), (6, 24))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-stale-{name}-{j}", root, f"stale-{name}", "epistemics", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 0))
    return out


def _authority():
    root = "memory_authority_error"
    # rank cases are structural; encode as cmp of stated ranks: higher number outranks
    specs = [
        ("src", "Runtime rank is {a}. Memory rank is {b}. Policy: the higher rank wins. Does runtime win?", "runtime", "memory", "gt", ((5, 2), (2, 5))),
        ("doc", "Canon rank is {a}. Note rank is {b}. Policy: the higher rank wins. Does canon win?", "canon", "note", "gt", ((4, 1), (1, 4))),
        ("log", "Ledger rank is {a}. Chatter rank is {b}. Policy: the higher rank wins. Does the ledger win?", "ledger", "chatter", "gt", ((6, 3), (3, 6))),
        ("sign", "Live rank is {a}. Signed-note rank is {b}. Policy: the higher rank wins, and a signature does not raise rank. Does live win?", "live", "note", "gt", ((7, 3), (3, 7))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-auth-{name}-{j}", root, f"auth-{name}", "epistemics", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 1))
    return out


def _permission():
    root = "permission_scope_error"
    specs = [
        ("rank", "Actor rank is {a}. The action requires rank {b}. Policy: allowed when actor rank is greater than or equal to the requirement. Is it allowed?", "allowed", "denied", "ge", ((3, 1), (1, 3))),
        ("scope", "Scope code is {a}. The call needs scope code {b}. Policy: allowed only when the codes are equal. Is it allowed?", "allowed", "denied", "eq", ((4, 4), (4, 2))),
        ("grant", "Grant rank is {a}. Admin needs rank {b}. Policy: the grant covers admin when grant rank is greater than or equal to the need. Does it cover admin?", "covers", "misses", "ge", ((5, 5), (2, 5))),
        ("child", "Parent revoked flag is {a}. Revoked means flag equal to {b}. Is the parent revoked?", "revoked", "live", "eq", ((1, 1), (0, 1))),
        ("mfa", "MFA age is {a} minutes. Fresh is under {b} minutes. Policy: fresh when age is less than the window. Is MFA fresh?", "fresh", "stale", "lt", ((4, 15), (20, 15))),
        ("region", "Region code is {a}. Allowed region code is {b}. Policy: entry when codes are equal. Is entry allowed?", "allowed", "blocked", "eq", ((3, 3), (3, 8))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-perm-{name}-{j}", root, f"perm-{name}", "institutions", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 0))
    return out


def _transitions():
    root = "invalid_state_transition"
    specs = [
        ("step", "Current step is {a}. The event asks for step {b}. Policy: the move is valid only when the event step equals current plus one, and here we compare event step greater than current. Is the jump too far?", "too_far", "next", "gt", ((1, 3), (2, 3))),
    ]
    # Use explicit allowed-edge style via numbers: from-state vs to-state where valid means to == from+1, tested as to > from+? 
    # "from 2 to 3 is the next step. to greater than from is a forward move." That's weak.
    specs = [
        ("skip", "From-state is {a}. To-state is {b}. Policy: a skip is to-state greater than from-state plus nothing we hide: a skip means to-state is greater than from-state by more than 1, asked as to-state greater than from-state. Is it a forward move?", "forward", "not_forward", "gt", ((2, 5), (5, 5))),
    ]
    return []


def _order():
    root = "temporal_order_error"
    specs = [
        ("cause", "Cause time is {a}. Effect time is {b}. Policy: the effect is valid when effect time is greater than cause time. Is the effect valid?", "valid", "invalid", "gt", ((3, 8), (8, 3))),
        ("ship", "Payment time is {a}. Ship time is {b}. Policy: shipping is valid when ship time is greater than payment time. Is shipping valid?", "valid", "invalid", "gt", ((2, 6), (6, 2))),
        ("bake", "Heat-on time is {a}. Remove time is {b}. Policy: removal is valid when remove time is greater than heat-on time. Is removal valid?", "valid", "invalid", "gt", ((1, 4), (4, 1))),
        ("sign", "Draft time is {a}. Sign time is {b}. Policy: signing is valid when sign time is greater than draft time. Is signing valid?", "valid", "invalid", "gt", ((5, 9), (9, 5))),
        ("plant", "Sow time is {a}. Harvest time is {b}. Policy: harvest is valid when harvest time is greater than sow time. Is harvest valid?", "valid", "invalid", "gt", ((2, 10), (10, 2))),
        ("lock", "Lock time is {a}. Unlock time is {b}. Policy: unlock is valid when unlock time is greater than lock time. Is unlock valid?", "valid", "invalid", "gt", ((4, 7), (7, 4))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            # template compares b ? a but our cmp is a ? b. Swap the numbers in the question wording carefully.
            # Policy says effect (b) > cause (a). Our _cmp uses left=a right=b rel gt means a>b.
            # I need effect > cause, so pass left=effect, right=cause, but the question names cause first.
            # Easiest: question "Cause time is {a}. Effect time is {b}." and rel is lt meaning a < b, yes=valid.
            out.append(cmp_case(f"r3-timeord-{name}-{j}", root, f"ord-{name}", "epistemics", template.format(a=a, b=b), yes, no, a, b, "lt", flip_options=j == 1))
    return out


def _completion():
    root = "false_completion_error"
    specs = [
        ("job", "Finished steps are {a}. Required steps are {b}. Policy: complete when finished is greater than or equal to required. Is it complete?", "complete", "open", "ge", ((5, 5), (3, 5))),
        ("paint", "Coats laid are {a}. Coats required are {b}. Policy: done when laid is greater than or equal to required. Is it done?", "done", "open", "ge", ((3, 3), (1, 3))),
        ("sew", "Seams closed are {a}. Seams required are {b}. Policy: done when closed is greater than or equal to required. Is it done?", "done", "open", "ge", ((8, 8), (6, 8))),
        ("check", "Checks signed are {a}. Checks required are {b}. Policy: cleared when signed is greater than or equal to required. Is it cleared?", "cleared", "open", "ge", ((2, 2), (1, 2))),
        ("load", "Crates loaded are {a}. Crates required are {b}. Policy: loaded when the counts meet, meaning loaded is greater than or equal to required. Is it loaded?", "loaded", "open", "ge", ((10, 10), (7, 10))),
        ("wash", "Rinses done are {a}. Rinses required are {b}. Policy: done when rinses are greater than or equal to required. Is it done?", "done", "open", "ge", ((4, 4), (2, 4))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-done-{name}-{j}", root, f"done-{name}", "software", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 0))
    return out


def _concurrency():
    root = "concurrency_race_error"
    specs = [
        ("lock", "Lock holder id is {a}. Requester id is {b}. Policy: the requester may write only when the ids are equal. May the requester write?", "write", "wait", "eq", ((4, 4), (4, 7))),
        ("epoch", "Request epoch is {a}. Fenced epoch is {b}. Policy: the write is allowed when request epoch is greater than the fence. Is the write allowed?", "allowed", "fenced", "gt", ((6, 5), (5, 5))),
        ("version", "Write version is {a}. Stored version is {b}. Policy: the write conflicts when the versions are not equal. Does it conflict?", "conflict", "clean", "ne", ((9, 8), (9, 9))),
        ("token", "Held tokens are {a}. A call needs {b}. Policy: the call runs when held tokens are greater than or equal to the need. Does it run?", "runs", "waits", "ge", ((1, 1), (0, 1))),
        ("seat", "Busy workers are {a}. Pool size is {b}. Policy: the pool is full when busy is greater than or equal to size. Is it full?", "full", "spare", "ge", ((8, 8), (3, 8))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-race-{name}-{j}", root, f"race-{name}", "software", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 1))
    return out


def _save():
    root = "save_state_invariant_error"
    specs = [
        ("ver", "New save version is {a}. Current version is {b}. Policy: the save is legal when the new version is greater than the current version. Is it legal?", "legal", "illegal", "gt", ((5, 4), (4, 4))),
        ("gen", "Observed generation is {a}. Metadata generation is {b}. Policy: status is stale when observed is less than metadata. Is status stale?", "stale", "fresh", "lt", ((4, 5), (5, 5))),
        ("slot", "Slot written is {a}. Slots required are {b}. Policy: the save is complete when written is greater than or equal to required. Is it complete?", "complete", "partial", "ge", ((3, 3), (1, 3))),
        ("crc", "Computed check code is {a}. Stored check code is {b}. Policy: the save matches when the codes are equal. Does it match?", "match", "corrupt", "eq", ((12, 12), (12, 9))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-save-{name}-{j}", root, f"save-{name}", "software", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 0))
    return out


def _identity():
    root = "identity_confusion"
    specs = [
        ("id", "Presented id is {a}. Canon id is {b}. Policy: it is the same entity when the ids are equal. Is it the same entity?", "same", "different", "eq", ((14, 14), (14, 15))),
        ("serial", "Tool serial is {a}. Issued serial is {b}. Policy: it is the issued tool when the serials are equal. Is it the issued tool?", "issued", "other", "eq", ((7, 7), (7, 8))),
        ("badge", "Badge code is {a}. Roster code is {b}. Policy: the person matches when the codes are equal. Does the person match?", "match", "stranger", "eq", ((3, 3), (3, 9))),
        ("lot", "Lot code is {a}. Order lot code is {b}. Policy: it is the ordered lot when the codes are equal. Is it the ordered lot?", "ordered", "other", "eq", ((21, 21), (21, 22))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-id-{name}-{j}", root, f"id-{name}", "epistemics", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 1))
    return out


def _capacity():
    root = "capacity_constraint_error"
    specs = [
        ("bin", "Items in the bin are {a}. The bin holds {b}. Policy: it overflows when items are greater than the hold. Does it overflow?", "overflow", "fits", "gt", ((12, 10), (8, 10))),
        ("hall", "People in the hall are {a}. The hall holds {b}. Policy: it is over capacity when people are greater than the hold. Is it over capacity?", "over", "inside", "gt", ((40, 30), (20, 30))),
        ("cart", "Cart load is {a} kg. The axle holds {b} kg. Policy: it is overweight when load is greater than the hold. Is it overweight?", "over", "legal", "gt", ((90, 70), (40, 70))),
        ("pool", "Borrowed sockets are {a}. The pool holds {b}. Policy: it is over cap when borrowed is greater than the hold. Is it over cap?", "over", "inside", "gt", ((16, 12), (6, 12))),
        ("queue", "Waiting jobs are {a}. Workers are {b}. Policy: the queue is backed up when jobs are greater than workers. Is it backed up?", "backed_up", "flowing", "gt", ((9, 4), (2, 4))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-cap-{name}-{j}", root, f"cap-{name}", "software", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 0))
    return out


def _rounding():
    root = "rounding_error"
    # nearest ten: compare rounded value using scale? 23 nearest 10 is 20. Ask if rounded value > line.
    # I'll state the rounding rule and the line. Use div? Not quite.
    # 23 with step 10: quotient 2, remainder 3, remainder < 5 so floor*10 = 20.
    # Keep it as cmp of a pre-explained pair that still requires the rule in the question
    # and the interpreter uses cmp on the two numbers that ARE the decision after we encode the rounded result as a fact the question also states.
    # That leaks. Skip fake rounding. Use integer "nearest lower ten" as floor via div.
    specs = [
        ("ten", "The value is {n}. The step is {denom}. The lower step count is the integer quotient. Is that count greater than {line}?", ((23, 10, 2), (23, 10, 1))),
        ("five", "The value is {n}. The step is {denom}. The lower step count is the integer quotient. Is that count greater than {line}?", ((17, 5, 3), (17, 5, 2))),
        ("dozen", "The value is {n}. The step is {denom}. The lower step count is the integer quotient. Is that count greater than {line}?", ((40, 12, 3), (40, 12, 2))),
        ("hour", "The value is {n} minutes. The step is {denom} minutes. The lower step count is the integer quotient. Is that count greater than {line}?", ((130, 60, 2), (130, 60, 1))),
    ]
    out = []
    for name, template, triples in specs:
        for j, (n, denom, line) in enumerate(triples):
            question = template.format(n=n, denom=denom, line=line)
            out.append(div_case(f"r3-round-{name}-{j}", root, f"round-{name}", "software", question, "yes", "no", n, denom, line, "gt", flip_options=j == 1))
    return out


def _index():
    root = "off_by_one_error"
    specs = [
        ("idx", "The index is {a}. The length is {b}. Policy: the index is inside when it is less than the length. Is the index inside?", "inside", "outside", "lt", ((4, 5), (5, 5))),
        ("page", "The page number is {a}. The last page is {b}. Policy: the page exists when the number is less than or equal to the last page. Does it exist?", "exists", "missing", "le", ((3, 3), (4, 3))),
        ("seat", "The seat number is {a}. Seats run through {b}. Policy: the seat exists when the number is less than or equal to the last seat. Does it exist?", "exists", "missing", "le", ((8, 8), (9, 8))),
        ("row", "The row index is {a}. Row count is {b}. Policy: the row is inside when the index is less than the count. Is it inside?", "inside", "outside", "lt", ((0, 4), (4, 4))),
        ("slot", "The slot is {a}. Slot count is {b}. Policy: the slot is inside when it is less than the count. Is it inside?", "inside", "outside", "lt", ((2, 3), (3, 3))),
        ("day", "The day number is {a}. Days in the month are {b}. Policy: the day exists when the number is less than or equal to the days. Does it exist?", "exists", "missing", "le", ((28, 28), (31, 28))),
    ]
    out = []
    for name, template, yes, no, rel, pairs in specs:
        for j, (a, b) in enumerate(pairs):
            out.append(cmp_case(f"r3-idx-{name}-{j}", root, f"idx-{name}", "software", template.format(a=a, b=b), yes, no, a, b, rel, flip_options=j == 1))
    return out
