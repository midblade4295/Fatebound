// Ported from godot/scripts/siege/siege_view.gd (Fatebound 0.31.222): actors -- what players wear, the Meshy bodies,
// make_body, skins, staffs, weapons (Armory Reforged), tints, the minion pool, the loading card's warm-ups, _ensure_actor,
// animation culling and sync().
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Vector4 = Fatebound.Sim.Vec4;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using Quaternion = Fatebound.Sim.Quat;
using AABB = Fatebound.Sim.Aabb;
using Material = Fatebound.GUI.GMaterial;
using Environment = Fatebound.GUI.Environment;

namespace Fatebound.Game
{
    using Eco = Fatebound.Game.Economy;
    using Stage = Fatebound.Game.AssetCache;
    using Sim = Fatebound.Sim.SiegeSim;

    public partial class SiegeView
    {
        // ---------- actors ----------
        // What the players wear (0.31.101, Kevin: "I want players to see everything the other players are wearing"): mine from
        // the profile, the other live players' from the server's "pn" (set_unit_looks); bots wear the defaults. 0.31.188 (Kevin:
        // "I only want the cosmetics to be an entire outfit"): an outfit -- the hero's body repainted and its own weapon
        // (Eco.SKINS) -- is all there is; the weapons and Forge stars per class (0.31.101-0.31.187) are gone.
        public GDict player_skins = new GDict();            // 0.31.186: hero -> the outfit I wear on him (Profile.d.skin_on)
        public GDict unit_skins = new GDict();              // 0.31.186: unit id -> the outfits that player wears (the looks' "_sk")
        public GDict _skin_cos = new GDict();               // unit id -> {"skin", "out"}: an outfit's cosmetic, made once
        public static readonly GDict NO_LOOK = new GDict();

        public void SetUnitLooks(GDict wire)
        {
            // the server's {unit id: looks} -> the outfits each other player wears
            unit_skins = new GDict();
            foreach (var uid in wire)
            {
                if (GD.Str(uid) == player_id)
                    continue;
                if (wire[uid].IsDict && GD.Str(wire[uid].D.Get("_sk", "")) != "")
                    unit_skins[GD.Str(uid)] = Var.Of(GD.Str(wire[uid]["_sk"]).Split(","));      // 0.31.186: the outfits they wear
            }
        }

        public GDict UnitCosmetic(Unit u)
        {
            // what this unit wears: the outfit on this hero (mine, or theirs online) -- made once, the same dictionary every frame
            var skin = UnitSkin(u);
            if (skin == "")
                return NO_LOOK;
            GDict c = _skin_cos.Get(u.id, new GDict()).D;
            if (c.IsEmpty() || GD.Str(c["skin"]) != skin)
            {
                c = GDict.Of("skin", skin, "out", GDict.Of("skin", skin, "lite", low_fx && u.id != player_id));
                _skin_cos[u.id] = c;
            }
            return c["out"].D;
        }

        public string UnitSkin(Unit u)
        {
            // 0.31.186: the skin this hero wears -- the one of mine (or that player's) made for him; bots wear none
            var hid = u.hid ?? "";
            if (hid == "" || !u.hero)
                return "";
            if (u.id == player_id)
            {
                var mine = GD.Str(player_skins.Get(hid, ""));
                return Eco.SKINS.Has(mine) && GD.Str(Eco.SKINS[mine]["hero"]) == hid ? mine : "";
            }
            foreach (var id in unit_skins.Get(u.id, new GArray()))
            {
                if (Eco.SKINS.Has(GD.Str(id)) && GD.Str(Eco.SKINS[GD.Str(id)]["hero"]) == hid)
                    return GD.Str(id);
            }
            return "";
        }
        public static GDict _tint_mats = new GDict();

        public static string LookKey(Unit u)
        {
            if (u.look != null)
                return GD.Str(u.look);                      // 0.31.157: a jungle monster, a LEGION skeleton
            if (u.minion && MINION_LOOKS.Has(u.mk ?? ""))
                return GD.Str(MINION_LOOKS[u.mk]);     // 0.31.159: the lane minions' own bodies
            if (u.cls == "barbarian" && u.up)
                return "berserker";
            if (u.cls == "priest" && u.up)
                return "necromancer";
            if (u.cls == "knight" && u.up)
                return "crusader";                     // 0.31.60: his own (Meshy) body
            if (u.up && Array.IndexOf(new[] { "rogue", "ranger", "mage" }, u.cls) >= 0)
                return GD.Str(GDict.Of("rogue", "assassin", "ranger", "sniper", "mage", "archmage")[u.cls]);
            return u.cls;
        }

        // ---------- Meshy characters (0.31.52, Kevin: a new Assassin model from Meshy) ----------
        // A Meshy-generated, Meshy-rigged character stands in for a KayKit one. Its bones are renamed to the KayKit names (and
        // hand slots added) so weapons, hats and the rest of the view find what they expect; its animations are the game's
        // KayKit animations baked onto its own skeleton by tools/retarget_meshy.gd (anims_<library>.res, same names), and
        // rig.json carries the fit scale and the hand-slot rests the tool worked out.
        public static readonly GDict MESHY = new GDict
        {
            { "assassin", "res://assets/meshy/assassin/" }, { "archmage", "res://assets/meshy/archmage/" }, { "crusader", "res://assets/meshy/crusader/" },
            { "berserker", "res://assets/meshy/berserker/" }, { "sniper", "res://assets/meshy/sniper/" },
            { "necromancer", "res://assets/meshy/necromancer/" }, { "worker", "res://assets/meshy/worker/" },
            { "knight", "res://assets/meshy/knight/" }, { "barbarian", "res://assets/meshy/barbarian/" }, { "rogue", "res://assets/meshy/rogue/" },
            { "ranger", "res://assets/meshy/ranger/" }, { "mage", "res://assets/meshy/mage/" }, { "priest", "res://assets/meshy/priest/" },
            // 5v5 lane minions (Kevin picked the A1 concepts: the King's levy)
            { "minion_melee", "res://assets/meshy/minion_melee/" }, { "minion_caster", "res://assets/meshy/minion_caster/" },
            { "minion_siege", "res://assets/meshy/minion_siege/" }, { "minion_super", "res://assets/meshy/minion_super/" },
            // 0.31.168: the six new 5v5 heroes
            { "golem", "res://assets/meshy/golem/" }, { "dragoon", "res://assets/meshy/dragoon/" }, { "duelist", "res://assets/meshy/duelist/" },
            { "stormcaller", "res://assets/meshy/stormcaller/" }, { "musketeer", "res://assets/meshy/musketeer/" }, { "druid", "res://assets/meshy/druid/" },
        };
        public static readonly GDict MESHY_RENAME = new GDict
        {
            { "Hips", "hips" }, { "Spine02", "spine" }, { "Spine", "chest" }, { "Head", "head" },
            { "LeftArm", "upperarm.l" }, { "LeftForeArm", "lowerarm.l" }, { "LeftHand", "wrist.l" },
            { "RightArm", "upperarm.r" }, { "RightForeArm", "lowerarm.r" }, { "RightHand", "wrist.r" },
            { "LeftUpLeg", "upperleg.l" }, { "LeftLeg", "lowerleg.l" }, { "LeftFoot", "foot.l" }, { "LeftToeBase", "toes.l" },
            { "RightUpLeg", "upperleg.r" }, { "RightLeg", "lowerleg.r" }, { "RightFoot", "foot.r" }, { "RightToeBase", "toes.r" },
        };
        public static GDict _meshy_libs = new GDict();
        public static GDict _meshy_rig = new GDict();

        public static GDict MeshyRig(string name)
        {
            if (!_meshy_rig.Has(name))
            {
                var f = FileAccess.Open(GD.Str(MESHY[name]) + "rig.json", FileAccess.READ);
                _meshy_rig[name] = f != null ? JSON.ParseString(f.GetAsText()) : new GDict();
            }
            return _meshy_rig[name].D;
        }

        public static Transform3D _Xf(GArray a)
        {
            return new Transform3D(new Vector3((double)a[0], (double)a[1], (double)a[2]), new Vector3((double)a[3], (double)a[4], (double)a[5]),
                new Vector3((double)a[6], (double)a[7], (double)a[8]), new Vector3((double)a[9], (double)a[10], (double)a[11]));
        }

        public static GDict MeshyBody(string name)
        {
            var packed = Stage.Scene(GD.Str(MESHY[name]) + "rigged.glb");
            if (packed == null)
                return new GDict();
            Node3D body = packed.Instantiate() as Node3D;
            foreach (var ap in body.FindChildren("*", "AnimationPlayer", true, false))
                ap.Free();                                   // Meshy's own sample player
            Skeleton3D sk = body.FindChild("Skeleton3D", true, false) as Skeleton3D;
            for (int i = 0; i < sk.GetBoneCount(); i++)
            {
                if (MESHY_RENAME.Has(sk.GetBoneName(i)))
                    sk.SetBoneName(i, GD.Str(MESHY_RENAME[sk.GetBoneName(i)]));
            }
            var skins = new List<Fatebound.GUI.Skin>();
            foreach (var mi in body.FindChildren("*", "MeshInstance3D", true, false))
            {
                Fatebound.GUI.Skin skin = (mi as MeshInstance3D).Skin;
                if (skin != null)
                {
                    skin = skin.Duplicate() as Fatebound.GUI.Skin;                               // per body: we rename and rescale it
                    (mi as MeshInstance3D).Skin = skin;
                    skins.Add(skin);
                    for (int b = 0; b < skin.GetBindCount(); b++)                       // the skin binds bones by name: rename them too
                    {
                        if (MESHY_RENAME.Has(GD.Str(skin.GetBindName(b))))
                            skin.SetBindName(b, GD.Str(MESHY_RENAME[GD.Str(skin.GetBindName(b))]));
                    }
                }
            }
            GDict rig = MeshyRig(name);
            foreach (var hand in new[] { "r", "l" })
            {
                if (rig.Has("slot_" + hand) && sk.FindBone("handslot." + hand) < 0)
                {
                    var bi = sk.GetBoneCount();
                    sk.AddBone("handslot." + hand);
                    sk.SetBoneParent(bi, sk.FindBone("wrist." + hand));
                    sk.SetBoneRest(bi, _Xf(rig["slot_" + hand].A));
                }
            }
            sk.ResetBonePoses();
            // 0.31.53: put the rig in metres at scale 1 (Meshy rigs are centimetres under a 0.01 Armature; with the fit to the
            // KayKit height on top) -- the ragdoll's physics bodies can't live under a scaled skeleton. Every bone rest's offset
            // and every skin bind is scaled by the same factor, then the nodes' scales are reset: the mesh draws exactly as before.
            var a = (double)rig.Get("fit", 1.0);
            Node n = sk;
            while (n != null && n != body)
            {
                if (n is Node3D)
                {
                    a *= (n as Node3D).Scale.x;
                    (n as Node3D).Scale = Vector3.ONE;
                }
                n = n.GetParent();
            }
            for (int i = 0; i < sk.GetBoneCount(); i++)
            {
                var r = sk.GetBoneRest(i);
                sk.SetBoneRest(i, new Transform3D(r.basis, r.origin * a));
            }
            var S = new Transform3D(Basis.FromScale(Vector3.ONE * a), Vector3.ZERO);
            foreach (var skin in skins)
            {
                for (int b = 0; b < skin.GetBindCount(); b++)
                    skin.SetBindPose(b, S * skin.GetBindPose(b));
            }
            sk.ResetBonePoses();
            body.SetMeta("meshy", name);
            return GDict.Of("body", body, "skeleton", sk, "chain", 1.0);
        }

        // 0.31.192 (Kevin: "add glow/smoky effects to the necromancers eyes"): a body's eyes glow and smoke (eye_fx.gd). pts:
        // each eye's middle on the mesh, in the rigged GLB's own space (found from the texels of the Necromancer's painted green
        // eyes, set a hair in front of the face); col: the glow's colour, per outfit -- his own lime green, the Frostbound's
        // ice, the Gravekeeper's lantern green.
        public static readonly GDict EYE_FX = GDict.Of("meshy:necromancer", GDict.Of("pts", GArray.Of(new Vector3(0.057, 0.7185, 0.153), new Vector3(-0.057, 0.7185, 0.153)),
            "col", "#9dff5a", "skins", GDict.Of("necromancer_frost", "#86ecff", "necromancer_gravekeeper", "#7dff9a")));

        public static void _Eyes(Node3D body, Skeleton3D skeleton, string model, string skin, bool lite)
        {
            GDict e = EYE_FX.Get(model, new GDict()).D;
            if (e.IsEmpty() || skeleton.FindBone("head") < 0)
                return;
            Fatebound.GUI.Skin sk = null;
            foreach (var mi in body.FindChildren("*", "MeshInstance3D", true, false))
            {
                if ((mi as MeshInstance3D).Skin != null)
                {
                    sk = (mi as MeshInstance3D).Skin;
                    break;
                }
            }
            if (sk == null)
                return;
            var bind = -1;
            for (int b = 0; b < sk.GetBindCount(); b++)
            {
                if (GD.Str(sk.GetBindName(b)) == "head" || (GD.Str(sk.GetBindName(b)) == "" && sk.GetBindBone(b) == skeleton.FindBone("head")))
                    bind = b;
            }
            if (bind < 0)
                return;
            var att = new BoneAttachment3D();
            att.Name = "Eyes";
            att.BoneName = "head";
            skeleton.AddChild(att);
            var fx = new EyeFx();
            fx.Name = "EyeFx";
            fx.col = new Color(GD.Str(e.Get("skins", new GDict()).D.Get(skin, e["col"])));
            fx.lite = lite;
            var bp = sk.GetBindPose(bind);
            foreach (var p in e["pts"])
                fx.pts.Append(bp * p.AsVec3());                          // the eye where the skin puts that vertex
            fx.up = bp.basis * Vector3.UP;                                   // (the GLB's +Y up, +Z the face's front)
            fx.fwd = bp.basis * Vector3.BACK;
            att.AddChild(fx);
        }

        public static GDict MeshyLibraries(string name)
        {
            if (!_meshy_libs.Has(name))
            {
                var libs = new GDict();
                foreach (var key in new[] { "g", "m", "r", "mb", "ma" })
                {
                    var path = GD.Str(MESHY[name]) + GD.Fmt("anims_%s.res", key);
                    var lib = Stage.Res(path);
                    if (lib != null)
                        libs[key] = Var.Of(lib);
                }
                _meshy_libs[name] = libs;
            }
            return _meshy_libs[name].D;
        }

        public static GDict MakeBody(string cls, GDict cosmetic = null)
        {
            cosmetic ??= new GDict();
            GDict look = LOOKS.Get(cls, LOOKS["knight"]).D.Duplicate();
            // 0.31.188: an outfit brings its own weapon (Eco.SKINS "weapon": {"r", "l"}), or his own repainted ("weapon_tex")
            GDict outfit = Eco.SKINS.Get(GD.Str(cosmetic.Get("skin", "")), new GDict()).D;
            GDict owpn = outfit.Get("weapon", new GDict()).D;
            foreach (var hand in new[] { "r", "l" })
            {
                if (owpn.Has(hand))
                    look[hand] = owpn[hand];
                if (cosmetic.Has(hand))
                    look[hand] = cosmetic[hand];                // (an explicit hand wins: the portraits' busts hold nothing)
            }
            if (GD.Str(look["model"]) == "prop:wyrm")
                return WyrmBody.Make(Stage.Scene(WyrmBody.MODEL), _cast_static);
            if (Array.IndexOf(new[] { "Knight", "meshy:knight", "meshy:crusader" }, GD.Str(look["model"])) >= 0 && GD.Str(look["l"]) == "")
                look["l"] = "bits/shield_B";            // 0.31.41 (Kevin): a Knight (and a Crusader) always carries a shield
            var meshy = GD.Str(look["model"]).BeginsWith("meshy:");
            Node3D body;
            Skeleton3D skeleton;
            var chain = 1.0;
            if (meshy)
            {
                var mb = MeshyBody(GD.Str(look["model"]).Substr(6));
                if (mb.IsEmpty())
                    return new GDict();
                body = mb["body"].As<Node3D>();
                skeleton = mb["skeleton"].As<Skeleton3D>();
                chain = (double)mb["chain"];
                if (GD.Str(cosmetic.Get("skin", "")) != "")
                    ApplySkin(body, GD.Str(cosmetic["skin"]));        // 0.31.186: before the weapons go in his hands (they keep theirs)
            }
            else
            {
                var packed = Stage.Scene(GD.Fmt("res://assets/kaykit/heroes/%s.glb", look["model"]));
                if (packed == null)
                    return new GDict();
                body = packed.Instantiate() as Node3D;
                skeleton = body.FindChild("Skeleton3D", true, false) as Skeleton3D;
                var rig = body.GetNodeOrNull("Rig");
                if (rig != null && body.GetNodeOrNull("Rig_Medium") == null)
                    rig.Name = "Rig_Medium";            // 0.31.157: a Skeletons 1.0 body -- the libraries' tracks name the rig so
            }
            var staffs = new List<(Node3D, string, string)>();
            var hand_models = new List<(Node3D, string, string)>();           // [model, hand, the KayKit file it is held like]
            if (skeleton != null)
            {
                foreach (var hand in new[] { "r", "l" })
                {
                    var file = GD.Str(look.Get(hand, ""));
                    if (file.Length == 0)
                        continue;
                    var slot = new BoneAttachment3D();
                    slot.BoneName = GD.Fmt("handslot.%s", hand);
                    skeleton.AddChild(slot);
                    // "bits/<name>" = KayKit Fantasy Weapons Bits (Round 11): larger models, scaled down.
                    // "mw/<name>" = an Armory Reforged Meshy weapon (0.31.93): placed in the space of the KayKit model it replaced,
                    // so it is held like that one (MESHY_WEAPON_LIKE).
                    var fit_as = WeaponTemplate(file);
                    var weapon = Stage.Scene(WeaponPath(file));
                    if (weapon != null)
                    {
                        Node3D model = weapon.Instantiate() as Node3D;
                        if (GD.Str(outfit.Get("weapon_tex", "")) != "")
                            ApplyWeaponSkin(model, file, GD.Str(outfit["weapon_tex"]));     // 0.31.188: his own weapon, repainted
                        _FitWeapon(model, fit_as, GD.Str(look["model"]), hand);
                        hand_models.Add((model, hand, fit_as));
                        if (IsStaff(fit_as))
                            staffs.Add((model, fit_as, hand));
                        if (meshy)
                        {
                            var holder = new Node3D();         // undo the rig's centimetre scale: weapons keep their size
                            holder.Scale = Vector3.ONE / chain;
                            holder.AddChild(model);
                            slot.AddChild(holder);
                        }
                        else
                            slot.AddChild(model);
                    }
                }
            }
            var player = new AnimationPlayer();
            body.AddChild(player);
            player.RootNode = new NodePath("..");
            GDict libs = meshy ? MeshyLibraries(GD.Str(look["model"]).Substr(6)) : Libraries();
            foreach (var key in libs)
                player.AddAnimationLibrary(key.AsString(), libs[key].As<AnimationLibrary>());
            foreach (var st in staffs)
                _FaceStaff(st.Item1, GD.Str(st.Item2), GD.Str(st.Item3), skeleton, libs, GD.Str(look["idle"]), GD.Str(look["model"]));
            foreach (var hm in hand_models)                                       // 0.31.100: a signature weapon's own effects (0.31.188: an outfit's)
            {
                var hf = GD.Str(look.Get(GD.Str(hm.Item2), ""));
                if (WeaponFx.Wants(hf))
                    WeaponFx.Apply(hm.Item1, hf, GD.Str(hm.Item2) == "r" || hand_models.Count == 1, GD.Str(hm.Item3), (bool)cosmetic.Get("lite", false));
            }
            foreach (var mi in body.FindChildren("*", "MeshInstance3D", true, false))
                (mi as MeshInstance3D).CastShadow = _cast_static ? GeometryInstance3D.SHADOW_CASTING_SETTING_ON : GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            if (meshy && EYE_FX.Has(GD.Str(look["model"])))
                _Eyes(body, skeleton, GD.Str(look["model"]), GD.Str(cosmetic.Get("skin", "")), (bool)cosmetic.Get("lite", false));
            if (!cosmetic.Has("tint") && look.Has("tint"))
            {
                cosmetic = cosmetic.Duplicate();
                cosmetic["tint"] = look["tint"];
            }
            if (cosmetic.Has("tint") && !meshy)                   // (a Meshy model is painted already)
                _ApplyTint(body, GD.Str(look["model"]), new Color(GD.Str(cosmetic["tint"])));
            return GDict.Of("body", body, "player", player);
        }

        // 0.31.186: a hero skin -- his own meshes painted with the skin's texture (Eco.skin_texture: the same UVs as his own,
        // Meshy's retexture kept them). One material per skin and original material, shared by every body wearing it.
        public static GDict _skin_mats = new GDict();

        public static bool ApplySkin(Node3D body, string skin)
        {
            var path = Eco.SkinTexture(skin);
            if (!ResourceLoader.Exists(path))
                return false;
            return _Paint(body, ResourceLoader.Load<Texture2D>(path), skin);
        }

        // 0.31.188: an outfit's repainted weapon -- the piece's own meshes with the outfit's texture for it (Eco.skin_weapon_texture,
        // Meshy's retexture of that piece with its UVs kept), one material per texture and original, shared
        public static bool ApplyWeaponSkin(Node3D model, string file, string key)
        {
            var path = Eco.SkinWeaponTexture(file, key);
            if (!ResourceLoader.Exists(path))
                return false;
            return _Paint(model, ResourceLoader.Load<Texture2D>(path), path);
        }

        public static bool _Paint(Node3D root, Texture2D tex, string key0)
        {
            var done = false;
            foreach (var mi in root.FindChildren("*", "MeshInstance3D", true, false))
            {
                var m3 = mi as MeshInstance3D;
                if (m3.Mesh == null)
                    continue;
                for (int surf = 0; surf < m3.Mesh.GetSurfaceCount(); surf++)
                {
                    var @base = m3.GetActiveMaterial(surf);
                    if (!(@base is BaseMaterial3D))
                        continue;
                    var key = GD.Fmt("%s|%d", key0, (long)@base.GetInstanceId());
                    if (!_skin_mats.Has(key))
                    {
                        var mat = (@base as BaseMaterial3D).Duplicate() as BaseMaterial3D;
                        mat.AlbedoTexture = tex;
                        _skin_mats[key] = Var.Of(mat);
                    }
                    m3.SetSurfaceOverrideMaterial(surf, _skin_mats[key].As<Material>());
                    done = true;
                }
            }
            return done;
        }

        // ---------- staffs: the face turns toward the body (0.31.66, Kevin) ----------
        // 0.31.65 stood every staff upright; Kevin: "make the staffs held how it was before but just make the face of it face
        // towards the body -- the skull, for example, faces the player model". So the hold is the old one again, and the staff
        // is only turned about its own length until its face (STAFF_FACE, in the model's own space: the side the ornament
        // looks out of) points at the holder's chest. Measured from the meshes' heads: the skull bulges out along -X
        // (centroid x -0.24); the flat heads (staff, staff_B, staff_D) are wide in X and thin in Z, so they face +-Z; staff_A
        // (a thin knotted rod) and staff_C (round all the way round) have no face and are left alone. Worked out from the
        // pose, not by eye: the idle animation's frame 0 is applied down the bone chain to the hand slot and to the chest
        // (each bone's rest overridden by its tracks), and the roll about the staff's +Y that points the face at the chest,
        // across the staff, is computed per body, idle and hand. Wands and every other weapon are unchanged.
        public static readonly GDict STAFF_FACE = GDict.Of("Skeleton_Staff", new Vector3(-1, 0, 0), "staff", new Vector3(0, 0, 1), "bits/staff_B", new Vector3(0, 0, 1),
            "bits/staff_D", new Vector3(0, 0, 1));
        public static GDict _staff_pose = new GDict();

        public static bool IsStaff(string file)
        {
            return STAFF_FACE.Has(file);
        }

        public static GDict _PoseTracks(Animation anim)
        {
            // bone name -> {"p": track, "r": track, "s": track} for an animation's 3D transform tracks
            var output = new GDict();
            for (int i = 0; i < anim.GetTrackCount(); i++)
            {
                var tp = anim.TrackGetPath(i);
                if (tp.GetSubnameCount() == 0)
                    continue;
                var bn = GD.Str(tp.GetSubname(0));
                GDict e = output.Get(bn, new GDict()).D;
                switch (anim.TrackGetType(i))
                {
                    case Animation.TYPE_POSITION_3D: e["p"] = i; break;
                    case Animation.TYPE_ROTATION_3D: e["r"] = i; break;
                    case Animation.TYPE_SCALE_3D: e["s"] = i; break;
                }
                output[bn] = e;
            }
            return output;
        }

        public static Transform3D _PosedBone(Skeleton3D sk, Animation anim, GDict tracks, int bone)
        {
            // a bone's skeleton-space transform in the animation's frame 0
            var bones = new List<int>();
            while (bone >= 0)
            {
                bones.Insert(0, bone);
                bone = sk.GetBoneParent(bone);
            }
            var g = Transform3D.IDENTITY;
            foreach (var b in bones)
            {
                var rest = sk.GetBoneRest(b);
                var pos = rest.origin;
                var rot = rest.basis.GetRotationQuaternion();
                var scl = rest.basis.GetScale();
                GDict tr = tracks.Get(sk.GetBoneName(b), new GDict()).D;
                if (tr.Has("p"))
                    pos = anim.PositionTrackInterpolate((int)tr["p"], 0.0);
                if (tr.Has("r"))
                    rot = anim.RotationTrackInterpolate((int)tr["r"], 0.0);
                if (tr.Has("s"))
                    scl = anim.ScaleTrackInterpolate((int)tr["s"], 0.0);
                g = g * new Transform3D(new Basis(rot) * Basis.FromScale(scl), pos);
            }
            return g;
        }

        public static void _FaceStaff(Node3D model, string file, string hand, Skeleton3D sk, GDict libs, string idle, string body_key)
        {
            var key = GD.Fmt("%s|%s|%s", body_key, idle, hand);
            if (!_staff_pose.Has(key))
            {
                var parts = idle.Split("/");
                AnimationLibrary lib = parts.Length == 2 ? libs.Get(parts[0]).As<AnimationLibrary>() : null;
                Animation anim = lib != null && lib.HasAnimation(parts[1]) ? lib.GetAnimation(parts[1]) : null;
                var si = sk.FindBone("handslot." + hand);
                var ci = sk.FindBone("chest");
                if (ci < 0)
                    ci = sk.FindBone("hips");
                if (anim == null || si < 0 || ci < 0)
                    _staff_pose[key] = new GArray();
                else
                {
                    var tracks = _PoseTracks(anim);
                    _staff_pose[key] = GArray.Of(_PosedBone(sk, anim, tracks, si), _PosedBone(sk, anim, tracks, ci).origin);
                }
            }
            GArray pose = _staff_pose[key].A;
            if (pose.IsEmpty())
                return;
            Transform3D slot = (Transform3D)pose[0];
            Vector3 chest = pose[1].AsVec3();
            var top = 0.0;                                         // the head: the top of the staff along its +Y
            foreach (var mi in model.FindChildren("*", "MeshInstance3D", true, false))
            {
                var m3 = mi as MeshInstance3D;
                top = GD.Maxf(top, (m3.Transform * m3.GetAabb()).End.y);
            }
            var to_skel = slot.basis * model.Basis;                // model space -> skeleton space
            var axis = (to_skel * Vector3.UP).NormalizedChecked();
            var head = slot.origin + to_skel * new Vector3(0, top * 0.85, 0);
            var d = chest - head;
            d -= axis * d.Dot(axis);                                // across the staff only
            if (d.Length() < 0.001)
                return;
            var dm = to_skel.Inverse() * d;                        // in the model's own space
            Vector3 face = STAFF_FACE[file].AsVec3();
            model.RotateObjectLocal(Vector3.UP, Math.Atan2(dm.x, dm.z) - Math.Atan2(face.x, face.z));
        }

        // 0.31.43 (Kevin: weapons upside down / wrongly sized -- "staffs shouldn't be super short"). Measured: the Bits pack uses
        // the SAME convention and scale as the Adventurers weapons (grip at the origin, business end along +Y: sword_A 1.77 m
        // vs sword_1handed 1.78, staff_A 2.15 vs staff 2.15), so the old flat 0.55 on every Bits model made them all small --
        // a staff came out 1.2 m. Bits models now keep their size, with a few of the giants brought down to the Adventurers'
        // two-handers (sword_E 3.25 -> 2.4; spears, the big bows, staff_D, the halberd), and shields a little larger than life
        // so a Knight's is obvious. Bows: the Adventurers bow lies along Z and wants a half turn; the Bits bows lie along X and
        // want a quarter turn -- 0.31.104 (Kevin's Hawkeye screenshot: "A lot of the weapons are still not gripped correctly"):
        // the OTHER way round. The quarter turn the same way as the half turn left every Bits bow's string on the far side, away
        // from the archer (Hawkeye, Stag Hunter, Galeshot, Longshot, Heartseeker); tests/weapon_grip_test.gd measures it.
        public static readonly GDict WEAPON_SCALE = new GDict
        {
            { "bits/sword_E", 0.75 }, { "bits/spear_A", 0.8 }, { "bits/spear_B", 0.8 }, { "bits/bow_C_withString", 0.75 }, { "bits/staff_D", 0.85 },
            { "bits/halberd", 0.85 }, { "bits/shield_D", 0.78 }, { "bits/shield_C", 0.85 }, { "bits/shield_B", 0.9 }, { "bits/shield_A", 1.0 }, { "bits/sword_F", 0.9 }, { "bits/hammer_D", 0.9 },
            { "Skeleton_Axe", 0.85 }, { "Skeleton_Shield_Large_A", 0.8 },      // (0.31.157: the jungle's skeletons)
        };

        // 0.31.44 (Kevin's screenshots): crossbows stood up like bows -- they lie forward (a quarter turn about X); shields sat
        // on the hand so the fist poked through the face -- they move out along the slot's Z so the hand is behind the board;
        // the clawed knuckles faced backwards (half turn); the single-bladed cleaver's edge pointed up in the two-handed grip
        // (half turn); the Twin Axes were two axes in a two-handed grip (now one double-bitted axe, in economy.gd).
        public static readonly GDict WEAPON_ROT = GDict.Of("bits/fistweapon_C_left", new Vector3(0, 180, 0), "bits/fistweapon_C_right", new Vector3(0, 180, 0));
        // 0.31.46 (side-view renders): in the Knight's one-handed idle the hand holds the weapon's long axis horizontal, so a
        // halberd lay flat; a quarter turn about Z stands it upright, head up. The Rogue's idle does the same to the scythe
        // (blade up, grim-reaper style). Crossbows lie forward with a quarter turn about X -- opposite signs for the two hands
        // (0.31.45's right-hand crossbows pointed backwards).
        // 0.31.47 (Kevin: back the 90 degrees, and the blade turned 180): the hold he called "right way but backwards" in
        // 0.31.45 -- lying along the arm, axe blade / scythe blade hanging down -- but with the head forward: a half roll about
        // the weapon's own long axis instead of the half turn about Z (which also swung the head behind him).
        public static readonly GDict WEAPON_ROT_FOR = new GDict
        {
            { "Knight", GDict.Of("bits/halberd", new Vector3(0, 180, 0)) }, { "Rogue_Hooded", GDict.Of("bits/scythe", new Vector3(0, 180, 0)) }, { "Rogue", GDict.Of("bits/scythe", new Vector3(0, 180, 0)) },
            { "meshy:knight", GDict.Of("bits/halberd", new Vector3(0, 180, 0)) }, { "meshy:rogue", GDict.Of("bits/scythe", new Vector3(0, 180, 0)) },     // (0.31.80: same holds)
        };

        // 0.31.48 (Kevin: turn these blades 180): the one-handed axe (Worker, Axe & Ale, Axe & Buckler -- its edge faced back
        // in the chop), the Great Cleaver and the Oathkeeper: a half roll about the weapon's own long axis.
        public static GDict WEAPON_ROLL_TEST = new GDict();     // (tools only: try a roll without editing the table)
        // 0.31.64 (Kevin): the Necromancer's staff skull faces the floor (it faced the sky: worked out from the pose -- the
        // skull sits on the model's -X side, and a 195-degree roll points that straight down in the idle); the open
        // spellbook's pages face whoever holds it (cover outward).
        public static readonly GDict WEAPON_ROLL = GDict.Of("axe_1handed", 180.0, "bits/axe_D", 180.0, "bits/sword_G", 180.0, "spellbook_open", 180.0);       // (Skeleton_Staff: see _face_staff, 0.31.66)

        // ---------- Armory Reforged (0.31.93, Kevin: "redo all the weapon models ... more unique and badass") ----------
        // Meshy models made from the approved concept sheets by tools/meshy_weapon.py: each piece is fitted offline into the
        // space of the KayKit model it replaces (same length / face area, grip and facing), so the hand slots, fits, rolls and
        // staff turns tuned for that model apply unchanged. id -> the KayKit file it stands in for. 0.31.94: every class (a
        // piece drawn upright is first turned onto the template's axes where that lies along Z or X -- bows, crossbows, claws;
        // a left-hand claw is the right one mirrored).
        public static readonly GDict MESHY_WEAPON_LIKE = new GDict
        {
            // (0.31.188, Kevin: "Remove the forge and the individual weapon skins": the catalog's weapons and the quests'
            // legendaries are gone, models and all -- 0.31.93-0.31.187 in git history)
            // 0.31.188: the outfits' own weapons (economy.gd OUTFITS) -- each held like its hero's own (tools/meshy_weapon.py fit)
            { "lion_sword", "sword_1handed" }, { "lion_shield", "bits/shield_B" }, { "mammoth_axe", "axe_2handed" },
            { "coin_dagger", "dagger" }, { "orchard_bow", "bow_withString" }, { "phoenix_staff", "staff" }, { "bell_scepter", "wand" },
            { "ember_hammer", "bits/hammer_C" }, { "ashen_shield", "bits/shield_B" }, { "bloodmoon_greatsword", "bits/sword_E" },
            { "ribbon_dagger", "dagger" }, { "wolf_crossbow", "crossbow_2handed" }, { "orrery_staff", "staff" },
            { "starchart_tome", "spellbook_open" }, { "lantern_shovel", "staff" }, { "geode_hammer", "bits/hammer_C" },
            { "geode_shield", "bits/shield_A" }, { "dragon_halberd", "bits/halberd" }, { "rose_rapier", "sword_1handed" },
            { "thorn_stiletto", "bits/dagger_A" }, { "lightning_rod_staff", "staff" }, { "brass_blunderbuss", "crossbow_2handed" },
            { "blossom_staff", "staff" },
            // 0.31.168: the six new 5v5 heroes' props (not cosmetics)
            { "golem_hammer", "bits/hammer_C" }, { "golem_shield", "bits/shield_A" }, { "dragoon_halberd", "bits/halberd" },
            { "duelist_rapier", "sword_1handed" }, { "needlepoint_stiletto", "bits/dagger_A" }, { "storm_staff", "staff" },
            { "druid_staff", "staff" }, { "musket", "crossbow_2handed" },
            // 0.31.159: the 5v5 lane minions' props (not cosmetics)
            { "minion_sword", "sword_1handed" }, { "minion_buckler", "shield_round" }, { "minion_crossbow", "crossbow_1handed" },
            { "minion_cannon", "crossbow_2handed" }, { "minion_hammer", "axe_2handed" },
            // each class's own (siege_view LOOKS; 0.31.93 Armory Reforged)
            { "squire_sword", "sword_1handed" }, { "squire_shield", "bits/shield_B" }, { "woodsplitter_axe", "axe_2handed" },
            { "cutpurse_dagger", "dagger" }, { "ashwood_bow", "bow_withString" }, { "apprentice_staff", "staff" }, { "acolyte_wand", "wand" },
            { "work_hatchet", "axe_1handed" }, { "templar_sword", "sword_1handed" }, { "templar_shield", "bits/shield_B" },
            { "ironhewer_greatsword", "bits/sword_E" }, { "bonecaller_staff", "Skeleton_Staff" }, { "shade_dagger", "dagger" },
            { "marksman_crossbow", "crossbow_2handed" }, { "magister_staff", "staff" }, { "magister_book", "spellbook_open" },
        };

        public static string WeaponPath(string file)
        {
            if (file.BeginsWith("mw/"))
                return GD.Fmt("res://assets/meshy/weapons/%s.glb", file.Substr(3));
            if (file.BeginsWith("bits/"))
                return GD.Fmt("res://assets/kaykit/bits/%s.gltf", file.Substr(5));
            return GD.Fmt("res://assets/kaykit/weapons/%s.gltf", file);
        }

        public static string WeaponTemplate(string file)
        {
            // the KayKit file whose hold a weapon file uses (itself, for a KayKit file)
            return file.BeginsWith("mw/") ? GD.Str(MESHY_WEAPON_LIKE.Get(file.Substr(3), file)) : file;
        }

        public static AABB _ModelBox(Node3D model)
        {
            return WeaponFx.BoxOf(model);
        }

        public static void _FitWeapon(Node3D model, string file, string body_model = "", string hand = "r")
        {
            model.Scale = Vector3.ONE * (double)WEAPON_SCALE.Get(file, 1.0);
            if (file.Contains("crossbow"))
            {
                var r0 = model.Rotation;
                r0.x = (float)GD.DegToRad(hand == "r" ? -90.0 : 90.0);
                model.Rotation = r0;
                if (hand == "r")
                {
                    // 0.31.190 (Kevin: "Now some of weapons are upside down like the musketeer weapons"): 0.31.46's -90 turned the
                    // right hand's crossbows forward but also upside down (the stock's drop and the trigger on top, a gun's lock
                    // underneath) -- a half roll about the piece's own length puts them upright, still pointing forward
                    model.RotateObjectLocal(Vector3.BACK, GD.PI);
                }
            }
            else if (file.Contains("bow"))
            {
                var r0 = model.Rotation;
                r0.y = (float)(file.BeginsWith("bits/") ? -GD.PI * 0.5 : GD.PI);
                model.Rotation = r0;
            }
            if (WEAPON_ROT.Has(file))
            {
                Vector3 r = WEAPON_ROT[file].AsVec3();
                model.Rotation = new Vector3(GD.DegToRad(r.x), GD.DegToRad(r.y), GD.DegToRad(r.z));
            }
            GDict per = WEAPON_ROT_FOR.Get(body_model, new GDict()).D;
            if (per.Has(file))
            {
                Vector3 pr = per[file].AsVec3();
                model.Rotation = new Vector3(GD.DegToRad(pr.x), GD.DegToRad(pr.y), GD.DegToRad(pr.z));
            }
            if (WEAPON_ROLL_TEST.Has(file))
                model.RotateObjectLocal(Vector3.UP, GD.DegToRad((double)WEAPON_ROLL_TEST[file]));
            else if (WEAPON_ROLL.Has(file))
                model.RotateObjectLocal(Vector3.UP, GD.DegToRad((double)WEAPON_ROLL[file]));
            if (file.Contains("shield"))
                model.Position = new Vector3(0.0, 0.0, file.BeginsWith("bits/") ? 0.14 : 0.15);
        }

        public static void _ApplyTint(Node3D body, string model, Color tint)
        {
            // A skin = the model's own material with its albedo multiplied by the tint. Made once per
            // (model, surface, tint) and cached; set once when the body is built, never per frame.
            Skeleton3D skel = body.FindChild("Skeleton3D", true, false) as Skeleton3D;
            foreach (var mi in body.FindChildren("*", "MeshInstance3D", true, false))
            {
                var m3 = mi as MeshInstance3D;
                if (skel != null && !skel.IsAncestorOf(m3))
                    continue;
                var under_hand = false;
                Node n = m3.GetParent();
                while (n != null && n != body)
                {
                    if (n is BoneAttachment3D)
                    {
                        under_hand = true;
                        break;
                    }
                    n = n.GetParent();
                }
                if (under_hand)
                    continue;                       // weapons keep their own colours
                for (int surf = 0; surf < m3.Mesh.GetSurfaceCount(); surf++)
                {
                    var @base = m3.GetActiveMaterial(surf);
                    if (!(@base is StandardMaterial3D))
                        continue;
                    var key = GD.Fmt("%s|%s|%d|%s", model, m3.Name, surf, tint.ToHtmlExact());
                    if (!_tint_mats.Has(key))
                    {
                        StandardMaterial3D m2 = (@base as StandardMaterial3D).Duplicate() as StandardMaterial3D;
                        m2.AlbedoColor = (@base as StandardMaterial3D).AlbedoColor * tint;
                        _tint_mats[key] = Var.Of(m2);
                    }
                    m3.SetSurfaceOverrideMaterial(surf, _tint_mats[key].As<Material>());
                }
            }
        }

        public static GDict _red_mats = new GDict();

        public static void _TeamRed(Node body)
        {
            // 0.31.159: a body (and what it holds) painted in the blue team's colours, in the red team's: each texture's
            // <name>_red.jpg beside it (tools/team_red_tex.py) on a copy of its material -- the same shader, so nothing new to
            // compile mid-match; textures without a red copy (steel, wood) stay as they are
            foreach (var m3 in body.FindChildren("*", "MeshInstance3D", true, false))
            {
                var mi = m3 as MeshInstance3D;
                if (mi.Mesh == null)
                    continue;
                for (int surf = 0; surf < mi.Mesh.GetSurfaceCount(); surf++)
                {
                    var @base = mi.GetActiveMaterial(surf) as StandardMaterial3D;
                    if (@base == null || @base.AlbedoTexture == null)
                        continue;
                    var path = @base.AlbedoTexture.ResourcePath;
                    if (!_red_mats.Has(path))
                    {
                        var red = path.GetBasename() + "_red.jpg";
                        StandardMaterial3D m2 = null;
                        if (path != "" && ResourceLoader.Exists(red))
                        {
                            m2 = @base.Duplicate() as StandardMaterial3D;
                            m2.AlbedoTexture = Stage.Texture(red);
                        }
                        _red_mats[path] = Var.Of(m2);
                    }
                    if (!_red_mats[path].IsNull)
                        mi.SetSurfaceOverrideMaterial(surf, _red_mats[path].As<Material>());
                }
            }
        }

        // 0.31.128 (Kevin: "make the base class models the same size as the advanced class"): every body at the upgraded
        // classes' 1.14 (the base classes were 1.0); an upgraded one still shows by its own model and its gold ring.
        public const double BODY_SCALE = 1.14;

        // 0.31.207 (Kevin: "The match keeps getting stutters"): a wave of 36 lane minions was 36 bodies built in one frame --
        // the phone's log had a 100-350 ms frame every half minute (tools/hitch_bench.gd: +504 nodes in the frame the first wave
        // came). Now a minion's actor, when its minion goes, waits hidden in a pool (by body and team) for the next one; the
        // match's loading card fills the pool with a wave's worth (prefill_minions); and any other body still to build waits
        // its turn -- BUILD_PER_FRAME a frame (heroes never wait).
        public const int MINION_POOL_MAX = 30;                     // (each body and team)
        public const int BUILD_PER_FRAME = 3;
        public GDict _minion_pool = new GDict();                    // "minion_melee|0" -> [actor, ...]
        public int _built_now = 0;                       // bodies built this frame
        public int pool_reused = 0;                      // (tests, the bench)
        public bool _prefilling = false;
        public int pool_built = 0;

        public string _PoolKey(Unit u)
        {
            if (!u.minion || !MINION_LOOKS.Has(u.mk ?? "") || u.look != null)
                return "";
            return GD.Fmt("%s|%d", LookKey(u), Vt(u.team));
        }

        public bool _PoolPut(GDict a)
        {
            // a minion's actor, its minion gone: hidden, its animation still, kept for the next of its kind and side
            var k = GD.Str(a.Get("pool_key", ""));
            if (k == "" || !GD.IsInstanceValid(a["root"]) || a.Get("body").IsNull || !GD.IsInstanceValid(a["body"]) || (bool)a.Get("vanish_on", false))
                return false;
            GArray list = _minion_pool.Get(k, new GArray()).A;
            if (list.Size() >= MINION_POOL_MAX)
                return false;
            if (!a.Get("rag").IsNull)
                _RagdollEnd(a);                           // (its bones back to the animation)
            a["root"].As<Node3D>().Visible = false;
            AnimRun(a["player"], false);
            a["root"].As<Node>().ProcessMode = ProcessModeEnum.Disabled;   // 0.31.220: its skeleton, attachments, eyes: no per-frame work
            list.Append(a);
            _minion_pool[k] = list;
            return true;
        }

        public GDict _PoolTake(string k, Unit u)
        {
            GArray list = _minion_pool.Get(k, new GArray()).A;
            if (list.IsEmpty())
                return new GDict();
            GDict a = list.PopBack().D;
            Node3D root = a["root"].As<Node3D>();
            root.ProcessMode = ProcessModeEnum.Inherit;
            var p = new Vector3(u.pos.x, Sim.HeightAt(u.pos), u.pos.y);
            root.Position = p;
            root.Rotation = new Vector3(0.0, u.face, 0.0);
            root.Visible = true;
            foreach (var kk in new[] { "snap", "gp", "gy", "fog_vis", "whirl_spin", "kick_last", "hit_flip" })
                a.Erase(kk);
            a["snap"] = true;
            a["last"] = p;
            a["dead"] = false;
            a["busy_until"] = 0.0;
            a["clip"] = "";
            a["team"] = u.team;
            a["cls"] = u.cls;
            a["up"] = u.up;
            // what flew out of his hands when he fell (copies) -- his own back in them
            foreach (var slot in a["body"].As<Node3D>().FindChildren("*", "BoneAttachment3D", true, false))
            {
                if (GD.Str((slot as BoneAttachment3D).BoneName).BeginsWith("handslot"))
                {
                    foreach (var w in slot.GetChildren())
                    {
                        if (w is Node3D)
                            (w as Node3D).Visible = true;
                    }
                }
            }
            a["ring"].As<MeshInstance3D>().Visible = true;
            AnimRun(a["player"], true);
            _Play(a, GD.Str(LOOKS.Get(GD.Str(a.Get("mlook", "")) != "" ? GD.Str(a["mlook"]) : u.cls, LOOKS["knight"])["idle"]));
            pool_reused += 1;
            return a;
        }

        public GArray PrefillMinions(GDict per_lane, int lanes = 3)
        {
            // the match's loading card: bodies for a wave's minions on each side, hidden in the pool (a job a body, to spread
            // them over the card's frames) -> [Callable, ...]
            var jobs = new GArray();
            for (int t = 0; t < 2; t++)
            {
                foreach (var mk in per_lane)
                {
                    for (int i = 0; i < (int)per_lane[mk] * lanes; i++)
                    {
                        int team = t;
                        string kind = mk.AsString();
                        int ii = i;
                        jobs.Append((Action)(() =>
                        {
                            // (the .gd's {"id", "cls", "up", "minion", "mk", "team", "pos", "face", "state", "hp", "max_hp"} stand-in)
                            var u = new Unit { id = GD.Fmt("__pool_%d_%s_%d", team, kind, ii), cls = "knight", up = false, minion = true, mk = kind, team = team,
                                pos = new Vector2(0.0, 300.0), face = 0.0, state = "idle", hp = 1.0, max_hp = 1.0 };
                            var k = _PoolKey(u);
                            if (k == "" || _minion_pool.Get(k, new GArray()).A.Size() >= (int)per_lane[kind] * lanes)
                                return;
                            var was = _built_now;
                            _built_now = 0;                // (the card's own budget: not the frame's)
                            _prefilling = true;            // (a new body, not one from the pool)
                            var a = _EnsureActor(u);
                            _prefilling = false;
                            _built_now = was;
                            actors.Erase(u.id);
                            if (a.IsEmpty())
                                return;
                            if (!_PoolPut(a))
                                a["root"].As<Node>().QueueFree();
                            else if (_minion_pool[k].A.Size() == 1)
                                _WarmShow(a);           // (the first of each kind and side: drawn once, beside you)
                        }));
                    }
                }
            }
            return jobs;
        }

        public int PoolSize()
        {
            var n = 0;
            foreach (var k in _minion_pool)
                n += _minion_pool[k].A.Size();
            return n;
        }

        public GArray _pool_shown = new GArray();               // the pooled bodies shown on the loading card (warm_end hides them)

        public void _WarmShow(GDict a)
        {
            GDict me = actors.Get(player_id, new GDict()).D;
            if (me.IsEmpty() || !GD.IsInstanceValid(me["root"]))
                return;
            Node3D root = a["root"].As<Node3D>();
            root.Position = me["root"].As<Node3D>().Position + new Vector3(GD.RandfRange(-3.0, 3.0), 0.0, GD.RandfRange(-3.0, 3.0));
            root.Visible = true;
            root.ProcessMode = ProcessModeEnum.Inherit;
            AnimRun(a["player"], true);
            _pool_shown.Append(a);
        }

        public GArray WarmFight()
        {
            // the loading card: a fight's own looks once beside you -- a hit's spark, number and blood, a pool of it, a body
            // falling and its weapons flying (the first of each drew late on the phone)
            var jobs = new GArray();
            jobs.Append((Action)(() =>
            {
                GDict me = actors.Get(player_id, new GDict()).D;
                if (me.IsEmpty() || !GD.IsInstanceValid(me["root"]))
                    return;
                Vector3 at = me["root"].As<Node3D>().Position;
                var p2 = new Vector2(at.x, at.z);
                Spark(at + new Vector3(0, 1.3, 0), new Color("#ffd27a"));
                Number(at + new Vector3(0, 2.2, 0), "12", false);
                Number(at + new Vector3(0.6, 2.2, 0), "12", true);
                Number(at + new Vector3(-0.6, 2.2, 0), "+12", false, true);
                BloodHit(p2 + new Vector2(1.5, 0.0), p2, 40.0);
                BloodPool(p2 + new Vector2(2.0, 1.0));
            }));
            jobs.Append((Action)(() =>
            {
                foreach (var av in _pool_shown)
                {
                    GDict a = av.D;
                    if (GD.IsInstanceValid(a["root"]) && a["root"].As<Node3D>().Visible && a.Get("rag").IsNull)
                    {
                        _DropWeapons(a, new Vector3(0.0, 1.6, 0.0));
                        _Ragdoll(a, new Vector3(0.0, 1.6, 0.0));
                        return;
                    }
                }
            }));
            return jobs;
        }

        public void WarmEnd()
        {
            // the loading card lifts: what it showed, gone (the bodies back in the pool, hidden; blood and loose weapons away)
            foreach (var av in _pool_shown)
            {
                GDict a = av.D;
                var k = GD.Str(a.Get("pool_key", ""));
                if (!_minion_pool.Get(k, new GArray()).A.Has(a) || !GD.IsInstanceValid(a["root"]))
                    continue;                                   // (already taken for a minion)
                if (!a.Get("rag").IsNull)
                    _RagdollEnd(a);
                a["root"].As<Node3D>().Visible = false;
                AnimRun(a["player"], false);
                a["root"].As<Node>().ProcessMode = ProcessModeEnum.Disabled;
            }
            _pool_shown.Clear();
            foreach (var d in _debris)
            {
                if (GD.IsInstanceValid(d["node"]))
                    d["node"].As<Node>().QueueFree();
                if (GD.IsInstanceValid(d["ground"]))
                    d["ground"].As<Node>().QueueFree();
            }
            _debris.Clear();
            foreach (var list in new[] { _splats, _pools })
            {
                foreach (var m in list)
                    m["mi"].As<MeshInstance3D>().Visible = false;
            }
            foreach (var d in _drops)
            {
                d.D["on"] = false;
                d["mi"].As<MeshInstance3D>().Visible = false;
            }
            foreach (var sh in _shocks)                             // (each shown again every frame it lasts)
            {
                if (GD.IsInstanceValid(sh["node"]))
                    sh["node"].As<Node>().QueueFree();
            }
            _shocks.Clear();
        }

        public static readonly string[] WARM_LOOKS = { "skel_minion", "skel_warrior", "skel_rogue", "skel_mage", "skel_brute", "skel_lord" };

        public GArray WarmBodies(string me_id)
        {
            // the loading card: the jungle's monsters (they first come at 0:30, the Lord at 5:00) shown once beside you -- their
            // materials made and drawn -- then gone (a job a body)
            var jobs = new GArray();
            foreach (var look in WARM_LOOKS)
            {
                string lk = look;
                jobs.Append((Action)(() =>
                {
                    GDict a = actors.Get(me_id, new GDict()).D;
                    if (!LOOKS.Has(lk) || a.IsEmpty() || !GD.IsInstanceValid(a["root"]))
                        return;
                    var made = MakeBody(lk);
                    if (made.IsEmpty())
                        return;
                    Node3D b = made["body"].As<Node3D>();
                    AddChild(b);
                    b.Position = a["root"].As<Node3D>().Position + new Vector3(GD.RandfRange(-2.0, 2.0), 0.0, GD.RandfRange(-2.0, 2.0));
                    b.Scale = Vector3.ONE * BODY_SCALE;
                    GetTree().CreateTimer(2.0).Timeout += b.QueueFree;
                }));
            }
            return jobs;
        }

        public GDict _EnsureActor(Unit u)
        {
            GDict a = actors.Get(u.id, new GDict()).D;
            // The usual case first, without building keys: the actor exists and wears this class (0.31.78: this ran for every
            // unit every frame, formatting a string -- with the player's cosmetics dictionary in it -- 32 times a frame).
            if (!a.IsEmpty() && a["cls"] == u.cls && a["up"] == u.up && GD.Str(a.Get("lk", "")) == (u.look ?? "")
                    && ((u.id != player_id && a["cosmetic"].IsEmpty() && !unit_skins.Has(u.id)) || a["cosmetic"] == UnitCosmetic(u)))
                return a;                                    // (0.31.170: and the same body -- online a player's hero takes a bot's seat)
            // 0.31.38: an upgraded class wears its own cosmetics (the Crusader's, the Berserker's...), not the base class's.
            // 0.31.101: every live player's, not only mine (unit_cosmetic)
            GDict cosmetic = UnitCosmetic(u);
            if (!a.IsEmpty() && u.state == "dead" && !a.Get("body").IsNull)
                return a;                                    // 0.31.20: the body stays as it fell until he respawns
            Node3D root;
            var pk = cosmetic.IsEmpty() ? _PoolKey(u) : "";
            if (a.IsEmpty())
            {
                if (pk != "" && !_prefilling)
                {
                    var pa = _PoolTake(pk, u);            // 0.31.207: a minion's body from the pool
                    if (!pa.IsEmpty())
                    {
                        actors[u.id] = pa;
                        return pa;
                    }
                }
                if (!u.hero && _built_now >= BUILD_PER_FRAME)
                    return new GDict();                              // (0.31.207: its turn next frame)
                _built_now += 1;
                pool_built += 1;
                root = new Node3D();
                AddChild(root);
                root.Position = new Vector3(u.pos.x, 0, u.pos.y);
                var ring = new MeshInstance3D();
                ring.Mesh = _RingMesh(u.id == player_id ? 0.62 : 0.5, 0.12);
                ring.Scale = new Vector3(1, 0.2, 1);
                Color col = u.id == player_id ? GOLD : TEAM_COLORS[Vt(u.team)];
                col.a = 0.9f;
                ring.MaterialOverride = _Unshaded(col);
                var rp = ring.Position;
                rp.y = 0.05f;
                ring.Position = rp;
                ring.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                root.AddChild(ring);
                // HP bars are drawn by the 2D HUD (as in the dice battle); no blob-shadow shader quads.
                a = GDict.Of("root", root, "ring", ring, "body", Var.Nil, "player", Var.Nil, "clip", "", "busy_until", 0.0, "dead", false, "last", root.Position,
                    "team", u.team, "cls", "", "up", false, "cosmetic", new GDict());
                actors[u.id] = a;
            }
            else
            {
                root = a["root"].As<Node3D>();
                if (GD.IsInstanceValid(a["body"]))
                    a["body"].As<Node>().QueueFree();
            }
            var made = MakeBody(LookKey(u), cosmetic);
            if (made.IsEmpty())
                return a;
            Node3D mbody = made["body"].As<Node3D>();
            root.AddChild(mbody);
            var minion_look = u.minion && MINION_LOOKS.Has(u.mk ?? "");
            a["mlook"] = u.look != null || minion_look ? LookKey(u) : "";     // 0.31.157: a monster's own clips (0.31.159: a minion's)
            if (minion_look && Vt(u.team) == 1)
                _TeamRed(mbody);                    // 0.31.159: the minions are painted in the blue team's colours
            mbody.Scale = Vector3.ONE * BODY_SCALE * (u.minion ? MINION_SCALE : 1.0) * u.mscale;   // 0.31.157: big monsters; 0.31.128 (Kevin): every class the upgraded size (base was 1.0); 0.31.155: 5v5 minions smaller
            GDict look = LOOKS.Get(LookKey(u), new GDict()).D;
            if (look.Has("size"))
                mbody.Scale = Vector3.ONE * (double)look["size"];     // 0.31.166: the Wyrm, at its own size
            a["body"] = made["body"];
            a["player"] = made["player"];
            a["pool_key"] = pk;                            // (0.31.207: back to the pool when it goes)
            if (_BlobOnly(u))
            {
                // 0.31.218 (Kevin: "Honor of kings gives me 120fps solid. This game I can hardly hit 30"): a lane minion or a
                // small camp monster casts no real shadow (each one was drawn twice, the second time into the sun's shadow map)
                // -- a soft dark blob on the ground under it instead, as Honor of Kings' minions have
                foreach (var mi in mbody.FindChildren("*", "MeshInstance3D", true, false))
                    (mi as MeshInstance3D).CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                if (!a.Has("blob") || !GD.IsInstanceValid(a["blob"]))
                    a["blob"] = _BlobShadow(root, 0.95 * u.mscale);
                // 0.31.219: ... and is animated ANIM_LOD_HZ times a second, not every frame (its player stepped by sync)
                if (GD.IsInstanceValid(a.Get("player")))
                {
                    var ap = a["player"].As<AnimationPlayer>();
                    ap.CallbackModeProcess = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;
                    a["lod_anim"] = true;
                    a["adt"] = GD.Randf() / ANIM_LOD_HZ;             // (spread over the frames: not all on the same one)
                }
            }
            _CapeSetup(a);
            a["cls"] = u.cls;
            a["up"] = u.up;
            a["lk"] = u.look ?? "";
            a["cosmetic"] = cosmetic;
            a["clip"] = "";
            a["busy_until"] = 0.0;
            _Play(a, GD.Str(LOOKS.Get(GD.Str(a["mlook"]) != "" ? GD.Str(a["mlook"]) : u.cls, LOOKS["knight"])["idle"]));
            a["big"] = (double)look.Get("ring", 0.0);                // (0.31.166: a body far wider than a man)
            if ((double)a["big"] > 0.0 && sim.Alive(u) && (sim.moba == null || sim.moba.CanSee(_MyTeam(), u)))
                _Play(a, "w/Rise", 1.0, 1.6);                        // up out of its pit when it comes (seen)
            // Upgraded: a gold ring (no material overrides on skinned meshes; 0.31.128: no longer a bigger body too).
            Color rc = u.up || u.id == player_id ? GOLD : TEAM_COLORS[Vt(u.team)];
            rc.a = 0.9f;
            a["ring"].As<MeshInstance3D>().MaterialOverride = _FxMat(rc);
            a["ring"].As<MeshInstance3D>().Mesh = _RingMesh(u.up ? 0.75 : (u.id == player_id ? 0.62 : 0.5), u.up ? 0.14 : 0.12);
            if ((double)a["big"] > 0.0)
                a["ring"].As<MeshInstance3D>().Mesh = _RingMesh((double)a["big"], 0.22);
            return a;
        }

        public static readonly string[] BLOB_LOOKS = { "skel_minion", "skel_warrior", "skel_rogue" };      // (the buff monsters, the Lord and the Wyrm keep theirs)
        public static QuadMesh _blob_mesh = null;

        public bool _BlobOnly(Unit u)
        {
            return u.minion || (u.HasMon && Array.IndexOf(BLOB_LOOKS, u.look ?? "") >= 0);
        }

        public MeshInstance3D _BlobShadow(Node3D root, double size)
        {
            // a flat quad on the ground under the unit, a radial gradient from a soft dark middle to nothing (one mesh and
            // material for all of them)
            if (_blob_mesh == null)
            {
                var g = new Gradient();
                g.SetColor(0, new Color(0.02, 0.03, 0.06, 0.5));
                g.SetColor(1, new Color(0.02, 0.03, 0.06, 0.0));
                g.AddPoint(0.55, new Color(0.02, 0.03, 0.06, 0.32));
                var gt = new GradientTexture2D();
                gt.Gradient = g;
                gt.Fill = GradientTexture2D.FillEnum.Radial;
                gt.FillFrom = new Vector2(0.5, 0.5);
                gt.FillTo = new Vector2(1.0, 0.5);
                gt.Width = 64;
                gt.Height = 64;
                var m = new StandardMaterial3D();
                m.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
                m.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
                m.AlbedoTexture = gt;
                m.CullMode = BaseMaterial3D.CULL_DISABLED;
                _blob_mesh = new QuadMesh();
                _blob_mesh.Orientation = PlaneMesh.FACE_Y;
                _blob_mesh.Size = new Vector2(1, 1);
                _blob_mesh.Material = m;
            }
            var mi = new MeshInstance3D();
            mi.Mesh = _blob_mesh;
            mi.Scale = new Vector3(size, 1.0, size);
            var mp = mi.Position;
            mp.y = 0.04f;
            mi.Position = mp;
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.Name = "Blob";
            root.AddChild(mi);
            return mi;
        }

        public void _Play(GDict a, string clip, double speed = 1.0, double busy = 0.0)
        {
            AnimationPlayer player = a["player"].As<AnimationPlayer>();
            if (!GD.IsInstanceValid(player))
                return;
            if (!player.HasAnimation(clip))
                clip = "g/Idle_A";
            if (busy > 0.0)
                a["busy_until"] = _time + busy;
            if (a["clip"] == clip && player.IsPlaying() && busy <= 0.0)
            {
                player.SpeedScale = (float)speed;
                return;
            }
            a["clip"] = clip;
            player.Play(clip, 0.1);
            player.SpeedScale = (float)speed;
        }

        // Animation culling (0.14.3): characters outside the camera view don't run their AnimationPlayer
        // (so no skeleton update or skinning upload either); they resume the moment they come into view.
        public bool anim_cull = true;
        public int anim_active = 0;
        public const double ANIM_LOD_HZ = 30.0;
        public const int OFF_EVERY = 4;                       // (0.31.220: a body off the screen placed every 4th frame)
        public int _frame_n = 0;
        public int _off_n = 0;
        public bool anim_freeze = false;                   // (0.31.220, gpu_probe.gd: every body's animation paused for a moment)

        // 0.31.219 (Kevin's 0.31.218 log: 23 fps in a 5v5, the CPU the limit): a player is paused by its process mode, not by
        // switching it off -- AnimationMixer.active = false throws away its caches (every track of its 81 clips bound again
        // when it's switched back on: 0.25-0.75 ms here a time, a few times that on the phone), and the view switched it each
        // time a body crossed the screen's edge or the fog, and for every minion taken from the pool (a wave: 36). A paused
        // player keeps them (switching back: ~0.006 ms).
        public static void AnimRun(Var player, bool on)
        {
            if (player.IsNull || !GD.IsInstanceValid(player))
                return;
            var ap = player.As<AnimationPlayer>();
            if (!ap.Active)
                ap.Active = true;                       // (an older body switched off: on once, for good)
            var pm = on ? ProcessModeEnum.Inherit : ProcessModeEnum.Disabled;
            if (ap.ProcessMode != pm)
                ap.ProcessMode = pm;
        }

        public static bool AnimRunning(Var player)
        {
            return !player.IsNull && GD.IsInstanceValid(player) && player.As<AnimationPlayer>().Active
                && player.As<AnimationPlayer>().ProcessMode != ProcessModeEnum.Disabled;
        }

        public bool _OnScreen(Vector3 p, Plane[] planes, double r = 1.8)
        {
            // Bounding sphere (1.8 m; 0.31.166: a big body's own) against the camera frustum planes.
            var c = p + new Vector3(0, 1.0, 0);
            foreach (var pl in planes)
            {
                if (pl.DistanceTo(c) > r)
                    return false;
            }
            return true;
        }

        public bool prof_on = false;                      // (tests/moba_bench.gd: microseconds per part of sync in prof)
        public GDict prof = new GDict();

        public long _Pv(string key, long t0)
        {
            var now = Time.GetTicksUsec();
            prof[key] = (long)prof.Get(key, 0) + (now - t0);
            return now;
        }

        public void Sync(double dt)
        {
            var tp = prof_on ? Time.GetTicksUsec() : 0;
            _time += dt;
            _SyncMeteorFx(dt);
            _SyncRecallFx(dt);
            if (prof_on) tp = _Pv("pre.meteors", tp);
            _SyncShocks();
            _KickDebris();
            if (prof_on) tp = _Pv("pre.shocks+debris", tp);
            _SyncAmbience(dt);
            if (prof_on) tp = _Pv("pre.amb", tp);
            _SyncRipples(dt);
            if (prof_on) tp = _Pv("pre.ripples", tp);
            _SyncBlood(dt);
            if (prof_on) tp = _Pv("pre.blood", tp);
            var seen = new GDict();
            _built_now = 0;                                 // 0.31.207: bodies built this frame (BUILD_PER_FRAME)
            Plane[] planes = anim_cull && GD.IsInstanceValid(camera) && camera.IsInsideTree() ? camera.GetFrustum() : new Plane[0];
            _planes = planes;
            anim_active = 0;
            // 0.31.160 (Kevin's phone log: the 5v5's view 12-16 ms a frame): per actor, only what changed -- the ground height
            // looked up again only when the unit moved (Sim.height_at is ~6 us), the transform written only while it's still
            // easing in (snapped once within a millimetre / a fraction of a degree), and the hand, load, Vanish, animation and
            // cape left alone while the body isn't drawn (in the fog, or off the screen; the dead and the just-respawned
            // always). A body hidden in the fog isn't moved at all: it snaps to its place when it's seen again.
            var my_team = _MyTeam();
            _frame_n += 1;
            _off_n = 0;
            var pos_k = 1.0 - Math.Exp(-dt * 22.0);
            var rot_k = 1.0 - Math.Exp(-dt * 18.0);
            foreach (var u in sim.units)
            {
                seen[u.id] = true;
                var tu = prof_on ? Time.GetTicksUsec() : 0;
                var a = _EnsureActor(u);
                if (prof_on) tu = _Pv("a.ensure", tu);
                if (a.IsEmpty() || !GD.IsInstanceValid(a["root"]))
                    continue;
                Node3D root = a["root"].As<Node3D>();
                bool alive_u = sim.Alive(u);
                if (sim.moba != null)
                {
                    // 0.31.158 5V5 fog of war: an enemy (or a monster) your side can't see isn't drawn (one that falls in sight
                    // stays shown where he fell)
                    bool fv = u.team == my_team || (alive_u && sim.moba.CanSee(my_team, u))
                        || (!alive_u && (bool)a.Get("fog_vis", false));
                    if (alive_u)
                        a["fog_vis"] = fv;
                    if (root.Visible != fv)
                    {
                        root.Visible = fv;
                        if (fv)
                            a["snap"] = true;
                    }
                    if (!fv)
                    {
                        if (AnimRunning(a["player"]))
                            AnimRun(a["player"], false);
                        if (prof_on) tu = _Pv("a.place+fog", tu);
                        continue;
                    }
                }
                Vector2 up = u.pos;
                double gy;
                if (a.Get("gp", Vector2.INF) == up)
                    gy = (double)a["gy"];
                else
                {
                    gy = Sim.HeightAt(up);
                    a["gp"] = up;
                    a["gy"] = gy;
                }
                var target = new Vector3(up.x, gy, up.y);
                // 0.31.220 (Kevin's 0.31.219 log: the view's bodies 3-6 ms a frame on his phone, two-thirds of them off the
                // screen): a living body well off the screen is placed every OFF_EVERY-th frame (straight to its place, turned
                // to its facing), its animation paused -- the easing, turning and animating only for what can be seen. Coming
                // back on, it eases from there (a few frames old, still off the edge).
                var rad = (double)a.Get("big", 0.0) <= 0.0 ? 1.8 : 5.0;
                if (alive_u && !(bool)a["dead"] && planes.Length != 0 && u.state != "dash" && !_OnScreen(target, planes, rad + 2.5))
                {
                    a["onscr"] = false;
                    _off_n += 1;
                    if ((_frame_n + (int)a.Get("off_ph", -1)) % OFF_EVERY == 0 || !a.Has("off_ph"))
                    {
                        if (!a.Has("off_ph"))
                            a["off_ph"] = _off_n % OFF_EVERY;
                        if (root.Position != target)
                            root.Position = target;
                        if (Math.Abs(GD.AngleDifference(root.Rotation.y, u.face)) > 0.0005)
                        {
                            var rr = root.Rotation;
                            rr.y = (float)u.face;
                            root.Rotation = rr;
                        }
                    }
                    if (GD.IsInstanceValid(a["player"]) && AnimRunning(a["player"]))
                        AnimRun(a["player"], false);
                    if (prof_on) tu = _Pv("a.place+fog", tu);
                    continue;
                }
                if (u.state == "dash" && u.dash != null && u.dash.leap)
                {
                    // 0.31.168: a leap arcs (LEAP, VAULT, DRAGON DIVE): up and down over the dash, higher the longer it is
                    Dash dd = u.dash;
                    var tot = GD.Maxf(0.5, dd.total);
                    var k = GD.Clampf(1.0 - dd.left / tot, 0.0, 1.0);
                    target.y += (float)(Math.Sin(k * GD.PI) * GD.Minf(4.5, 0.35 * tot));
                }
                var before = root.Position;
                // Smooth between 30 Hz sim ticks; snap on respawn teleports (and coming out of the fog).
                var newp = target;
                if ((bool)a.Get("snap", false))
                    a.Erase("snap");
                else if (before.DistanceSquaredTo(target) <= 36.0)
                {
                    newp = before.Lerp(target, pos_k);
                    if (newp.DistanceSquaredTo(target) < 0.000001)
                        newp = target;
                }
                if (newp != before)
                    root.Position = newp;
                var vel = (newp - before).Length() / GD.Maxf(dt, 0.001);
                if (sim.Whirling(u) && u.state != "dead")
                {
                    // 0.31.16 (Kevin: "the barbarian model should spin with the vfx"): he turns with his whirlwind -- the same way
                    // round as its ribbons and nearly as fast (they turn at 44 and 34 rad/s; he at 38).
                    a["whirl_spin"] = (double)a.Get("whirl_spin", 0.0) + dt * 38.0;
                    var rr = root.Rotation;
                    rr.y = (float)(u.face - (double)a["whirl_spin"]);
                    root.Rotation = rr;
                }
                else
                {
                    if ((double)a.Get("whirl_spin", 0.0) != 0.0)
                        a["whirl_spin"] = 0.0;
                    var ry = root.Rotation.y;
                    if (Math.Abs(GD.AngleDifference(ry, u.face)) > 0.0005)
                    {
                        var rr = root.Rotation;
                        rr.y = (float)GD.LerpAngle(ry, u.face, rot_k);
                        root.Rotation = rr;
                    }
                }
                a["ring"].As<MeshInstance3D>().Visible = u.state != "dead";
                if (a.Has("blob"))
                    a["blob"].As<Node3D>().Visible = u.state != "dead";         // (0.31.218: its blob shadow goes with its ring)
                if (prof_on) tu = _Pv("a.place+fog", tu);
                var show = root.Visible && (planes.Length == 0 || _OnScreen(newp, planes, rad));
                a["onscr"] = show;                          // (0.31.219: bars() skips the bodies off the screen)
                if (show || !alive_u || (bool)a["dead"])
                {
                    _SyncVanish(a, u);
                    if (prof_on) tu = _Pv("a.vanish", tu);
                    _Animate(a, u, vel);
                    if (prof_on) tu = _Pv("a.animate", tu);
                    if (!a.Get("cape").IsNull)
                        _CapeStep(a, dt);
                }
                if (GD.IsInstanceValid(a["player"]))
                {
                    AnimRun(a["player"], show && !anim_freeze);
                    if (show && !anim_freeze)
                    {
                        anim_active += 1;
                        if ((bool)a.Get("lod_anim", false))
                        {
                            // 0.31.219: a minion's or small monster's animation 30 times a second (at 60 fps: every other
                            // frame) -- each animated body costs the engine its animation, its skeleton and its skinning; a
                            // lane fight shows twenty of them, each ~40 px tall
                            var adt = (double)a.Get("adt", 0.0) + dt;
                            if (adt >= 1.0 / ANIM_LOD_HZ - 0.002)
                            {
                                a["player"].As<AnimationPlayer>().Advance(adt);
                                adt = 0.0;
                            }
                            a["adt"] = adt;
                        }
                    }
                }
            }
            if (prof_on) tp = _Pv("actors", tp);
            foreach (var id in actors.Keys())
            {
                if (!seen.Has(id))
                {
                    if (_PoolPut(actors[id].D))                  // 0.31.207: a minion's body waits for the next one
                    {
                        actors.Erase(id);
                        continue;
                    }
                    if (!actors[id].D.Get("rag").IsNull)
                        _RagdollEnd(actors[id].D);               // 0.31.160: its ground patch and its place among the RAG_MAX go too
                    actors[id]["root"].As<Node>().QueueFree();
                    actors.Erase(id);
                }
            }
            _SyncOracles(dt);
            if (prof_on) tp = _Pv("oracles", tp);
            _SyncCastle(dt);
            if (prof_on) tp = _Pv("castle", tp);
            _SyncProjectiles();
            if (prof_on) tp = _Pv("projectiles", tp);
            if (sim.moba != null)
            {
                _SyncMoba();
                _SyncFalling(dt);                          // 0.31.172: a tower's broken-off pieces
            }
            if (prof_on) tp = _Pv("moba", tp);
            _StepFx();
            if (fxs != null)
                fxs.Step(dt);                               // 0.31.201: the abilities' effects
            if (prof_on) tp = _Pv("fx", tp);
            _UpdateCamera(dt);
            if (prof_on) tp = _Pv("camera", tp);
        }
    }
}
