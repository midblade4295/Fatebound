#if FB3D
// Seams other parts of the 3D facade build on (partial: their full APIs live in their own files).
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public partial class Skeleton3D : Node3D
    {
        readonly List<MeshInstance3D> _skinned = new List<MeshInstance3D>();
        internal void RegisterSkinned(MeshInstance3D mi) { if (!_skinned.Contains(mi)) _skinned.Add(mi); }
        internal void UnregisterSkinned(MeshInstance3D mi) => _skinned.Remove(mi);
        /// <summary>The meshes skinned by this skeleton (the renderer poses their bones).</summary>
        public IReadOnlyList<MeshInstance3D> SkinnedMeshes => _skinned;
        /// <summary>Tells the renderer the bone pose changed (call after the pose is updated).</summary>
        protected void NotifySkinnedPoseChanged()
        {
            for (int i = 0; i < _skinned.Count; i++) _skinned[i].SkeletonPoseChanged();
        }
    }
}

#endif
