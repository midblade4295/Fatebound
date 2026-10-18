extends RefCounted
# 0.31.108: what one seated player did in an online match, counted by the SERVER from its own simulation (the phone
# counts the same thing for its results screen, siege_mode.gd _title_track / _count, but only this count is paid):
# knockouts, tower/gate/King damage, healing and the 5v5's towers, camps, last hits and epic monsters from the unit's
# totals since the player took the seat (a bot held it before), the best burst from the match's events, and per class
# worn the time and what was done as it (the quests and titles, Eco.QUESTS / TITLE_GOALS). me() -> the dictionary
# Profile.apply_match takes, as the phone builds it. (0.31.169: Siege's rescues, gathering, fish, King lifts and repairs
# went with Siege; the 5v5's numbers came in, as siege_mode counts them.)
const Eco = preload("res://scripts/meta/economy.gd")
const Q_UNIT := {"kills":"kills", "gate_dmg":"gate_dmg", "healed":"healed", "towers":"towers", "camps":"camps", "lh":"lh",
	"epics":"epics"}

var uid := ""
var team := -1
var base := {}
var seen := {}
var cls_time := {}
var kills_cls := {}
var kills_seen := 0
var q := {}
var q_cls := ""
var best_multi := 0

func start(u: Dictionary) -> void:
	uid = str(u.id)
	team = int(u.team)
	for f in Q_UNIT:
		base[f] = float(u.get(f, 0.0))
		seen[f] = base[f]
	kills_seen = int(u.get("kills", 0))

func _entry(c: String) -> Dictionary:
	if not q.has(c):
		q[c] = {}
	return q[c]

func _q_add(stat: String, v: float) -> void:
	if q_cls == "":
		return
	var e := _entry(q_cls)
	e[stat] = float(e.get(stat, 0.0)) + v

func track(u: Dictionary, delta: float) -> void:
	# every server frame: the class worn, and what the unit's totals grew by, credited to it
	var cls := str(u.cls)
	if str(u.state) != "dead":
		cls_time[cls] = float(cls_time.get(cls, 0.0)) + delta
	var k := int(u.kills)
	if k > kills_seen:
		kills_cls[cls] = int(kills_cls.get(cls, 0)) + (k - kills_seen)
		kills_seen = k
	q_cls = Eco.cosmetic_class(cls, bool(u.get("up", false)))
	if q_cls != "" and str(u.state) != "dead":
		var e := _entry(q_cls)
		e["t"] = float(e.get("t", 0.0)) + delta
	for f in Q_UNIT:
		var v := float(u.get(f, 0.0))
		var dv := v - float(seen.get(f, 0.0))
		if dv > 0.0:
			_q_add(str(Q_UNIT[f]), dv)
		seen[f] = v

func on_event(e: Dictionary) -> void:
	if str(e.get("id", "")) != uid:
		return
	if str(e.get("k", "")) == "multikill":
		best_multi = maxi(best_multi, int(e.get("n", 0)))
		if q_cls != "":
			var qe := _entry(q_cls)
			qe["best_multi"] = maxi(int(qe.get("best_multi", 0)), int(e.get("n", 0)))

func me(u: Dictionary) -> Dictionary:
	var main := ""
	var best := 60.0
	for c in cls_time:
		if float(cls_time[c]) >= best:
			best = float(cls_time[c])
			main = str(c)
	var qq := {}
	for c in q:
		var e: Dictionary = q[c]
		qq[c] = {"t": float(e.get("t", 0.0)), "kills": int(e.get("kills", 0.0)),
			"gates": int(float(e.get("gate_dmg", 0.0)) / 100.0), "healed": int(e.get("healed", 0.0)),
			"best_multi": int(e.get("best_multi", 0)), "towers": int(e.get("towers", 0.0)), "camps": int(e.get("camps", 0.0)),
			"lh": int(e.get("lh", 0.0)), "epics": int(e.get("epics", 0.0))}
	var out := {"kills": int(u.get("kills", 0)) - int(base.get("kills", 0.0)),
		"gate_dmg": maxf(0.0, float(u.get("gate_dmg", 0.0)) - float(base.get("gate_dmg", 0.0))),
		"healed": maxf(0.0, float(u.get("healed", 0.0)) - float(base.get("healed", 0.0))),
		"best_multi": best_multi, "cls": str(u.cls), "cls_main": main, "kills_cls": kills_cls.duplicate(), "q": qq}
	for f in Eco.FIVE_STATS:
		out[f] = maxi(0, int(u.get(f, 0)) - int(base.get(f, 0.0)))
	return out
