#!/usr/bin/env python3
"""Reproduce the native preview assets from the pinned, full v114 HTML.
No external artwork is downloaded, no model is regenerated, and no gameplay file
is rewritten. Run from the repository root with --godot /path/to/godot.
"""
from pathlib import Path
import argparse,base64,hashlib,json,re,subprocess
p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--root',default='.');args=p.parse_args()
root=Path(args.root).resolve();project=root/'godot';dest=project/'assets/art';dest.mkdir(parents=True,exist_ok=True)
html=(root/'fatebound.html').read_bytes();expected='84697859827127e8c9285b0cf57578a8fc2bcedcb3cf8d3247772f0309f3b4e9'
assert hashlib.sha256(html).hexdigest()==expected,'Not the approved v114 artwork source'
s=html.decode();originals={}
def save(name,uri):
    typ,b64=uri.split(';base64,');suffix=typ.split('/')[-1]
    assert suffix in ['png','jpeg','webp']
    blob=base64.b64decode(b64,validate=True);filename=name+'.'+suffix
    (dest/filename).write_bytes(blob)
    originals[filename]={'bytes':len(blob),'sha256':hashlib.sha256(blob).hexdigest()}
for key in ['MAP','PANO']:
    m=re.search(r'\b'+key+r'\.src\s*=\s*[\"\'](data:image/[^\"\']+)[\"\']',s);assert m
    save(key.lower(),m[1])
m=re.search(r'const SPR = \{\}; Object.entries\((\{.*?\})\)',s);assert m
for name,b64 in json.loads(m[1]).items():save(name,'data:image/png;base64,'+b64)
m=re.search(r'const COMBAT_HD_DATA = (\[.*?\]);',s);assert m
rows=json.loads(m[1]);assert len(rows)==45
for i,uri in enumerate(rows):save('row_%02d'%i,uri)
subprocess.run([args.godot,'--headless','--path',str(project),'--script','res://tools/split_atlases.gd'],check=True)
files={f.name:{'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted(dest.iterdir()) if f.suffix in ['png','jpeg','webp']}
manifest={'source_sha256':expected,'cell':[340,280],'frames_per_row':26,'hero_weapon_rows':45,'originals':originals,'native_files':files,'credit':'Source credits: KayKit Adventurers 2.0, Character Animations 1.1, Medieval Hexagon Pack; Kay Lousberg; CC0. Reuses the approved v114 baked artwork, not new models. Native animation strips are pixel-identical lossless crops.'}
(dest/'provenance.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Imported',len(files),'native assets; source HTML unchanged')
