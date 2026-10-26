// Facade addition (the siege fx port: weapon_fx.gd keys its glow materials by "%d" % texture.get_instance_id() and
// "%d" % material.get_instance_id()): Object.get_instance_id() on a Resource. Godot gives every Object a unique id for
// its lifetime; here each Resource gets one the first time it's asked, from its own counter (kept clear of the Nodes'
// ids, which count up from 1), held by reference -- so a Duplicate() (a MemberwiseClone) gets a new id of its own, as
// a duplicated resource does in Godot.
using System.Runtime.CompilerServices;
using System.Threading;

namespace Fatebound.GUI
{
    public partial class Resource
    {
        static readonly ConditionalWeakTable<Resource, object> _objectIds = new ConditionalWeakTable<Resource, object>();
        static long _nextObjectId = 1L << 40;

        /// <summary>get_instance_id(): unique among the Resources alive, stable for this one's lifetime.</summary>
        public ulong GetInstanceId() =>
            (ulong)(long)_objectIds.GetValue(this, _ => Interlocked.Increment(ref _nextObjectId));
    }
}
