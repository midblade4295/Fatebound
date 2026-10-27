// Facade addition for the siege fx port (siege_view.gd's _drop_weapons copies each held weapon into a rigid body):
// Node.duplicate(flags). As Godot's Node::_duplicate: a new node of the same class, its stored properties copied
// (resources shared, not copied), its name, groups and children (each duplicated the same way; internal children are
// the node's own and are left to it). What it copies here:
//  - Node: name, process_mode, process_priority, groups; Node3D: transform, rotation edit mode and order, top_level,
//    visible (Godot stores transform, not position / rotation / scale, which are views of it);
//  - every other facade class between Node3D (or Node, for nodes that aren't 3D) and the node's class: its public
//    writable properties and fields, base class first, in declaration order (Godot's property list order), with the
//    per-surface materials and instance shader parameters of GeometryInstance3D / MeshInstance3D, which aren't
//    properties here. Global* views (they need the tree) and the renderer's BackendData are not copied.
//  - Game subclasses' own fields are not copied: GDScript's duplicate() skips script variables that aren't @export
//    (the game exports none).
// Signal connections aren't copied (C# events), nor DUPLICATE_USE_INSTANTIATION's re-instancing of scene children
// (the copy is the same nodes either way).
using System;
using System.Collections.Generic;
using System.Reflection;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial class Node
    {
        public const int DUPLICATE_SIGNALS = 1, DUPLICATE_GROUPS = 2, DUPLICATE_SCRIPTS = 4, DUPLICATE_USE_INSTANTIATION = 8;

        public Node Duplicate(int flags = DUPLICATE_SIGNALS | DUPLICATE_GROUPS | DUPLICATE_SCRIPTS | DUPLICATE_USE_INSTANTIATION)
        {
            Node n;
            try { n = (Node)Activator.CreateInstance(GetType()); }
            catch (Exception ex)
            {
                GD.PushError("Node.duplicate: can't make a " + GetType().Name + " (" + ex.Message + ")");
                return null;
            }
            n.Name = Name;
            n.ProcessMode = ProcessMode;
            n.ProcessPriority = ProcessPriority;
            if ((flags & DUPLICATE_GROUPS) != 0 && _groups != null)
                foreach (var g in _groups) n.AddToGroup(g);
            DuplicateCopy.Copy(this, n);
            foreach (var c in GetChildren())
            {
                var d = c.Duplicate(flags);
                if (d != null) n.AddChild(d);
            }
            return n;
        }
    }

    static class DuplicateCopy
    {
        static readonly Dictionary<Type, Action<object, object>[]> _ops = new Dictionary<Type, Action<object, object>[]>();
        static readonly HashSet<string> _skip = new HashSet<string> { "BackendData", "Owner", "Name" };

        public static void Copy(Node src, Node dst)
        {
            if (src is Node3D a && dst is Node3D b)
            {
                b.RotationEditMode = a.RotationEditMode;
                b.RotationOrder = a.RotationOrder;
                b.TopLevel = a.TopLevel;
                b.DisableScale = a.DisableScale;
                b.Transform = a.Transform;
                b.Visible = a.Visible;
            }
            foreach (var op in Ops(src.GetType())) op(src, dst);
            if (src is GeometryInstance3D gs && dst is GeometryInstance3D gd)
                foreach (var kv in gs.InstanceShaderParameters) gd.SetInstanceShaderParameter(kv.Key, kv.Value);
            if (src is MeshInstance3D ms && dst is MeshInstance3D md)
                for (int i = 0; i < ms.GetSurfaceOverrideMaterialCount(); i++)
                    if (ms.GetSurfaceOverrideMaterial(i) != null) md.SetSurfaceOverrideMaterial(i, ms.GetSurfaceOverrideMaterial(i));
        }

        static Action<object, object>[] Ops(Type t)
        {
            lock (_ops)
            {
                if (_ops.TryGetValue(t, out var ops)) return ops;
                var asm = typeof(Node).Assembly;
                var chain = new List<Type>();
                // the facade's classes below the node's own class, down to (not including) Node3D / Node
                for (var c = t; c != null && c != typeof(Node3D) && c != typeof(Node); c = c.BaseType)
                    if (c.Assembly == asm) chain.Add(c);
                chain.Reverse();
                var list = new List<Action<object, object>>();
                const BindingFlags F = BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly;
                foreach (var c in chain)
                {
                    foreach (var m in c.GetMembers(F))
                    {
                        if (_skip.Contains(m.Name) || m.Name.StartsWith("Global", StringComparison.Ordinal)) continue;
                        if (m is PropertyInfo p)
                        {
                            if (!p.CanRead || !p.CanWrite || p.GetIndexParameters().Length > 0) continue;
                            if (p.GetSetMethod() == null || p.GetGetMethod() == null) continue;
                            if (typeof(Node).IsAssignableFrom(p.PropertyType) || typeof(Delegate).IsAssignableFrom(p.PropertyType)) continue;
                            list.Add((s, d) => Set(p.Name, () => p.SetValue(d, p.GetValue(s))));
                        }
                        else if (m is FieldInfo f)
                        {
                            if (f.IsInitOnly || f.IsLiteral) continue;
                            if (typeof(Node).IsAssignableFrom(f.FieldType) || typeof(Delegate).IsAssignableFrom(f.FieldType)) continue;
                            list.Add((s, d) => f.SetValue(d, f.GetValue(s)));
                        }
                    }
                }
                ops = list.ToArray();
                _ops[t] = ops;
                return ops;
            }
        }

        static readonly HashSet<string> _warned = new HashSet<string>();

        static void Set(string name, Action set)
        {
            try { set(); }
            catch (Exception ex)
            {
                var inner = ex is TargetInvocationException tie && tie.InnerException != null ? tie.InnerException : ex;
                lock (_warned)
                    if (_warned.Add(name)) GD.PushWarning("Node.duplicate: " + name + " not copied (" + inner.Message + ")");
            }
        }
    }
}
