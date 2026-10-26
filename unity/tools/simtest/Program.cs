// Fatebound (Unity port): the simulation's tests and its parity with the Godot sim, without Unity.
//   dotnet run --project simtest -- rng            the RNG against Godot's (values printed by tools/godot_rng.gd)
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.SimTest
{
    public static class Program
    {
        public static int Main(string[] args)
        {
            string cmd = args.Length > 0 ? args[0] : "rng";
            switch (cmd)
            {
                case "rng": return RngCheck();
                case "trace": return Trace(args);
                default: Console.WriteLine("unknown: " + cmd); return 2;
            }
        }

        // The C# side of unity/tools/parity/godot_trace.gd: the same digest line per tick.
        static int Trace(string[] a)
        {
            long seed = a.Length > 1 ? long.Parse(a[1]) : 7;
            string hero = a.Length > 2 ? a[2] : "knight";
            if (hero == "-") hero = "";
            int ticks = a.Length > 3 ? int.Parse(a[3]) : 900;
            int dumpAt = a.Length > 4 ? int.Parse(a[4]) : -1;
            var s = new SiegeSim();
            s.Setup(5, seed);
            s.SetupMoba(hero, seed);
            Console.WriteLine("INIT " + Digest(s, false) + " " + s.units.Count + " walls=" + s.walls.Count + " fills=" + s.squeeze_fills);
            for (int tick = 1; tick <= ticks; tick++)
            {
                if (s.ended)
                {
                    Console.WriteLine("ENDED " + tick + " " + s.winner + " " + s.end_reason);
                    break;
                }
                s.Step(SiegeSim.TICK);
                var ev = s.DrainEvents();
                var ek = new List<string>();
                foreach (var e in ev) ek.Add(e.K);
                Console.WriteLine("T " + tick + " " + s.units.Count + " " + s.projectiles.Count + " " + Digest(s, tick == dumpAt) + " " + string.Join(",", ek));
            }
            return 0;
        }

        static string Hex32(params float[] v)
        {
            var sb = new System.Text.StringBuilder();
            foreach (var f in v) foreach (var b in BitConverter.GetBytes(f)) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }

        static string Hex64(params double[] v)
        {
            var sb = new System.Text.StringBuilder();
            foreach (var f in v) foreach (var b in BitConverter.GetBytes(f)) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }

        static string Digest(SiegeSim s, bool dump)
        {
            var parts = new List<string>();
            foreach (var u in s.units)
            {
                string line = u.id + "|" + u.state + "|" + Hex32(u.pos.x, u.pos.y, u.move.x, u.move.y) + "|"
                    + Hex64(u.hp, u.max_hp, u.face, u.t, u.cd_ability, u.stun, u.gold, u.xp);
                parts.Add(line);
                if (dump) Console.WriteLine("U " + line + " " + u.atk + " lvl=" + u.level + " hp=" + u.hp + " pos=" + u.pos);
            }
            foreach (var p in s.projectiles)
            {
                string pl = "P" + p.id + "|" + p.kind + "|" + Hex32(p.pos.x, p.pos.y);
                parts.Add(pl);
                if (dump) Console.WriteLine(pl);
            }
            using (var md5 = System.Security.Cryptography.MD5.Create())
            {
                var h = md5.ComputeHash(System.Text.Encoding.UTF8.GetBytes(string.Join("|", parts)));
                var sb = new System.Text.StringBuilder();
                foreach (var b in h) sb.Append(b.ToString("x2"));
                return sb.ToString().Substring(0, 12);
            }
        }

        static int RngCheck()
        {
            var r = new Rng();
            r.Seed = 4401;
            var parts = new List<string>();
            for (int i = 0; i < 5; i++) parts.Add(GD.FloatStr(r.Randf()));
            for (int i = 0; i < 5; i++) parts.Add(GD.FloatStr(r.RandfRange(-1.0, 1.0)));
            for (int i = 0; i < 5; i++) parts.Add(r.RandiRange(0, 9).ToString());
            parts.Add(GHash.Str("b3").ToString());
            parts.Add(GD.FloatStr(Vec2.FromAngle(1.234).x));
            parts.Add(GD.FloatStr(new Vec2(3.3f, 4.1f).Length()));
            Console.WriteLine("RNG " + string.Join(" ", parts));
            return 0;
        }
    }
}
