"""Evaluate a case rule from facts alone.

The teacher claim is not an input. Unknown rules raise.
"""

from __future__ import annotations

_CMP = {
    "lt": lambda left, right: left < right,
    "le": lambda left, right: left <= right,
    "gt": lambda left, right: left > right,
    "ge": lambda left, right: left >= right,
    "eq": lambda left, right: left == right,
    "ne": lambda left, right: left != right,
}


def interpret(rule: dict, facts: dict) -> str:
    op = rule.get("op")
    if op == "cmp":
        ok = _CMP[rule["rel"]](facts[rule["left"]], facts[rule["right"]])
        return rule["if_true"] if ok else rule["if_false"]
    if op == "eq":
        ok = facts[rule["key"]] == rule["value"]
        return rule["if_true"] if ok else rule["if_false"]
    if op == "table":
        return str(rule["map"][str(facts[rule["key"]])])
    if op == "rank":
        present = set(facts["present"])
        for name in rule["order"]:
            if name in present:
                return str(name)
        raise ValueError("rank miss")
    if op == "edge":
        allowed = {tuple(pair) for pair in rule["allowed"]}
        ok = (facts["state"], facts["event"]) in allowed
        return rule["if_true"] if ok else rule["if_false"]
    if op == "contains":
        ok = rule["item"] in facts[rule["key"]]
        return rule["if_true"] if ok else rule["if_false"]
    if op == "monotonic":
        seq = list(facts[rule["key"]])
        ok = all(seq[index] < seq[index + 1] for index in range(len(seq) - 1))
        return rule["if_true"] if ok else rule["if_false"]
    if op == "sum_eq":
        ok = sum(facts[rule["parts"]]) == facts[rule["total"]]
        return rule["if_true"] if ok else rule["if_false"]
    if op == "reach":
        return rule["if_true"] if _reaches(facts["edges"], facts["start"], facts["goal"]) else rule["if_false"]
    if op == "cycle":
        return rule["if_true"] if _has_cycle(facts["edges"]) else rule["if_false"]
    raise ValueError(f"unknown rule {op!r}")


def _reaches(edges: list, start: str, goal: str) -> bool:
    adjacent: dict[str, list[str]] = {}
    for src, dst in edges:
        adjacent.setdefault(src, []).append(dst)
    seen: set[str] = set()
    stack = [start]
    while stack:
        node = stack.pop()
        if node in seen:
            continue
        seen.add(node)
        stack.extend(adjacent.get(node, []))
    return goal in seen


def _has_cycle(edges: list) -> bool:
    adjacent: dict[str, list[str]] = {}
    nodes: set[str] = set()
    for src, dst in edges:
        adjacent.setdefault(src, []).append(dst)
        nodes.update((src, dst))
    color = {node: 0 for node in nodes}

    def visit(node: str) -> bool:
        color[node] = 1
        for nxt in adjacent.get(node, []):
            if color[nxt] == 1 or (color[nxt] == 0 and visit(nxt)):
                return True
        color[node] = 2
        return False

    return any(color[node] == 0 and visit(node) for node in list(nodes))
