// Facade additions for the app shell's port (app/content_loader.gd, app/boot_guard.gd):
//  - ResourceUID's text_to_id / has_id / add_id / INVALID_ID (core/io/resource_uid.cpp: "uid://" + base-34 digits,
//    a-z then 0-9, masked to 63 bits; the id -> path table the packs' UIDs are registered in)
//  - RenderingServer.get_current_rendering_method() (OS::get_current_rendering_method: the method the app started with,
//    from project.godot's rendering/renderer/rendering_method -- "mobile")
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public static partial class ResourceUID
    {
        public const long INVALID_ID = -1;
        const uint CHAR_COUNT = 'z' - 'a';
        const uint BASE = CHAR_COUNT + ('9' - '0');
        static readonly Dictionary<long, string> _ids = new Dictionary<long, string>();

        public static long TextToId(string text)
        {
            if (text == null || !text.StartsWith("uid://", System.StringComparison.Ordinal) || text == "uid://<invalid>")
                return INVALID_ID;
            ulong uid = 0;
            for (int i = 6; i < text.Length; i++)
            {
                unchecked { uid *= BASE; }
                char c = text[i];
                if (c >= 'a' && c <= 'z') unchecked { uid += (ulong)(c - 'a'); }
                else if (c >= '0' && c <= '9') unchecked { uid += (ulong)(c - '0') + CHAR_COUNT; }
                else return INVALID_ID;
            }
            return (long)(uid & 0x7FFFFFFFFFFFFFFFUL);
        }

        public static bool HasId(long id)
        {
            lock (_ids) return _ids.ContainsKey(id);
        }

        public static void AddId(long id, string path)
        {
            lock (_ids)
            {
                if (_ids.ContainsKey(id)) { GD.PushError("ResourceUID: id " + id + " is already registered."); return; }
                _ids[id] = path;
            }
        }

        public static void SetId(long id, string path)
        {
            lock (_ids) _ids[id] = path;
        }

        public static string GetIdPath(long id)
        {
            lock (_ids) return _ids.TryGetValue(id, out var p) ? p : "";
        }
    }

    public static partial class RenderingServer
    {
        public static string GetCurrentRenderingMethod() =>
            ProjectSettings.GetSetting("rendering/renderer/rendering_method", "mobile").AsString();
    }
}
