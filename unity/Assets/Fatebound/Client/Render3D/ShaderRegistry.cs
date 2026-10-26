// Ported Godot shaders: a .gdshader at res://<path>.gdshader is the Unity shader "Fatebound/gd/<path>" (its file in
// Shaders/Resources/Shaders/gd/<path>.shader, so a build includes it). A shader made from code at run time
// (Shader.new() + code) is looked up by its code text, whitespace-normalised: the shader ports register those with
// RegisterInline. A ShaderMaterial's parameters start from the Unity shader's property defaults (its Properties block
// holds the uniforms' Godot defaults), its queue is the shader's own plus the material's render_priority.
using System.Collections.Generic;
using System.Text;
using UnityEngine;
using GShader = Fatebound.GUI.Shader;
using Material = UnityEngine.Material;
using Shader = UnityEngine.Shader;

namespace Fatebound.Client
{
    public static class ShaderRegistry
    {
        static readonly Dictionary<string, string> _inline = new Dictionary<string, string>();
        static readonly Dictionary<GShader, Shader> _resolved = new Dictionary<GShader, Shader>(ReferenceEqualityComparer<GShader>.Instance);
        static readonly Dictionary<Shader, Material> _defaults = new Dictionary<Shader, Material>();
        static readonly HashSet<string> _missing = new HashSet<string>();

        /// <summary>A shader the game builds from a code string: its Unity port.</summary>
        public static void RegisterInline(string godotCode, string unityShaderName) => _inline[Normalise(godotCode)] = unityShaderName;

        static string Normalise(string code)
        {
            var sb = new StringBuilder(code.Length);
            bool space = false;
            foreach (char c in code)
            {
                if (char.IsWhiteSpace(c)) { space = sb.Length > 0; continue; }
                if (space) { sb.Append(' '); space = false; }
                sb.Append(c);
            }
            return sb.ToString();
        }

        /// <summary>"res://shaders/a/b.gdshader" -> "shaders/a/b"</summary>
        public static string RelPath(string resPath)
        {
            var p = resPath;
            if (p.StartsWith("res://")) p = p.Substring(6);
            int dot = p.LastIndexOf('.');
            if (dot > p.LastIndexOf('/')) p = p.Substring(0, dot);
            return p;
        }

        public static Shader Find(GShader s)
        {
            if (s == null) return null;
            if (_resolved.TryGetValue(s, out var sh) && sh != null) return sh;
            string name = null, resource = null;
            if (!string.IsNullOrEmpty(s.ResourcePath))
            {
                var rel = RelPath(s.ResourcePath);
                name = "Fatebound/gd/" + rel;
                resource = "Shaders/gd/" + rel;
            }
            else if (!string.IsNullOrEmpty(s.Code) && _inline.TryGetValue(Normalise(s.Code), out var n)) name = n;
            if (name != null)
            {
                sh = Shader.Find(name);
                if (sh == null && resource != null) sh = Resources.Load<Shader>(resource);
            }
            if (sh == null)
            {
                string key = !string.IsNullOrEmpty(s.ResourcePath) ? s.ResourcePath : ("inline shader: " + (s.Code ?? "").Split('\n')[0]);
                if (_missing.Add(key)) Debug.LogWarning("Fatebound: no Unity port of " + key);
                return null;
            }
            _resolved[s] = sh;
            return sh;
        }

        /// <summary>Resets a material to its shader's defaults (parameters a ShaderMaterial dropped go back to them).</summary>
        public static void ApplyDefaults(Material m, GShader s)
        {
            var sh = m.shader;
            if (!_defaults.TryGetValue(sh, out var def))
            {
                def = new Material(sh) { hideFlags = HideFlags.DontSave };
                _defaults[sh] = def;
            }
            m.CopyPropertiesFromMaterial(def);
        }

        public static int Queue(Shader shader, int renderPriority)
        {
            int baseQueue = shader != null ? shader.renderQueue : 2000;
            return baseQueue + Mathf.Clamp(renderPriority, -50, 50);
        }
    }
}
