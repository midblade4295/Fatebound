extends SceneTree
# 0.31.26: a captive King works off one fish every DIGEST_EVERY seconds, so his weight (and the hands needed to lift him)
# comes down unless the feeding is kept up.
const Sim = preload("res://scripts/siege/siege_sim.gd")
func _init():
	var s = Sim.new()
	s.setup(4, 3)
	for u in s.units: u.bot = false; u.move = Vector2.ZERO
	var k: Dictionary = s.oracles[1]
	k.cakes = 7
	k.weight = mini(Sim.MAX_WEIGHT, 7 / Sim.CAKE_PER_STAGE)
	var w0: int = k.weight
	var need0 := s.lifters_needed(k)
	for i in int((Sim.DIGEST_EVERY * 2 + 1.0) / Sim.TICK): s.step(); s.drain_events()
	var ok := int(k.cakes) == 5 and int(k.weight) == 1 and s.lifters_needed(k) < need0 and w0 == 2
	print("DIGEST_PASS 7 fish -> %d after %.0f s (stage %d -> %d, lifters %d -> %d)" % [k.cakes, Sim.DIGEST_EVERY * 2 + 1, w0, k.weight, need0, s.lifters_needed(k)] if ok else "DIGEST_FAIL cakes=%d weight=%d" % [k.cakes, k.weight])
	quit(0 if ok else 1)
