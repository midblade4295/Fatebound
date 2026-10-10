# Bounds of a glTF/GLB model in its own space (node transforms applied). Used by meshy_weapon.py fit.
import json, struct, sys, os
import numpy as np
def load(path):
    if path.endswith('.glb'):
        b=open(path,'rb').read(); jl=struct.unpack_from('<I',b,12)[0]; g=json.loads(b[20:20+jl])
        bl=struct.unpack_from('<I',b,20+jl)[0]; bins=[b[28+jl:28+jl+bl]]
    else:
        g=json.load(open(path)); d=os.path.dirname(path); bins=[open(os.path.join(d,bf['uri']),'rb').read() for bf in g['buffers']]
    return g,bins
def acc(g,bins,i):
    a=g['accessors'][i]; bv=g['bufferViews'][a['bufferView']]
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    dt={5126:np.float32,5123:np.uint16,5125:np.uint32,5121:np.uint8}[a['componentType']]
    off=bv.get('byteOffset',0)+a.get('byteOffset',0); st=bv.get('byteStride',0)
    buf=bins[bv.get('buffer',0)]
    if st and st!=n*np.dtype(dt).itemsize:
        rows=[np.frombuffer(buf,dt,n,off+k*st) for k in range(a['count'])]; return np.array(rows)
    return np.frombuffer(buf,dt,a['count']*n,off).reshape(-1,n) if n>1 else np.frombuffer(buf,dt,a['count'],off)
def mat(node):
    if 'matrix' in node: return np.array(node['matrix']).reshape(4,4).T
    T=np.eye(4); t=node.get('translation',[0,0,0]); r=node.get('rotation',[0,0,0,1]); s=node.get('scale',[1,1,1])
    x,y,z,w=r; R=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
    T[:3,:3]=R*np.array(s); T[:3,3]=t; return T
def points(path):
    g,bins=load(path); out=[]
    def walk(ni,M):
        n=g['nodes'][ni]; M2=M@mat(n)
        if 'mesh' in n:
            for p in g['meshes'][n['mesh']]['primitives']:
                v=acc(g,bins,p['attributes']['POSITION']).astype(np.float64)
                out.append((M2[:3,:3]@v.T).T+M2[:3,3])
        for c in n.get('children',[]): walk(c,M2)
    sc=g['scenes'][g.get('scene',0)]
    for r in sc['nodes']: walk(r,np.eye(4))
    return np.vstack(out)
def surface(path, n=5000, seed=1):
    # n points spread evenly over the model's triangles (by area): a fair shape sample whatever the mesh density
    g,bins=load(path); tris=[]
    def walk(ni,M):
        nd=g['nodes'][ni]; M2=M@mat(nd)
        if 'mesh' in nd:
            for p in g['meshes'][nd['mesh']]['primitives']:
                v=acc(g,bins,p['attributes']['POSITION']).astype(np.float64)
                v=(M2[:3,:3]@v.T).T+M2[:3,3]
                idx=acc(g,bins,p['indices']).astype(np.int64).reshape(-1,3) if 'indices' in p else np.arange(len(v)).reshape(-1,3)
                tris.append(v[idx])
        for c in nd.get('children',[]): walk(c,M2)
    sc=g['scenes'][g.get('scene',0)]
    for r in sc['nodes']: walk(r,np.eye(4))
    T=np.vstack(tris); a=np.linalg.norm(np.cross(T[:,1]-T[:,0],T[:,2]-T[:,0]),axis=1)*0.5
    rng=np.random.default_rng(seed); k=rng.choice(len(T),n,p=a/a.sum())
    u=rng.random((n,2)); m=u.sum(1)>1; u[m]=1-u[m]
    t=T[k]; return t[:,0]+u[:,:1]*(t[:,1]-t[:,0])+u[:,1:]*(t[:,2]-t[:,0])
if __name__=='__main__':
    for p in sys.argv[1:]:
        v=points(p); lo=v.min(0); hi=v.max(0)
        print(os.path.basename(p), 'min',np.round(lo,3),'max',np.round(hi,3),'size',np.round(hi-lo,3),'verts',len(v))
