extends "res://scripts/main.gd"
const Content=preload("res://scripts/game/content.gd")
const Store=preload("res://scripts/game/progress_store.gd")
const Progress=preload("res://scripts/game/progression.gd")
const GameApi=preload("res://scripts/game/game_api.gd")
const RaidGame=preload("res://scripts/game/raid.gd")
const Factory=preload("res://scripts/game/hero_factory.gd")
const Trainer=preload("res://scripts/game/training.gd")
const LegacyImport=preload("res://scripts/game/legacy_import.gd")
const Pages=preload("res://scripts/ui/pages.gd")
var save_store
var progression
var pages
var trainer
var coach:PanelContainer
var body:VBoxContainer
var scroller:ScrollContainer
var wallet:Label
var message_label:Label
var detail_label:Label
var chests_button:Button
var profile_in_flight:=false
var autoload_network:=true
var pending_scene_clock:=0
var qte_busy:=false
var qte_overlay:Control
var qte_hits:=0
var qte_beat:=0
var qte_at:=0
var qte_button:Button
var qte_status:Label
var qte_progress:ProgressBar
var qte_epoch:=0
var raid_parry_button:Button
var _last_frame_tick:=0
var training_temp_notice:Label
var page_history:Array[String]=[]
var _save_path_override:=""
var level_pause_at:=0
var last_wallet_paint:=0
var roll_held:=false
var auto_running:=false
var suppress_release_roll:=false
var auto_generation:=0
var active_p:
    get:return api.current_progress() if api!=null else progression
var d:Dictionary:
    get:return active_p.d
func _ready()->void:
    save_store=Store.new(_save_path_override if not _save_path_override.is_empty() else "user://fatebound-save.json")
    progression=Progress.new(save_store);progression.boot()
    api=GameApi.new();api.configure(progression);add_child(api)
    audio=Audio.new();add_child(audio)
    audio.set_levels(progression.d.native.settings)
    pages=Pages.new();pages.app=self
    trainer=Trainer.new()
    poll_timer=Timer.new();poll_timer.wait_time=0.75;poll_timer.timeout.connect(_poll);add_child(poll_timer)
    get_tree().auto_accept_quit=false
    resized.connect(_safe_area)
    save_store.committed.connect(_wallet_refresh)
    get_window().focus_exited.connect(func():api.checkpoint())
    _show_home()
    if save_store.writable and progression.d.get("war") is Dictionary and not progression.d.native.get("session") is Dictionary:
        LegacyImport.convert(progression)
    if save_store.writable and progression.d.native.get("session") is Dictionary:
        var local:Dictionary=api.restore_local()
        if local.get("ok",false):_accept(local);poll_timer.start()
    elif autoload_network and not api.token.is_empty():_recover_online.call_deferred()
func _notification(what:int)->void:
    if what==NOTIFICATION_APPLICATION_PAUSED and api!=null:
        _stop_auto_roll();audio.stop();api.checkpoint()
    if what==NOTIFICATION_WM_GO_BACK_REQUEST:
        if qte_busy:return
        if is_instance_valid(modal):modal.queue_free();modal=null
        elif trainer!=null and trainer.active:trainer.finish(false)
        elif screen=="battle":
            if api.local_kind=="raid":_confirm_leave_raid()
            else:_notice("Finish this battle before leaving.")
        elif screen=="queue":_cancel_queue()
        elif screen not in ["home","result"]:_go("home")
func _process(delta:float)->void:
    super._process(delta)
    if Time.get_ticks_msec()-last_wallet_paint>=1000:
        last_wallet_paint=Time.get_ticks_msec()
        _wallet_refresh()
        if pages!=null and trainer!=null and not trainer.active and not busy and not qte_busy and active_p.d.get("levelReward") is Dictionary and not is_instance_valid(modal) and screen!="queue":
            if api.local_kind=="raid":pause_for_level_reward()
            pages.level_reward()
    if qte_busy and is_instance_valid(qte_progress):
        var elapsed:=Time.get_ticks_msec()-qte_at
        qte_progress.value=clampf(float(elapsed)/1000*100,0,100)
        if is_instance_valid(qte_button):
            var target:=elapsed>=520 and elapsed<=780
            qte_button.modulate=Color("#85ffe0") if target else Color.WHITE
    if screen=="battle" and api!=null and api.is_local() and api.local_kind=="raid" and Time.get_ticks_msec()-_last_frame_tick>=100:
        _last_frame_tick=Time.get_ticks_msec()
        # The local raid telegraph needs a finer presentation tick, not more network traffic.
        api._advance_local()
        if api.local_engine.s.ended:_accept(api._local_state())
        elif is_instance_valid(raid_parry_button):
            var run:Dictionary=api.local_engine.run
            raid_parry_button.disabled=int(run.telegraphUntil)<=active_p.now() or bool(run.parryHit)
            raid_parry_button.text="PARRY NOW" if not raid_parry_button.disabled else ("PARRIED" if run.parryHit and int(run.telegraphUntil)>0 else "PARRY · WAIT FOR WIND-UP")
func _show_home()->void:
    if pages==null:return
    if api.is_local() and api.local_engine.s.ended and api.local_kind!="training":api.leave_local()
    if api.is_local() and not api.local_engine.s.ended and api.local_kind!="training":
        _accept(api._local_state());return
    busy=false;joining=false;poll_timer.stop()
    pages.show("home")
func _shell(title:String,tab:String="home",navigation:=true)->VBoxContainer:
    _new_screen(tab)
    coach=null;message_label=null;detail_label=null;chests_button=null;raid_parry_button=null
    var header:=_row(page)
    header.add_child(_label(title,24,Color("#f3d794")))
    if tab!="home":
        var back:=_button("BACK",40);back.custom_minimum_size.x=72;back.size_flags_horizontal=Control.SIZE_FILL
        back.pressed.connect(func():_go("home"));header.add_child(back)
    wallet=_label("",12,Color("#acdcd6"),false);wallet.custom_minimum_size.y=35;page.add_child(wallet)
    _wallet_refresh()
    scroller=ScrollContainer.new();scroller.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroller.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
    scroller.follow_focus=true;page.add_child(scroller)
    body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",9);scroller.add_child(body)
    message_label=_label("",11,Color("#ffe8a9"),true);message_label.custom_minimum_size.y=20;page.add_child(message_label)
    if not save_store.writable:message_label.text=save_store.last_error
    if trainer!=null and trainer.active:
        training_temp_notice=_label("TRAINING SAVE · Your real resources are unchanged",10,Color("#efba8d"),true);page.add_child(training_temp_notice)
    if navigation:
        var nav:=_row(page)
        for spec in [["shop","SHOP"],["hero","HERO"],["home","HOME"],["guild","GUILD"],["friends","FRIENDS"]]:
            var b:=_button(spec[1],48);b.add_theme_font_size_override("font_size",11);b.name="nav_"+spec[0]
            if spec[0]==tab:b.add_theme_stylebox_override("normal",_style(Color("#1d625d"),Color("#80d9c5")))
            b.pressed.connect(_go.bind(spec[0]));nav.add_child(b)
    rebuild_coach.call_deferred()
    return body
func _wallet_refresh()->void:
    if not is_instance_valid(wallet) or api==null:return
    var p=active_p
    wallet.text="LEVEL %d · %s / %s XP\nGold %s · Fate %s · Tokens %s · Season %s"%[int(p.d.level),_compact(int(p.d.xp)),_compact(Content.xp_need(int(p.d.level))),_compact(int(p.d.gold)),_compact(p.fate()),_compact(int(p.d.tokens)),_compact(int(p.d.season.pts))]
func card(parent:Node,title:String,text:="")->VBoxContainer:
    var panel:=PanelContainer.new();panel.add_theme_stylebox_override("panel",_style(Color("#102630"),Color("#685e42"),12));parent.add_child(panel)
    var box:=VBoxContainer.new();box.add_theme_constant_override("separation",7);panel.add_child(box)
    if not title.is_empty():box.add_child(_label(title,17,Color("#f0d79a"),true))
    if not text.is_empty():box.add_child(_label(text,12,Color("#bfd0cf"),true))
    return box
func action_button(parent:Node,text:String,callback:Callable,enabled:=true,key:="")->Button:
    var b:=_button(text,44);b.disabled=not enabled;b.pressed.connect(callback)
    if not key.is_empty():b.name=key;b.set_meta("action_key",key)
    parent.add_child(b);return b
func portrait(parent:Node,ci:int,wi:int,height:=160):
    var field=Field.new();field.preview=true;field.front_portrait=screen=="hero";field.preview_char=ci;field.preview_weapon=wi;field.custom_minimum_size.y=height;parent.add_child(field);return field
func flash_message(text:String)->void:
    if is_instance_valid(message_label):message_label.text=text
    elif is_instance_valid(status):_notice(text)
func mutate(work:Callable,success:String,refresh:=true)->bool:
    var okay:bool=bool(work.call())
    if not okay:flash_message(active_p.store.last_error if not active_p.store.last_error.is_empty() else "Not available: check the requirement or balance.");return false
    audio.play("confirm")
    if refresh and screen!="battle":
        var position:=scroller.scroll_vertical if is_instance_valid(scroller) else 0
        var current:=screen;pages.show(current)
        if is_instance_valid(scroller):scroller.set_deferred("scroll_vertical",position)
    _wallet_refresh()
    flash_message(success)
    return true
func _go(tab:String)->void:
    if qte_busy:return
    if screen=="guild":active_p.store.commit()
    if screen in ["battle","queue"] and not (trainer!=null and trainer.active):
        _notice("Complete your active match first.");return
    if screen=="result" and not pages.result_claimed:return
    if tab in ["shop","hero","home","guild","friends","settings","season","quests","stats","prepare","raid","chests","live_guild"]:
        pages.show(tab)
        if trainer!=null and trainer.active:trainer.notify(tab)
func _recover_online()->void:
    if api.is_local() or profile_in_flight:return
    profile_in_flight=true
    var profile:Dictionary=await api.profile()
    if profile.get("ok",false):
        if profile.get("active") is Dictionary and not screen in ["battle","queue"]:
            var state:Dictionary=await api.state(true)
            if state.get("ok",false):_accept(state);poll_timer.start()
        elif screen=="home":
            await api.sync_receipts();_wallet_refresh()
    profile_in_flight=false
func start_online()->void:
    if trainer.active:return
    selected_char=int(d.char);selected_weapon=int(d.weapon);selected_loadout=d.adventure.loadout.duplicate()
    if joining or api.is_local():return
    joining=true;flash_message("Connecting to matchmaking…")
    var generation:=epoch
    var answer:Dictionary=await api.ensure_session(str(d.native.name))
    if generation!=epoch:joining=false;return
    if not answer.get("ok",false):joining=false;flash_message(str(answer.get("error","Connection failed")));return
    var state:Dictionary=await api.queue(selected_char,selected_weapon,selected_loadout)
    joining=false
    if generation!=epoch:return
    if not state.get("ok",false):flash_message(str(state.get("error","Queue failed")));return
    _show_queue();_accept(state);poll_timer.start()
func start_local(kind:String,options:Dictionary={})->void:
    if trainer.active:return
    if not save_store.writable:flash_message(save_store.last_error);return
    selected_char=int(d.char);selected_weapon=int(d.weapon);selected_loadout=d.adventure.loadout.duplicate()
    var response:Dictionary=api.start_local(kind,options)
    if not response.get("ok",false):flash_message(str(response.get("error","Could not start session")));return
    latest={};current_match_id="";_accept(response);poll_timer.start()
func _accept(state:Dictionary)->void:
    super._accept(state)
    if state.get("local",false) and not str(state.get("saveError","")).is_empty():_notice(str(state.saveError))
func _show_battle()->void:
    wallet=null;message_label=null;coach=null
    super._show_battle()
    apply_settings()
    roll_button.button_down.connect(_start_hold_roll)
    detail_label=_label("",11,Color("#abddd0"),true);detail_label.custom_minimum_size.y=16;page.add_child(detail_label);page.move_child(detail_label,3)
    if api.is_local() and api.local_kind=="raid":
        tower_title.text="RAID · "+str(api.local_engine.boss.name)
        tower_title.disabled=true
        all_in.get_parent().visible=false
        mult_select.visible=false;rally_button.visible=false
        for b in spell_buttons:b.visible=false
        var row=spell_buttons[0].get_parent()
        raid_parry_button=action_button(row,"PARRY · WAIT FOR WIND-UP",func():_do_action("parry"),false,"parry")
        var ult=action_button(row,"ULTIMATE",func():_do_action("ultimate"),true,"raid_ultimate")
        ult_button=ult
        var exit=action_button(page,"END RAID ATTEMPT",_confirm_leave_raid,true,"raid_exit")
        exit.custom_minimum_size.y=36
    if api.is_local():
        chests_button=action_button(page,"CHESTS & STORED ATTACKS",_battle_inventory,true,"battle_inventory")
        chests_button.custom_minimum_size.y=34
    mult_select.item_selected.connect(func(_i):
        if trainer.active and mult_select.get_selected_id()==2:trainer.notify("mult")
    )
    rebuild_coach()
func _update_battle(data:Dictionary,earnings:Variant={})->void:
    super._update_battle(data,earnings)
    if screen!="battle":return
    if api.is_local():
        bank.text="%d gold · %d XP · %d saved chests"%[int(d.gold),int(d.xp),d.chests.size()+int(d.rollTrack.ready)]
        if api.local_kind=="raid":
            var b:Dictionary=api.local_engine.boss;var run:Dictionary=api.local_engine.run
            var remaining:=maxi(0,int(ceil(float(int(run.staggerUntil)-active_p.now())/1000)))
            detail_label.text="Armour %d/4 · weak to %s · %s"%[int(b.armor),"CRIT" if b.weak=="C" else "SWORD",("STAGGER ×3 · %ds"%remaining) if remaining>0 else "3% damage to stagger"]
            tower_title.text=str(b.name)
        elif data.get("excitement") is Dictionary:
            var ex:Dictionary=data.excitement
            detail_label.text="Momentum %d/100 · %s"%[int(ex.momentum[0]),("+10% SURGE" if active_p.now()<int(ex.surgeUntil[0]) else "Own towers, protect allies")]
            if int(_me().get("streak",0))>0:detail_label.text+=" · Combo %d/10"%int(_me().streak)
            if _me().get("hot",false):detail_label.text+=" · Guaranteed match next roll"
            if ex.get("order") is Dictionary:
                var order:Dictionary=ex.order
                detail_label.text+="\nOrder: %s %d/%d"%[str(order.type).capitalize(),int(order.progress/1000) if order.type=="hold" else int(order.progress),int(order.need/1000) if order.type=="hold" else int(order.need)]
        else:detail_label.text="PRACTICE · No rewards, rank or mastery changes"
    else:
        var me:=_me();var uid:=str(int(me.get("char",0)));var scores:Dictionary=d.adventure.mastery.get(uid,{})
        detail_label.text="ONLINE · Equalized level 10 · %s %s"%[active_p.mastery().title,Content.character(int(me.get("char",0))).n]
    _paint_controls()
func _paint_controls()->void:
    super._paint_controls()
    if api==null or not api.is_local() or screen!="battle" or not is_instance_valid(roll_button):return
    var h:=_me();var now:=_server_now();var ko:=int(h.get("hp",0))<=0;var locked:bool=busy or qte_busy or ko or not api.local_error.is_empty()
    if api.local_kind=="raid":
        roll_button.disabled=locked or now<float(h.get("rollAt",0))
        roll_button.text="KO" if ko else ("ROLLING…" if busy or qte_busy else "ROLL")
        ult_button.disabled=locked or int(h.get("ult",0))<100
        ult_button.text="ULTIMATE %d%%"%int(h.get("ult",0))
        focus.text="HP %d/%d · Attempt %d/3 · FREE ROLLS"%[int(h.get("hp",0)),int(h.get("maxHp",1)),int(api.local_engine.boss.attempts)]
        if is_instance_valid(raid_parry_button):
            var r:Dictionary=api.local_engine.run;raid_parry_button.disabled=ko or int(r.telegraphUntil)<=active_p.now() or bool(r.parryHit)
        status.text="SOLO RAID · Simulated company support"
    else:
        if api.local_kind in ["campaign","training"]:
            if not api.local_engine.s.get("pendingGift",[]).is_empty():roll_button.disabled=true
        status.text="TRAINING · Temporary resources" if trainer.active else ("SOLO COMPANY · Your equipment and progression apply" if api.local_kind=="campaign" else "PRACTICE · Equalized level 10 · No rewards")
    if qte_busy or d.get("levelReward") is Dictionary:roll_button.disabled=true
    if not api.local_kind=="raid":
        var held:=int(h.get("focus",0))
        for i in 4:mult_select.set_item_disabled(i,held<[0,2,4,6][i])
        all_in.disabled=all_in.disabled or held<3
        if held<[0,2,4,6][mult_select.selected]:mult_select.select(0)
func _do_action(kind:String,payload:={}) -> void:
    if qte_busy and kind not in ["parry"]:return
    if active_p.d.get("levelReward") is Dictionary and kind=="roll":pages.level_reward();return
    await super._do_action(kind,payload)
    if not api.last_action_answer.get("ok",false):return
    if api.is_local() and api.local_kind=="raid" and is_instance_valid(roll_result):
        var result:Dictionary=api.last_action_answer.get("result",{});var ef:Dictionary=result.get("effects",{})
        var bits:Array[String]=[]
        if int(result.get("dealt",0))>0:bits.append("%d damage"%int(result.dealt))
        if int(ef.get("armorBroken",0))>0:bits.append("-%d armour"%int(ef.armorBroken))
        if int(ef.get("hpGained",0))>0:bits.append("+%d HP"%int(ef.hpGained))
        if int(ef.get("goldAdded",0))>0:bits.append("+%d tier/milestone gold"%int(ef.goldAdded))
        if not bits.is_empty():roll_result.text=" · ".join(bits)
    if trainer.active:trainer.notify(kind)
    if api.is_local() and api.local_kind in ["campaign","training"] and not api.local_engine.s.get("pendingGift",[]).is_empty():show_gift_choices()
    if screen=="battle":_update_battle(latest,latest_state.get("earnings",{}))
    if active_p.d.get("levelReward") is Dictionary and not trainer.active and not is_instance_valid(modal):
        if api.local_kind=="raid":pause_for_level_reward()
        pages.level_reward()
func _roll()->void:
    if suppress_release_roll:
        suppress_release_roll=false
        return
    if not is_instance_valid(roll_button) or roll_button.disabled:return
    if d.get("levelReward") is Dictionary:pages.level_reward();return
    if not api.is_local() or api.local_kind=="practice":await super._roll();return
    var engine=api.local_engine
    var generation:=epoch
    var faces:Array=engine.forced_faces.duplicate() if not engine.forced_faces.is_empty() else engine.faces()
    var h:=_me()
    if h.get("hot",false):faces[2]=faces[0]
    if int(h.get("forcedCrits",0))>0:
        faces[2]="C"
        if faces[0]!="C" and faces[1]!="C":faces[1]="C"
    engine.forced_faces=faces.duplicate()
    var qte:=1.0
    var resolved:Dictionary=Content.resolve(faces)
    if resolved.action=="C":
        var target:=false
        for foe in latest.heroes:
            if int(foe.side)!=int(h.side) and int(foe.tower)==int(h.tower) and int(foe.hp)>0:target=true;break
        if target:qte=await _critical_sequence()
    if generation!=epoch:return
    if not trainer.active:engine.forced_faces=faces.duplicate()
    dice.start_roll();audio.play("roll")
    await _do_action("roll",{"mult":mult_select.get_selected_id(),"allIn":all_in.button_pressed,"qte":qte})
    if not trainer.active and api.local_engine!=null:api.local_engine.forced_faces=[]
    if screen=="battle" and is_instance_valid(all_in):all_in.set_pressed_no_signal(false);all_in.text="ALL-IN OFF"
func _critical_sequence()->float:
    _stop_auto_roll()
    qte_busy=true;qte_hits=0;qte_epoch=epoch
    var box:=_popup("CRITICAL STRIKE")
    qte_overlay=modal
    box.add_child(_label("Three timing strikes. Tap in the bright window to increase this critical attack. Missing never cancels the roll.",14,Color("#e9d3a7"),true))
    qte_status=_label("Strike 1 / 3",22,Color("#b9fff0"));box.add_child(qte_status)
    qte_progress=ProgressBar.new();qte_progress.max_value=100;qte_progress.show_percentage=false;qte_progress.custom_minimum_size.y=24;box.add_child(qte_progress)
    qte_button=action_button(box,"STRIKE",func():
        if qte_button.disabled:return
        var time:=Time.get_ticks_msec()-qte_at
        if time>=520 and time<=780:qte_hits+=1;audio.play("crit")
        else:audio.play("miss")
        qte_button.disabled=true
    ,true,"qte_strike")
    qte_button.custom_minimum_size.y=80
    # No dismiss handler may orphan a paid critical sequence.
    for child in box.get_children():
        if child is HBoxContainer:
            for button in child.get_children():
                if button is Button:button.disabled=true
    for beat in 3:
        if qte_epoch!=epoch:break
        qte_beat=beat;qte_at=Time.get_ticks_msec();qte_button.disabled=false;qte_status.text="Strike %d / 3 · %d accurate"%[beat+1,qte_hits]
        await get_tree().create_timer(1.10).timeout
        if not is_instance_valid(qte_button):break
    qte_busy=false
    if is_instance_valid(qte_overlay):qte_overlay.queue_free()
    if modal==qte_overlay:modal=null
    qte_overlay=null
    return 1.0+0.35*qte_hits
func _tower_map()->void:
    _stop_auto_roll()
    super._tower_map()
    if trainer.active:trainer.notify("map")
func _more()->void:
    _stop_auto_roll()
    if api.is_local():
        var box:=_popup("BATTLE MENU")
        action_button(box,"Sound & effects",func():pages.sound_panel(_popup("SOUND & EFFECTS")))
        action_button(box,"Stored attacks & chests",_battle_inventory)
        if api.local_kind in ["campaign","training"]:
            for spell in SPELLS:action_button(box,"CAST "+SPELL_NAMES[spell],_cast_from_more.bind(spell),int(_me().get("spell",0))>0)
            if str(latest.get("phase","")) in ["finale","overtime"]:action_button(box,"Claim final-push Fate +3",func():_do_action("rally_energy"))
        if api.local_kind=="raid":action_button(box,"End raid attempt",_confirm_leave_raid)
        elif api.local_kind=="practice":action_button(box,"Exit practice · no rewards",_exit_practice)
        if not api.local_error.is_empty():action_button(box,"RETRY SAVING",_retry_save)
        var rival:Variant=_me().get("rival")
        if rival!=null and api.local_kind in ["campaign","training"]:
            var enemy:Dictionary=api.local_engine.hero(str(rival))
            if not enemy.is_empty():action_button(box,"HUNT RIVAL · "+str(enemy.name),_move_to.bind(int(enemy.tower)))
        if trainer.active:action_button(box,"Exit training safely",func():trainer.finish(false))
    else:
        super._more()
func _cast_from_more(spell:String)->void:
    if is_instance_valid(modal):modal.queue_free();modal=null
    await _cast(spell)
func _exit_practice()->void:
    if api.local_kind!="practice":return
    api.local_engine.finish(active_p.now());await api.claim(str(api.local_engine.s.id));api.leave_local();poll_timer.stop();_show_home()
func _confirm_leave_raid()->void:
    var box:=_popup("END THIS ATTEMPT?")
    box.add_child(_label("Damage and tier rewards are saved. This attempt remains used for today.",14,Color("#e9d3a7"),true))
    action_button(box,"END ATTEMPT",func():
        if is_instance_valid(modal):modal.queue_free();modal=null
        _do_action("leave")
    )
func _battle_inventory()->void:
    var box:=_popup("SAVED REWARDS")
    pages.chests_content(box,true)
    action_button(box,"Use a stored attack",show_stored_attacks)
func show_stored_attacks()->void:
    var box:=_popup("STORED ATTACKS")
    var items:Array=active_p.gift_box().items
    if items.is_empty():box.add_child(_label("No stored attacks yet.",14,Color("#c7d5d6"),true))
    for i in items.size():action_button(box,"USE %d DAMAGE"%int(items[i]),_use_stored.bind(i),true,"stored_"+str(i))
    if trainer.active:trainer.notify("stored_menu")
func _use_stored(index:int)->void:
    if is_instance_valid(modal):modal.queue_free();modal=null
    await _do_action("stored",{"index":index})
func show_gift_choices()->void:
    _stop_auto_roll()
    if api.local_engine==null:return
    var choices:Array=api.local_engine.s.get("pendingGift",[])
    if choices.is_empty():return
    var box:=_popup("CHOOSE A GUILDMATE")
    box.add_child(_label("The displayed amount already includes your roll multiplier. Choose one card. Simulated solo company gifts stay saved.",13,Color("#d8dcce"),true))
    for i in choices.size():
        var c:Dictionary=choices[i]
        var amount:=int(float(c.mult)*({"gold":30,"energy":3,"attack":500}[str(c.kind)]))
        var card_box:=card(box,("★ BONUS · " if c.get("bonus",false) else "")+str(c.name),"+%d %s"%[amount,{"gold":"gold","energy":"stored rolls","attack":"stored damage"}[str(c.kind)]])
        action_button(card_box,"SEND THIS GIFT",_choose_gift.bind(i),true,"gift_choice_"+str(i))
func _choose_gift(index:int)->void:
    if trainer.active and trainer.index==13 and not api.local_engine.s.pendingGift[index].get("bonus",false):flash_message("Choose the bonus card for this lesson.");return
    if is_instance_valid(modal):modal.queue_free();modal=null
    await _do_action("gift_choice",{"index":index})
func _show_result(state:Dictionary)->void:
    _stop_auto_roll()
    poll_timer.stop();busy=false
    if is_instance_valid(qte_overlay):qte_overlay.queue_free()
    qte_busy=false
    pages.show_result(state)
func begin_training()->void:
    if trainer.active:return
    if api.is_local():flash_message("Finish your current session before training.");return
    if not trainer.begin(self,progression):flash_message("Training could not start. Your save is unchanged.")
func training_show_target(target:String)->void:
    if target in ["battle","map"]:
        var state:Dictionary=api._local_state()
        latest=state.match;latest_state=state;received_ms=Time.get_ticks_msec();current_match_id=str(latest.id)
        _show_battle();_update_battle(latest,{})
        if target=="map":super._tower_map()
    else:pages.show(target)
func rebuild_coach()->void:
    if trainer==null or not trainer.active:return
    if is_instance_valid(coach):
        if coach.get_parent()!=null:coach.get_parent().remove_child(coach)
        coach.queue_free()
    coach=PanelContainer.new();coach.add_theme_stylebox_override("panel",_style(Color("#28362e"),Color("#ead596")))
    var box:=VBoxContainer.new();coach.add_child(box)
    var lesson:Dictionary=trainer.lesson()
    box.add_child(_label("TRAINING %d/33 · %s"%[trainer.index+1,lesson.title],13,Color("#ffe3a1"),true))
    var controls:=_row(box)
    action_button(controls,"INSTRUCTIONS",func():
        var detail:=_popup(str(lesson.title));detail.add_child(_label(str(lesson.text),16,Color("#dfe9e4"),true))
    ,true,"coach_instructions")
    if not lesson.has("action"):action_button(controls,"FINISH" if lesson.get("finish",false) else "GOT IT",func():trainer.next(),true,"coach_next")
    var expected:=str(lesson.get("action",""))
    if expected=="home":action_button(controls,"HOME",func():_go("home"),true,"coach_home")
    elif expected=="giftOpen":action_button(controls,"STORED ATTACKS",show_stored_attacks,true,"coach_stored")
    elif expected=="map":action_button(controls,"MAP",_tower_map,true,"coach_map")
    action_button(controls,"EXIT",func():trainer.finish(false),true,"coach_exit")
    page.add_child(coach);page.move_child(coach,0)
    if lesson.has("mult") and screen=="battle" and is_instance_valid(mult_select):mult_select.select(int(lesson.mult)-1)

func apply_settings()->void:
    if audio!=null:audio.set_levels(active_p.d.native.settings)
    if is_instance_valid(board):board.reduce_motion=bool(active_p.d.native.settings.get("reduceMotion",false))
    if is_instance_valid(dice):dice.reduce_motion=bool(active_p.d.native.settings.get("reduceMotion",false))
func resume_imported_war()->void:
    var converted:Dictionary=LegacyImport.convert(progression)
    if not converted.get("ok",false):flash_message(str(converted.get("error","Legacy battle retained without conversion.")))
    if d.native.get("session") is Dictionary:
        var response:Dictionary=api.restore_local()
        if response.get("ok",false):_accept(response);poll_timer.start()
func pause_for_level_reward()->void:
    if api.pause_local:return
    api.pause_local=true;api.paused_wall_at=active_p.now()
    api.checkpoint()
func resume_level_pause()->void:
    if not api.pause_local:return
    var elapsed:int=maxi(0,active_p.now()-int(api.paused_wall_at))
    api.pause_local=false;api.paused_wall_at=0;level_pause_at=0
    if api.local_kind!="raid" or api.local_engine==null:return
    var e=api.local_engine
    for key in ["startAt","endAt","now"]:e.s[key]=int(e.s[key])+elapsed
    for key in ["until","nextStrike","telegraphUntil","staggerUntil","parryUntil","botAt"]:
        if int(e.run.get(key,0))>0:e.run[key]=int(e.run[key])+elapsed
    for h in e.s.heroes:
        for key in ["downUntil","rollAt","buffUntil"]:
            if int(h.get(key,0))>0:h[key]=int(h[key])+elapsed
    e.sync_boss();api.checkpoint()
func _compact(value:int)->String:
    if value>=1000000000:return "%.1fB"%(float(value)/1000000000)
    if value>=1000000:return "%.1fM"%(float(value)/1000000)
    if value>=1000:return "%.1fK"%(float(value)/1000)
    return str(value)
func _retry_save()->void:
    api.local_error=""
    if api.checkpoint():
        if is_instance_valid(modal):modal.queue_free();modal=null
        _notice("Progress saved. You can continue.")
    else:_notice(api.local_error)
func _events(data:Dictionary)->void:
    var previous_seq:=event_seq
    super._events(data)
    for event in data.get("events",[]):
        if int(event.get("seq",0))<=previous_seq or float(data.get("now",0))-float(event.get("at",0))>1800:continue
        if int(event.get("tower",_me().get("tower",0)))!=int(_me().get("tower",0)):continue
        var actor:Dictionary={}
        for h in data.heroes:
            if str(h.id)==str(event.get("actor","")):actor=h;break
        var quiet:=str(event.get("actor",""))!=str(api.player_id)
        var kind:=str(event.get("type",""))
        if kind=="roll":
            if int(event.get("dealt",0))>0 and not actor.is_empty():
                var weapon:int=int(actor.get("weapon",0))
                audio.play("bow" if weapon in [7,8] else ("magic" if weapon in [5,6] else ("axe" if weapon in [2,4] else "sword")),quiet)
            elif event.get("symbol",null)=="G":audio.play("coin",quiet)
            elif event.get("symbol",null)=="E":audio.play("energy",quiet)
            elif event.get("symbol",null)=="F":audio.play("gift",quiet)
        elif kind=="parry":audio.play("parry",false)
        elif kind=="ko":audio.play("ko",str(event.get("target",""))!=str(api.player_id))
        elif kind=="capture":audio.play("flip",quiet)
        elif kind=="ultimate" and not actor.is_empty():audio.play(["bulwark","shadow","rampage","meteor","volley"][clampi(int(actor.get("char",0)),0,4)],quiet)
        elif kind=="phase":audio.play("tension",false)
func _input(event:InputEvent)->void:
    if (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed) or (event is InputEventScreenTouch and not event.pressed) or (event is InputEventKey and not event.pressed and event.keycode in [KEY_SPACE,KEY_ENTER]):
        suppress_release_roll=auto_running
        _stop_auto_roll()
func _stop_auto_roll()->void:
    roll_held=false;auto_running=false;auto_generation+=1
func _start_hold_roll()->void:
    roll_held=true;suppress_release_roll=false;auto_generation+=1
    var hold_generation:=auto_generation;var scene_generation:=epoch
    await get_tree().create_timer(0.45).timeout
    if not roll_held or hold_generation!=auto_generation or scene_generation!=epoch:return
    auto_running=true
    while roll_held and hold_generation==auto_generation and scene_generation==epoch and screen=="battle":
        if qte_busy or is_instance_valid(modal) or int(_me().get("hp",0))<=0 or d.get("levelReward") is Dictionary:break
        if not busy and is_instance_valid(roll_button) and not roll_button.disabled:
            await _roll()
        await get_tree().create_timer(0.10).timeout
    if hold_generation==auto_generation:_stop_auto_roll()
