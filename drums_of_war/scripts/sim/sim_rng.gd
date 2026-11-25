extends RefCounted
## Small seeded random source for the battle rules (xorshift64).
## The rules never touch the engine's global RNG, so a seed fully decides a match.

const MASK := 0x7FFFFFFFFFFFFFFF

var state: int


func _init(seed_value: int = 1) -> void:
	state = (seed_value * 0x2545F4914F6CDD1D + 0x1234567) & MASK
	if state == 0:
		state = 1
	for i in 4:
		next_u32()


func next_u32() -> int:
	var x := state
	x ^= (x << 13) & MASK
	x ^= x >> 7
	x ^= (x << 17) & MASK
	state = x & MASK
	if state == 0:
		state = 1
	return (state >> 16) & 0xFFFFFFFF


func next_f() -> float:
	return float(next_u32()) / 4294967296.0


func range_f(a: float, b: float) -> float:
	return a + (b - a) * next_f()


func range_i(a: int, b: int) -> int:
	return a + int(next_u32() % (b - a + 1))


func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := range_i(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
