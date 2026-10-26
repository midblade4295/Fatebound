// Added for the app/ UI port (title_logo.gd: m.set_meta("phase", ...) on a ShaderMaterial): Object's metadata on a
// Resource, as Node has it (object.cpp set_meta / get_meta / has_meta / remove_meta: a null value removes the key).
using System.Collections.Generic;

namespace Fatebound.GUI
{
    public partial class Resource
    {
        Dictionary<string, object> _resMeta;

        public void SetMeta(string key, object value)
        {
            if (value == null || (value is Fatebound.Sim.Var v && v.IsNil)) { _resMeta?.Remove(key); return; }
            (_resMeta ??= new Dictionary<string, object>())[key] = value;
        }

        public object GetMeta(string key, object dflt = null) => _resMeta != null && _resMeta.TryGetValue(key, out var v) ? v : dflt;
        public bool HasMeta(string key) => _resMeta != null && _resMeta.ContainsKey(key);
        public void RemoveMeta(string key) => _resMeta?.Remove(key);
    }
}
