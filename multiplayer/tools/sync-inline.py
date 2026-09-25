#!/usr/bin/env python3
"""Maintain the shared v111 inline modules WITHOUT regenerating from an older game.
Default checks only. --write requires an explicit new build marker.
Run from the repository root with --root ., or from the standalone package.
"""
from pathlib import Path
import argparse,hashlib,json,re
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path.cwd());p.add_argument('--write',action='store_true');p.add_argument('--build-marker');a=p.parse_args()
root=a.root;module=root/'multiplayer' if (root/'multiplayer').exists() else root
html=root/'fatebound.html';text=html.read_text()
assert 'arenaEngineV109' in text, 'Refusing to modify a game without the installed arena integration'
changed=[]
for name,tag,path in [('arenaWireV113','script','src/arena-wire.js'),('arenaEngineV109','script','src/arena-engine.js'),('adventureClientV109','script','src/arena-client.js'),('adventureV109','style','src/adventure.css'),('soundDesignV111','script','src/game-audio.js'),('uiComfortV111','style','src/ui-comfort.css'),('uiComfortRuntimeV111','script','src/ui-comfort.js')]:
 pattern=rf'(<{tag} id="{name}">)(.*?)(</{tag}>)';matches=list(re.finditer(pattern,text,re.S));assert len(matches)==1,name
 content=(module/path).read_text();m=matches[0]
 if m[2]!=content:changed.append(path);text=text[:m.start(2)]+content+text[m.end(2):]
if not a.write:
 assert not changed,'Inline modules are out of sync: '+', '.join(changed)
 print('Shared engine/client/CSS match the current HTML');raise SystemExit(0)
assert a.build_marker and re.fullmatch(r'\d+-[a-z0-9-]+',a.build_marker),'Use --write --build-marker <version-description>'
text,n=re.subn(r'(<meta name="fatebound-build" content=")[^"]+(">)',lambda m:m[1]+a.build_marker+m[2],text,count=1);assert n==1
html.write_text(text)
data=html.read_bytes();digest=hashlib.sha256(data).hexdigest();(root/'fatebound-source.sha256').write_text(digest+'  fatebound.html\n')
manifest=root/'fatebound-source.json'
if manifest.exists():
 obj=json.loads(manifest.read_text());obj.update(html_version=int(a.build_marker.split('-')[0]),build_marker=a.build_marker,bytes=len(data),sha256=digest,git_blob_sha1=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest());manifest.write_text(json.dumps(obj,indent=2)+'\n')
print('Updated only current inline modules; runtime tests still required. SHA256:',digest)
