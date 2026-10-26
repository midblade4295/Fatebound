// `guitest anim`: the port's Skeleton3D / BoneAttachment3D / Animation / AnimationLibrary / AnimationPlayer running the
// same scene and frame sequence as tools/parity/godot_anim.gd, printing the same lines -- tools/parity/anim.sh diffs the
// two. Part 2 reads the real assets' dump Godot wrote ($FB_ANIM_OUT/anim_dump.bin: the Meshy knight's skeleton and skin
// as the game prepares them, and the stored properties of its anims_g / anims_mb libraries) and builds the animations
// through SetStoredProperty, as the baked-asset loader will.
using System;
using System.Collections.Generic;
using System.IO;
using Fatebound.GUI;
using Fatebound.Sim;

namespace GuiTest
{
    public static class AnimTest
    {
        static int frame;
        static Node3D body, weapon, pivot;
        static Skeleton3D skel;
        static AnimationPlayer player;
        static BoneAttachment3D att;
        static Skin skin;
        static bool hasCur;
        static readonly Xform3[] skinBuf = new Xform3[64];

        static Node3D rbody;
        static Skeleton3D rskel;
        static AnimationPlayer rplayer;
        static Skin rskin;
        static bool rhas;

        static void p(string k, Var v) => Console.WriteLine(k + "|" + GD.Str(v));
        static Vec3 V(double x, double y, double z) => new Vec3((float)x, (float)y, (float)z);
        static Var Q(Vec3 axis, double angle) => Var.Of(new Quat(axis, angle));
        static Xform3 XF(Vec3 axis, double angle, Vec3 sc, Vec3 origin) => new Xform3(new Basis(axis.Normalized(), angle).Scaled(sc), origin);

        sealed class Marker : Node
        {
            public void Mark(string what, long n) => Console.WriteLine("call|mark|" + what + "|" + n);
        }

        // the skeleton-modifier hook (what the ragdoll will use): arm.l turned on top of the animation, tail pinned
        sealed class Twist : SkeletonModifier3D
        {
            protected override void _ProcessModificationWithDelta(double delta)
            {
                var sk = GetSkeleton();
                int b = sk.FindBone("arm.l");
                sk.SetBonePoseRotation(b, sk.GetBonePoseRotation(b) * new Quat(V(1, 0, 0), 0.7));
                sk.SetBoneGlobalPose(sk.FindBone("tail"), new Xform3(new Basis(V(0, 1, 0), 0.4), V(0.1, 0.5, -0.3)));
            }
        }

        static Twist twist;

        static AnimationLibrary[] BuildAnimations()
        {
            var lib = new AnimationLibrary();
            var lib2 = new AnimationLibrary();
            const string P = "Armature/Skeleton3D:";

            var idle = new Animation { Length = 1.2, LoopMode = Animation.LOOP_LINEAR };
            int t = idle.AddTrack(Animation.TYPE_POSITION_3D);
            idle.TrackSetPath(t, P + "hips");
            idle.TrackInsertKey(t, 0.0, V(0, 1.0, 0));
            idle.TrackInsertKey(t, 0.4, V(0.05, 1.04, -0.02));
            idle.TrackInsertKey(t, 0.9, V(-0.03, 0.97, 0.01));
            t = idle.AddTrack(Animation.TYPE_ROTATION_3D);
            idle.TrackSetPath(t, P + "hips");
            idle.TrackInsertKey(t, 0.0, Q(V(0, 1, 0), 0.2));
            idle.TrackInsertKey(t, 0.6, Q(V(0, 1, 0.3).Normalized(), -0.35));
            idle.TrackInsertKey(t, 1.1, Q(V(1, 0, 0), 0.15));
            t = idle.AddTrack(Animation.TYPE_ROTATION_3D);
            idle.TrackSetPath(t, P + "spine");
            idle.TrackInsertKey(t, 0.1, Q(V(1, 0, 0), 0.3));
            idle.TrackInsertKey(t, 0.7, Q(V(1, 0.2, 0).Normalized(), -0.4), 0.5);
            t = idle.AddTrack(Animation.TYPE_SCALE_3D);
            idle.TrackSetPath(t, P + "spine");
            idle.TrackInsertKey(t, 0.0, V(1, 1, 1));
            idle.TrackInsertKey(t, 0.6, V(1.1, 0.95, 1.05), -2.0);
            t = idle.AddTrack(Animation.TYPE_ROTATION_3D);
            idle.TrackSetPath(t, P + "chest");
            idle.TrackInsertKey(t, 0.0, Q(V(0, 0, 1), 0.1));
            idle.TrackInsertKey(t, 1.2, Q(V(0, 0, 1), -0.1));
            t = idle.AddTrack(Animation.TYPE_VALUE);
            idle.TrackSetPath(t, "Pivot:position");
            idle.TrackInsertKey(t, 0.0, V(0, 0, 0));
            idle.TrackInsertKey(t, 0.5, V(0.3, 0.1, -0.2));
            lib.AddAnimation("idle", idle);

            var walk = new Animation { Length = 0.8, LoopMode = Animation.LOOP_LINEAR };
            t = walk.AddTrack(Animation.TYPE_POSITION_3D);
            walk.TrackSetPath(t, P + "hips");
            walk.TrackSetInterpolationType(t, Animation.INTERPOLATION_CUBIC);
            walk.TrackInsertKey(t, 0.0, V(0, 0.95, 0));
            walk.TrackInsertKey(t, 0.2, V(0.02, 1.02, 0.1));
            walk.TrackInsertKey(t, 0.4, V(0, 0.95, 0.2));
            walk.TrackInsertKey(t, 0.65, V(-0.02, 1.03, 0.1));
            t = walk.AddTrack(Animation.TYPE_ROTATION_3D);
            walk.TrackSetPath(t, P + "hips");
            walk.TrackSetInterpolationType(t, Animation.INTERPOLATION_CUBIC);
            walk.TrackInsertKey(t, 0.0, Q(V(0, 1, 0), 2.9));
            walk.TrackInsertKey(t, 0.3, Q(V(0, 1, 0), -2.8));
            walk.TrackInsertKey(t, 0.55, Q(V(0.3, 1, 0).Normalized(), 3.1));
            walk.TrackInsertKey(t, 0.8, Q(V(0, 1, 0), 2.9));
            t = walk.AddTrack(Animation.TYPE_ROTATION_3D);
            walk.TrackSetPath(t, P + "head");
            walk.TrackSetInterpolationType(t, Animation.INTERPOLATION_CUBIC_ANGLE);
            walk.TrackInsertKey(t, 0.0, Q(V(1, 0, 0), -0.3));
            walk.TrackInsertKey(t, 0.4, Q(V(0, 0, 1), 1.2));
            t = walk.AddTrack(Animation.TYPE_ROTATION_3D);
            walk.TrackSetPath(t, P + "arm.l");
            walk.TrackInsertKey(t, 0.0, Q(V(0, 0, 1), 1.5));
            walk.TrackInsertKey(t, 0.4, Q(V(0, 0, 1), -1.5));
            t = walk.AddTrack(Animation.TYPE_VALUE);
            walk.TrackSetPath(t, "Pivot:position");
            walk.TrackSetInterpolationType(t, Animation.INTERPOLATION_CUBIC);
            walk.TrackInsertKey(t, 0.0, V(0, 0.5, 0));
            walk.TrackInsertKey(t, 0.3, V(0.2, 0.1, 0.4));
            walk.TrackInsertKey(t, 0.6, V(-0.1, 0.3, 0.1));
            t = walk.AddTrack(Animation.TYPE_VALUE);
            walk.TrackSetPath(t, "Pivot:rotation:y");
            walk.TrackSetInterpolationType(t, Animation.INTERPOLATION_LINEAR_ANGLE);
            walk.TrackInsertKey(t, 0.0, 3.0);
            walk.TrackInsertKey(t, 0.4, -3.0);
            t = walk.AddTrack(Animation.TYPE_VALUE);
            walk.TrackSetPath(t, "Pivot:visible");
            walk.ValueTrackSetUpdateMode(t, Animation.UPDATE_DISCRETE);
            walk.TrackInsertKey(t, 0.0, true);
            walk.TrackInsertKey(t, 0.3, false);
            walk.TrackInsertKey(t, 0.6, true);
            t = walk.AddTrack(Animation.TYPE_METHOD);
            walk.TrackSetPath(t, "Marker");
            walk.TrackInsertKey(t, 0.1, new GDict { ["method"] = "mark", ["args"] = GArray.Of("step", 1) });
            walk.TrackInsertKey(t, 0.5, new GDict { ["method"] = "mark", ["args"] = GArray.Of("step", 2) });
            lib.AddAnimation("walk", walk);

            var hit = new Animation { Length = 0.5 };
            t = hit.AddTrack(Animation.TYPE_ROTATION_3D);
            hit.TrackSetPath(t, P + "arm.l");
            hit.TrackInsertKey(t, 0.0, Q(V(0, 0, 1), 0.2), 2.0);
            hit.TrackInsertKey(t, 0.25, Q(V(0, 1, 1).Normalized(), 2.0), 0.4);
            hit.TrackInsertKey(t, 0.5, Q(V(0, 0, 1), 0.3));
            t = hit.AddTrack(Animation.TYPE_POSITION_3D);
            hit.TrackSetPath(t, P + "hand.l");
            hit.TrackInsertKey(t, 0.05, V(0.1, 0.3, 0));
            hit.TrackInsertKey(t, 0.45, V(0.2, 0.5, 0.1));
            t = hit.AddTrack(Animation.TYPE_ROTATION_3D);
            hit.TrackSetPath(t, P + "hips");
            hit.TrackInsertKey(t, 0.0, Q(V(1, 0, 0), -0.5));
            hit.TrackInsertKey(t, 0.3, Q(V(1, 0, 0), 0.6));
            lib.AddAnimation("hit", hit);

            var spin = new Animation { Length = 0.6, LoopMode = Animation.LOOP_PINGPONG };
            t = spin.AddTrack(Animation.TYPE_ROTATION_3D);
            spin.TrackSetPath(t, P + "chest");
            spin.TrackInsertKey(t, 0.0, Q(V(0, 1, 0), 0.0));
            spin.TrackInsertKey(t, 0.2, Q(V(0, 1, 0), 2.1));
            spin.TrackInsertKey(t, 0.4, Q(V(0, 1, 0), -2.1));
            t = spin.AddTrack(Animation.TYPE_SCALE_3D);
            spin.TrackSetPath(t, P + "head");
            spin.TrackSetInterpolationType(t, Animation.INTERPOLATION_CUBIC);
            spin.TrackInsertKey(t, 0.0, V(1, 1, 1));
            spin.TrackInsertKey(t, 0.3, V(1.3, 1.3, 1.3));
            spin.TrackInsertKey(t, 0.6, V(0.8, 1, 1.2));
            lib2.AddAnimation("spin", spin);

            var snap = new Animation { Length = 1.0, LoopMode = Animation.LOOP_LINEAR };
            t = snap.AddTrack(Animation.TYPE_POSITION_3D);
            snap.TrackSetPath(t, P + "tail");
            snap.TrackSetInterpolationType(t, Animation.INTERPOLATION_NEAREST);
            snap.TrackInsertKey(t, 0.0, V(0, -0.2, -0.1));
            snap.TrackInsertKey(t, 0.5, V(0, -0.3, -0.3));
            t = snap.AddTrack(Animation.TYPE_ROTATION_3D);
            snap.TrackSetPath(t, P + "tail");
            snap.TrackSetInterpolationLoopWrap(t, false);
            snap.TrackInsertKey(t, 0.2, Q(V(1, 0, 0), 1.0));
            snap.TrackInsertKey(t, 0.8, Q(V(1, 0, 0), -1.0));
            lib2.AddAnimation("snap", snap);
            return new[] { lib, lib2 };
        }

        static void BuildScene(Node root)
        {
            body = new Node3D { Name = "Body" };
            body.Position = V(1, 0, -2);
            body.Rotation = V(0, 0.7, 0);
            var arm = new Node3D { Name = "Armature" };
            arm.Scale = V(0.5, 0.5, 0.5);
            body.AddChild(arm);
            skel = new Skeleton3D { Name = "Skeleton3D" };
            arm.AddChild(skel);
            string[] names = { "hips", "spine", "chest", "head", "arm.l", "hand.l", "tail" };
            int[] parents = { -1, 0, 1, 2, 2, 4, 0 };
            Xform3[] rests =
            {
                XF(V(0, 1, 0), 0.3, V(1, 1, 1), V(0, 1.0, 0)),
                XF(V(1, 0.2, 0), 0.25, V(1.1, 0.9, 1.0), V(0, 0.3, 0.02)),
                XF(V(0.1, 0, 1), -0.2, V(1, 1, 1), V(0, 0.35, 0)),
                XF(V(0, 1, 0.3), 0.5, V(0.9, 0.9, 0.9), V(0, 0.3, 0.05)),
                XF(V(0, 0, 1), 1.4, V(1, 1.2, 1), V(0.2, 0.25, 0)),
                XF(V(1, 1, 0), -0.6, V(1, 1, 1), V(0, 0.35, 0)),
                XF(V(1, 0, 0), 2.6, V(1, 1, 1), V(0, -0.1, -0.15)),
            };
            foreach (var n in names) skel.AddBone(n);
            for (int i = 0; i < names.Length; i++)
            {
                skel.SetBoneParent(i, parents[i]);
                skel.SetBoneRest(i, rests[i]);
            }
            skel.ResetBonePoses();
            skin = new Skin();
            skin.AddNamedBind("hips", XF(V(0, 1, 0), 0.1, V(1, 1, 1), V(0, -1, 0)));
            skin.AddNamedBind("hand.l", XF(V(1, 0, 0), 0.4, V(1, 1, 1), V(-0.2, -1.9, 0)));
            skin.AddBind(3, XF(V(0, 0, 1), -0.3, V(1, 1, 1), V(0, -2.0, 0.1)));
            pivot = new Node3D { Name = "Pivot" };
            body.AddChild(pivot);
            body.AddChild(new Marker { Name = "Marker" });
            player = new AnimationPlayer { Name = "AnimationPlayer" };
            body.AddChild(player);
            player.RootNode = "..";
            var libs = BuildAnimations();
            player.AddAnimationLibrary("", libs[0]);
            player.AddAnimationLibrary("x", libs[1]);
            player.AnimationStarted += n => p("sig|started", n);
            player.AnimationFinished += n => p("sig|finished", n);
            player.AnimationChanged += (a, b) => p("sig|changed", a + ">" + b);
            player.CurrentAnimationChanged += n => p("sig|current", n);
            root.AddChild(body);
            att = new BoneAttachment3D { Name = "Hand" };
            att.BoneName = "hand.l";
            skel.AddChild(att);
            weapon = new Node3D();
            weapon.Position = V(0, 0.2, 0.05);
            weapon.Rotation = V(0.1, 0.2, 0.3);
            att.AddChild(weapon);
        }

        static void InterpDump(string prefix, Animation anim, double[] times)
        {
            for (int i = 0; i < anim.GetTrackCount(); i++)
            {
                var tt = anim.TrackGetType(i);
                foreach (double tm in times)
                {
                    string k = prefix + "|" + i + "|" + GD.Str(tm);
                    switch (tt)
                    {
                        case Animation.TrackType.Position3D: p(k, anim.PositionTrackInterpolate(i, tm)); break;
                        case Animation.TrackType.Rotation3D:
                            p(k, Var.Of(anim.RotationTrackInterpolate(i, tm)));
                            p(k + "|bw", Var.Of(anim.RotationTrackInterpolate(i, tm, true)));
                            break;
                        case Animation.TrackType.Scale3D: p(k, anim.ScaleTrackInterpolate(i, tm)); break;
                        case Animation.TrackType.Value:
                            p(k, anim.ValueTrackInterpolate(i, tm));
                            p(k + "|bw", anim.ValueTrackInterpolate(i, tm, true));
                            break;
                    }
                }
            }
        }

        static void State()
        {
            string f = "f" + frame;
            p(f + "|cur", player.CurrentAnimation + "|" + player.AssignedAnimation + "|" + GD.Str(player.IsPlaying()));
            if (hasCur) p(f + "|pos", player.CurrentAnimationPosition);
            for (int i = 0; i < skel.GetBoneCount(); i++) p(f + "|b" + i, Var.Of(skel.GetBoneGlobalPose(i)));
            p(f + "|att", Var.Of(att.GlobalTransform));
            p(f + "|wpn", Var.Of(weapon.GlobalTransform));
            p(f + "|pivot", GD.Str(pivot.Position) + "|" + GD.Str((double)pivot.Rotation.y) + "|" + GD.Str(pivot.Visible));
            skel.GetSkinTransforms(skin, skinBuf);
            for (int b = 0; b < skin.GetBindCount(); b++) p(f + "|skin" + b, Var.Of(skinBuf[b]));
        }

        static void Step()
        {
            switch (frame)
            {
                case 0: player.Play("idle"); hasCur = true; break;
                case 8: player.Play("walk", 0.2); break;
                case 20: player.PlaybackDefaultBlendTime = 0.05; player.Play("x/spin"); break;
                case 30: player.Seek(0.3, true); break;
                case 32: player.SpeedScale = 1.5f; break;
                case 33: player.Seek(0.1); break;
                case 40: player.Play("hit", 0.15); player.Queue("idle"); break;
                case 64: player.Play("x/snap", 0.1); break;
                case 70: player.CallbackModeProcess = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL; player.Advance(0.13); break;
                case 71: case 72: case 73: case 76: case 77: case 78: case 79: player.Advance(0.13); break;
                case 74: player.SetBlendTime("x/snap", "walk", 0.25); break;
                case 75: player.Play("walk"); player.Advance(0.13); break;
                case 80: player.Pause(); break;
                case 82: player.Advance(0.1); break;
                case 84: player.Play(); player.CallbackModeProcess = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE; break;
                case 86: player.GetAnimation("walk").TrackSetEnabled(4, false); break;
                case 88: player.GetAnimation("walk").TrackSetEnabled(4, true); break;
                case 90: player.ProcessMode = ProcessModeEnum.Disabled; break;
                case 95: player.ProcessMode = ProcessModeEnum.Inherit; break;
                case 100: player.Stop(true); hasCur = false; break;
                case 102: player.PlayBackwards("hit"); hasCur = true; break;
                case 104: twist = new Twist { Name = "Twist" }; skel.AddChild(twist); break;
                case 108: twist.Influence = 0.6; break;
                case 112: player.Deterministic = true; break;
                case 116: player.Deterministic = false; break;
                case 124:
                    player.CallbackModeProcess = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS;
                    player.SpeedScale = 1.0f;
                    player.Play("idle", 0.2);
                    break;
                case 128: twist.QueueFree(); break;
                case 134: player.Stop(); hasCur = false; break;
            }
        }

        // ---------------------------------------------------------------- part 2: the real assets, from Godot's dump
        static void PrepareReal(Node root, string dumpPath)
        {
            var dump = GMarshal.BytesToVar(File.ReadAllBytes(dumpPath)).AsDict();
            var bones = dump["bones"].AsArr();
            var binds = dump["binds"].AsArr();
            var dlibs = dump["libs"].AsDict();
            var libs = new Dictionary<string, AnimationLibrary>();
            foreach (var key in new[] { "g", "mb" })
            {
                var lib = new AnimationLibrary();
                var data = new GDict();
                var d = dlibs[key].AsDict();
                foreach (var an in d.Keys()) data[an] = Var.Of(FromStored(d[an].AsDict()));
                lib.SetStoredProperty("_data", data);
                libs[key] = lib;
            }

            rbody = new Node3D { Name = "Knight" };
            var arm = new Node3D { Name = "Armature" };
            rbody.AddChild(arm);
            rskel = new Skeleton3D { Name = "Skeleton3D" };
            arm.AddChild(rskel);
            for (int i = 0; i < bones.Size(); i++) rskel.AddBone(bones[i].AsArr()[0].AsString());
            for (int i = 0; i < bones.Size(); i++)
            {
                var b = bones[i].AsArr();
                rskel.SetBoneParent(i, b[1].AsInt());
                rskel.SetBoneRest(i, AnimVar.ToXform3(b[2]));
            }
            rskel.ResetBonePoses();
            rskin = new Skin();
            for (int i = 0; i < binds.Size(); i++)
            {
                var b = binds[i].AsArr();
                if (b[0].AsString() != "") rskin.AddNamedBind(b[0].AsString(), AnimVar.ToXform3(b[2]));
                else rskin.AddBind(b[1].AsInt(), AnimVar.ToXform3(b[2]));
            }
            rplayer = new AnimationPlayer { Name = "AnimationPlayer" };
            rbody.AddChild(rplayer);
            rplayer.RootNode = "..";
            foreach (var key in new[] { "g", "mb" }) rplayer.AddAnimationLibrary(key, libs[key]);
            rplayer.CallbackModeProcess = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;
            rplayer.AnimationStarted += n => p("rsig|started", n);
            rplayer.AnimationFinished += n => p("rsig|finished", n);
            rplayer.AnimationChanged += (a, b) => p("rsig|changed", a + ">" + b);
            root.AddChild(rbody);
            p("real|bones", rskel.GetBoneCount());
            p("real|binds", rskin.GetBindCount());
            // part 1's animations rebuilt from their stored properties (value, method, scale, cubic tracks)
            var synth = dump["synth"].AsDict();
            foreach (var an in synth.Keys()) InterpDump("si|" + an.AsString(), FromStored(synth[an].AsDict()), SynTimes);
            double[] times = { 0.0, 0.0333, 0.1, 0.37, 0.5, 0.8, 1.0, 2.3 };
            foreach (var key in new[] { "g", "mb" })
            {
                var lib = libs[key];
                foreach (var an in lib.GetAnimationList())
                {
                    var anim = lib.GetAnimation(an);
                    p("real|" + key + "/" + an, GD.Str(anim.Length) + "|" + (int)anim.LoopMode + "|" + anim.GetTrackCount());
                    for (int i = 0; i < anim.GetTrackCount(); i += 3)
                    {
                        foreach (double tm in times)
                        {
                            string k = "ri|" + key + "/" + an + "|" + i + "|" + GD.Str(tm);
                            switch (anim.TrackGetType(i))
                            {
                                case Animation.TrackType.Position3D: p(k, anim.PositionTrackInterpolate(i, tm)); break;
                                case Animation.TrackType.Rotation3D: p(k, Var.Of(anim.RotationTrackInterpolate(i, tm))); break;
                                case Animation.TrackType.Scale3D: p(k, anim.ScaleTrackInterpolate(i, tm)); break;
                            }
                        }
                    }
                }
            }
        }

        static readonly double[] SynTimes = { -0.1, 0.0, 0.05, 0.1234, 0.25, 0.3, 0.5, 0.61, 0.79, 0.8, 0.95, 1.2, 1.37, 2.7 };

        /// <summary>An Animation from its stored properties, as the baked-asset loader builds one.</summary>
        static Animation FromStored(GDict props)
        {
            var anim = new Animation();
            foreach (var pn in props.Keys())
            {
                string name = pn.AsString();
                if (name == "resource_name") { anim.ResourceName = props[pn].AsString(); continue; }
                if (!anim.SetStoredProperty(name, props[pn])) Console.Error.WriteLine("unhandled stored property " + name);
            }
            return anim;
        }

        static void RealState()
        {
            string f = "r" + frame;
            p(f + "|cur", rplayer.CurrentAnimation + "|" + rplayer.AssignedAnimation + "|" + GD.Str(rplayer.IsPlaying()));
            if (rhas) p(f + "|pos", rplayer.CurrentAnimationPosition);
            foreach (var bn in new[] { "hips", "chest", "head", "wrist.r", "handslot.r", "foot.l" })
            {
                int bi = rskel.FindBone(bn);
                if (bi >= 0) p(f + "|" + bn, Var.Of(rskel.GetBoneGlobalPose(bi)));
            }
            var buf = new Xform3[rskin.GetBindCount()];
            rskel.GetSkinTransforms(rskin, buf);
            foreach (int b in new[] { 0, 5, 11 })
                if (b < rskin.GetBindCount()) p(f + "|skin" + b, Var.Of(buf[b]));
        }

        static void RealStep()
        {
            switch (frame)
            {
                case 142: rplayer.Play("g/Idle_A"); rhas = true; break;
                case 147: rplayer.Play("mb/Running_A", 0.1); rplayer.SpeedScale = 1.2f; rplayer.Advance(1.0 / 30.0); break;
                case 151: rplayer.Play("g/Hit_A", 0.1); rplayer.Queue("g/Idle_B"); rplayer.Advance(1.0 / 30.0); break;
                case 176: rplayer.Stop(true); rhas = false; break;
                case 177: rplayer.Play("mb/Walking_B", 0.2); rhas = true; rplayer.Advance(1.0 / 30.0); break;
                default: if (frame > 142) rplayer.Advance(1.0 / 30.0); break;
            }
        }

        public static void Run(string[] args)
        {
            string outDir = System.Environment.GetEnvironmentVariable("FB_ANIM_OUT");
            if (string.IsNullOrEmpty(outDir)) outDir = "/tmp/fb-anim";
            var tree = new SceneTree(new Vec2(760, 420));
            BuildScene(tree.Root);
            foreach (var an in player.GetAnimationList()) InterpDump("i|" + an, player.GetAnimation(an), SynTimes);
            PrepareReal(tree.Root, Path.Combine(outDir, "anim_dump.bin"));
            tree.ProcessFrame += () =>
            {
                if (frame < 140) { State(); Step(); }
                else if (frame >= 142) { RealState(); RealStep(); }
                frame++;
            };
            while (frame <= 186) tree.Iterate(1.0 / 60.0);
        }
    }
}
