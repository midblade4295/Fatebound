extends SceneTree
const Arena=preload("res://scripts/game/arena_local.gd")
var errors:Array=[]
var keyfields:=["hp","downUntil","focus","spell","ult","rollAt","moveAt","tower","damage","absorbed","kos","triples","rolls","paidRolls","focusSpent","spellAt","rallyAt","ralliesLeft","streak","hot","lastFaces","giftDamage","storedDamage","shieldSlots"]
func approx_equal(a:Variant,b:Variant)->bool:
    if (a is float or a is int) and (b is float or b is int):return absf(float(a)-float(b))<0.00001
    if a is Dictionary and b is Dictionary:
        if a.size()!=b.size():return false
        for k in a:
            if not b.has(k) or not approx_equal(a[k],b[k]):return false
        return true
    if a is Array and b is Array:
        if a.size()!=b.size():return false
        for i in a.size():
            if not approx_equal(a[i],b[i]):return false
        return true
    return a==b
func verify_state(actual:Dictionary,expected:Dictionary,label:String)->void:
    for i in actual.heroes.size():
        for key in keyfields:
            if not approx_equal(actual.heroes[i].get(key),expected.heroes[i].get(key)):
                errors.append({"case":label,"hero":i,"key":key,"got":actual.heroes[i].get(key),"want":expected.heroes[i].get(key)})
                if errors.size()>12:return
    for key in ["towers","score"]:
        if not approx_equal(actual[key],expected[key]):errors.append({"case":label,"key":key,"got":actual[key],"want":expected[key]})
func _init()->void:
    var oracle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/arena-oracle.json"))
    for item in oracle.cases:
        var e=Arena.new();e.init_match("oracle",oracle.players,100000,12345)
        e.forced_faces=item.faces
        var result:Dictionary=e.act("test0",{"type":"roll","mult":1},100000)
        if not approx_equal(result.result,item.result):errors.append({"case":item.faces,"got":result.result,"want":item.result})
        verify_state(e.s,item,str(item.faces))
        if errors.size()>12:break
    if errors.is_empty():
        for run in oracle.runs:
            var e=Arena.new();e.init_match("run"+str(int(run.seed)),oracle.players,100000,int(run.seed))
            var t:=100250
            for expect in run.ticks:
                while t<=int(expect.at):e.tick(t);t+=250
                verify_state(e.s,expect.state,"seed%d @%d"%[int(run.seed),int(expect.at)])
                if e.seed!=int(expect.seed):errors.append({"case":"rng","at":expect.at,"got":e.seed,"want":expect.seed})
                if errors.size()>12:break
            if errors.size()>12:break
    print("ARENA_PARITY ",JSON.stringify({"cases":oracle.cases.size(),"runs":oracle.runs.size(),"errors":errors}))
    FileAccess.open("res://reports/full-port/arena-parity.json",FileAccess.WRITE).store_string(JSON.stringify({"cases":oracle.cases.size(),"runs":oracle.runs.size(),"errors":errors},"  "))
    quit(0 if errors.is_empty() else 1)
