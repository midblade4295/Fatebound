// Facade addition (the meta/ porter, Fatebound Unity port): Godot's Object.call / connect / has_method / has_signal /
// get / set by NAME, for the objects the game only ever reaches by name -- an engine plugin's singleton
// (Engine.get_singleton: "GodotGooglePlayBilling", "GodotPlayGameServices", "FateboundNotify"), a ClassDB instance
// (GodotApplePlugins' GameCenterManager / StoreKitManager, FateboundNotifyIOS) and the objects those hand back (a
// StoreKit transaction or product, GKLocalPlayer, GKAchievement). In GDScript those are untyped (`plugin.signIn()`,
// `plugin.userAuthenticated.connect(f)`, `txn.product_id`); the port writes them GObject.Call(plugin, "signIn"),
// GObject.Connect(plugin, "userAuthenticated", f), GObject.Get(txn, "product_id").
//
// The Unity client's plugin stand-ins (registered with Engine.RegisterSingleton / ClassDB.Register) implement
// IGodotDynamic with the plugin's own names -- the Java/Swift method names ("setAchievementSteps", "queryPurchases"),
// signal names ("userAuthenticated", "purchase_completed") and properties ("product_id", "local_player") -- and call a
// connected callable back with GObject.Invoke(callable, args...). Any other object (a C# class of the port) is reached
// by reflection: the member named as given, or PascalCased as the port names members; a signal is a C# event.
// What Godot does when the name isn't there: call -> an error and null; connect -> an error, ERR_INVALID_PARAMETER;
// get -> null (no error); set -> nothing.
using System;
using System.Collections.Generic;
using System.Reflection;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    /// <summary>An object reached by name (a plugin stand-in): Godot's Object.call / connect / get / set.</summary>
    public interface IGodotDynamic
    {
        bool HasMethod(string method);
        /// <summary>call(method, args...): the method's return value (Nil for void).</summary>
        Var Call(string method, Var[] args);
        bool HasSignal(string signal);
        /// <summary>connect(signal, callable): the callable is invoked with the signal's arguments through
        /// GObject.Invoke (Vars converted to its parameter types). An Error code.</summary>
        int Connect(string signal, Delegate callable);
        void Disconnect(string signal, Delegate callable);
        /// <summary>get(property): Nil when there's no such property.</summary>
        Var Get(string property);
        void Set(string property, Var value);
    }

    /// <summary>Object.call / connect / get / set by name on any object (an IGodotDynamic, or a C# object by reflection).</summary>
    public static class GObject
    {
        const BindingFlags F = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.FlattenHierarchy;

        static object Unwrap(object o) => o is Var v ? v.Obj : o;

        // ------------------------------------------------------------------ call
        public static bool HasMethod(object o, string method)
        {
            o = Unwrap(o);
            if (o == null) return false;
            if (o is IGodotDynamic g) return g.HasMethod(method);
            return FindMethod(o.GetType(), method, -1) != null;
        }

        /// <summary>obj.method(args...) / obj.call("method", args...).</summary>
        public static Var Call(object o, string method, params Var[] args)
        {
            o = Unwrap(o);
            if (o == null || (o is IGodotObject go && go.IsFreed))
            {
                GD.PushError("Attempt to call function '" + method + "' in base 'previously freed' or 'null instance'.");
                return Var.Nil;
            }
            if (o is IGodotDynamic g) return g.Call(method, args ?? Array.Empty<Var>());
            args = args ?? Array.Empty<Var>();
            var mi = FindMethod(o.GetType(), method, args.Length);
            if (mi == null)
            {
                GD.PushError("Invalid call. Nonexistent function '" + method + "' in base '" + o.GetType().Name + "'.");
                return Var.Nil;
            }
            var ps = mi.GetParameters();
            var a = new object[ps.Length];
            for (int i = 0; i < ps.Length; i++)
                a[i] = i < args.Length ? To(args[i], ps[i].ParameterType) : ps[i].DefaultValue;
            object r;
            try { r = mi.Invoke(o, a); }
            catch (TargetInvocationException e) { throw e.InnerException ?? e; }
            return mi.ReturnType == typeof(void) ? Var.Nil : Var.Of(r);
        }

        static readonly Dictionary<(Type, string, int), MethodInfo> _methods = new Dictionary<(Type, string, int), MethodInfo>();

        static MethodInfo FindMethod(Type t, string name, int argc)
        {
            lock (_methods)
            {
                if (_methods.TryGetValue((t, name, argc), out var m)) return m;
                foreach (var cand in new[] { name, PropertyPath.Pascal(name) })
                {
                    foreach (var mi in t.GetMethods(F))
                    {
                        if (mi.Name != cand || mi.IsSpecialName) continue;
                        var ps = mi.GetParameters();
                        int required = 0;
                        foreach (var p in ps) if (!p.IsOptional) required++;
                        if (argc < 0 || (argc >= required && argc <= ps.Length)) { m = mi; break; }
                    }
                    if (m != null) break;
                }
                _methods[(t, name, argc)] = m;
                return m;
            }
        }

        // ------------------------------------------------------------------ signals
        public static bool HasSignal(object o, string signal)
        {
            o = Unwrap(o);
            if (o == null) return false;
            if (o is IGodotDynamic g) return g.HasSignal(signal);
            return FindEvent(o.GetType(), signal) != null;
        }

        /// <summary>obj.signal.connect(callable) / obj.connect("signal", callable): an Error code.</summary>
        public static int Connect(object o, string signal, Delegate callable)
        {
            o = Unwrap(o);
            if (o == null)
            {
                GD.PushError("Cannot connect to '" + signal + "': the instance is null.");
                return GD.ERR_INVALID_PARAMETER;
            }
            if (callable == null)
            {
                GD.PushError("Cannot connect to '" + signal + "': the callable is null.");
                return GD.ERR_INVALID_PARAMETER;
            }
            if (o is IGodotDynamic g) return g.Connect(signal, callable);
            var ev = FindEvent(o.GetType(), signal);
            if (ev == null)
            {
                GD.PushError("In Object of type '" + o.GetType().Name + "': Attempt to connect nonexistent signal '" + signal + "' to callable.");
                return GD.ERR_INVALID_PARAMETER;
            }
            var h = Adapt(callable, ev.EventHandlerType);
            if (h == null)
            {
                GD.PushError("Cannot connect to '" + signal + "': the callable's arguments don't match the signal's.");
                return GD.ERR_INVALID_PARAMETER;
            }
            ev.AddEventHandler(o, h);
            return GD.OK;
        }

        public static void Disconnect(object o, string signal, Delegate callable)
        {
            o = Unwrap(o);
            if (o == null || callable == null) return;
            if (o is IGodotDynamic g) { g.Disconnect(signal, callable); return; }
            var ev = FindEvent(o.GetType(), signal);
            var h = ev == null ? null : Adapt(callable, ev.EventHandlerType);
            if (h != null) ev.RemoveEventHandler(o, h);
        }

        static Delegate Adapt(Delegate f, Type t)
        {
            if (t.IsInstanceOfType(f)) return f;
            try { return Delegate.CreateDelegate(t, f.Target, f.Method, false); }
            catch (Exception) { return null; }
        }

        static EventInfo FindEvent(Type t, string name) => t.GetEvent(name, F) ?? t.GetEvent(PropertyPath.Pascal(name), F);

        /// <summary>A connected callable called with Var arguments (what a stand-in's signal emits, or a callable passed
        /// to it as an argument): each argument converted to the callable's parameter type -- Var as it is; int, long,
        /// float, double, bool, string as GDScript's constructors convert; GDict / GArray / byte[] / objects as held.
        /// A different number of arguments is an error, as in Godot.</summary>
        public static Var Invoke(Delegate f, params Var[] args)
        {
            if (f == null) { GD.PushError("Attempt to call an invalid Callable."); return Var.Nil; }
            args = args ?? Array.Empty<Var>();
            var ps = f.Method.GetParameters();
            // (a closure compiled as a static method with its closure as the first parameter still reports its own ones)
            if (ps.Length != args.Length)
            {
                GD.PushError("Error calling a callable: expected " + ps.Length + " arguments, but called with " + args.Length + ".");
                return Var.Nil;
            }
            var a = new object[ps.Length];
            for (int i = 0; i < ps.Length; i++) a[i] = To(args[i], ps[i].ParameterType);
            object r;
            try { r = f.DynamicInvoke(a); }
            catch (TargetInvocationException e) { throw e.InnerException ?? e; }
            return f.Method.ReturnType == typeof(void) ? Var.Nil : Var.Of(r);
        }

        /// <summary>A Var as a C# parameter type.</summary>
        public static object To(Var v, Type t)
        {
            if (t == typeof(Var)) return v;
            if (t == typeof(int)) return v.AsInt();
            if (t == typeof(long)) return v.AsLong();
            if (t == typeof(double)) return v.AsFloat();
            if (t == typeof(float)) return (float)v.AsFloat();
            if (t == typeof(bool)) return v.Truthy;
            if (t == typeof(string)) return v.AsString();
            if (t == typeof(GDict)) return v.AsDict();
            if (t == typeof(GArray)) return v.AsArr();
            if (t == typeof(Vec2)) return v.AsVec2();
            if (t == typeof(Vec3)) return v.AsVec3();
            if (t == typeof(string[]) && v.IsArr) return v.A.ToStrings().ToArray();
            object o = v.Obj;
            if (o == null) return t.IsValueType ? Activator.CreateInstance(t) : null;
            if (t.IsInstanceOfType(o)) return o;
            if (t.IsEnum) return Enum.ToObject(t, v.AsLong());
            return t.IsValueType ? Activator.CreateInstance(t) : null;
        }

        // ------------------------------------------------------------------ properties
        /// <summary>obj.property / obj.get("property"): Nil when there's no such property.</summary>
        public static Var Get(object o, string property)
        {
            o = Unwrap(o);
            if (o == null) return Var.Nil;
            if (o is IGodotDynamic g) return g.Get(property);
            if (o is GDict d) return d.Get(property);
            try { return Var.Of(PropertyPath.Get(o, property)); }
            catch (MissingMemberException) { return Var.Nil; }
        }

        /// <summary>obj.property = value / obj.set("property", value).</summary>
        public static void Set(object o, string property, Var value)
        {
            o = Unwrap(o);
            if (o == null) return;
            if (o is IGodotDynamic g) { g.Set(property, value); return; }
            if (o is GDict d) { d[property] = value; return; }
            try { PropertyPath.Set(o, property, value.Obj); }
            catch (MissingMemberException) { }
        }
    }
}
