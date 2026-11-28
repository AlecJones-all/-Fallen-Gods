class_name LevelBook
extends RefCounted

## The fifteen campaign stops, in play order. Data only — no scene lookups, no side effects.
##
## Every stop routes somewhere: a built level points at its own scene, a stop still on the bench
## falls back to the shared stub (`STUB_SCENE`), so the board never has a dead card. Fill a `scene`
## in one entry at a time as levels land — nothing else has to change.

const ACT_COUNT := 5
const PER_ACT := 3
const STUB_SCENE := "res://scenes/levels/level_stub.tscn"

## Stops held back on purpose — a preview build, a story gate. Empty means every stop opens,
## which is where the board starts while all fifteen are in development.
## Locking is a runtime concern (progress, a debug jump, a test): add an index here and that
## stop closes; nothing else in the page has to change.
static var locks: Array[int] = []

const LEVELS := [
	{ "name": "焚村", "scene": "" },
	{ "name": "什一税道", "scene": "res://scenes/levels/tithe_gate_graybox.tscn" },
	{ "name": "绞架市集", "scene": "" },
	{ "name": "白洗礼拜堂", "scene": "res://scenes/levels/whitewash_chapel.tscn" },
	{ "name": "沉没大教堂", "scene": "" },
	{ "name": "根须阶梯", "scene": "" },
	{ "name": "髓林", "scene": "" },
	{ "name": "腺海", "scene": "" },
	{ "name": "线之法庭", "scene": "" },
	{ "name": "白冕殿", "scene": "" },
	{ "name": "原初伤口", "scene": "" },
	{ "name": "疤之唱诗班", "scene": "" },
	{ "name": "空席", "scene": "" },
	{ "name": "梦的边际", "scene": "" },
	{ "name": "心核", "scene": "" },
]


static func count() -> int:
	return LEVELS.size()


static func at(index: int) -> Dictionary:
	if index < 0 or index >= LEVELS.size():
		return {}
	return LEVELS[index]


static func name_of(index: int) -> String:
	return String(at(index).get("name", ""))


## Where this stop leads. Never empty — an unbuilt level gets the shared stub page.
static func scene_of(index: int) -> String:
	var scene := String(at(index).get("scene", ""))
	return scene if not scene.is_empty() else STUB_SCENE


## True once the level has a scene of its own.
static func built(index: int) -> bool:
	return not String(at(index).get("scene", "")).is_empty()


## Levels are grouped three to an act, so the board can lay one act per row.
static func act_of(index: int) -> int:
	return floori(index / float(PER_ACT))


static func locked(index: int) -> bool:
	return locks.has(index)


## The first stop that opens — the page starts the cursor here rather than on stop one.
static func first_open() -> int:
	for index in LEVELS.size():
		if not locked(index):
			return index
	return 0
