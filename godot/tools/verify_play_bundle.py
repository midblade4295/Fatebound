"""Artifact-level checks. Never export debug material, tests, or signing keys."""
from pathlib import Path
import sys,zipfile,subprocess,re,hashlib,json,struct
p=Path(sys.argv[1]); assert p.exists() and p.stat().st_size>1_000_000
cert=subprocess.check_output(['keytool','-printcert','-jarfile',str(p)],text=True)
fp=re.search(r'SHA256:\s*([0-9A-F:]+)',cert)[1].replace(':','').lower()
assert fp=='6971a9123d610b397f6e9122c6cb241dbbe9c9c5fdbeb5a8751d5e2e80839084','Upload certificate does not match the existing vc21 bundle'
libs=[]
with zipfile.ZipFile(p) as z:
 assert z.testzip() is None
 names=z.namelist()
 assert 'BundleConfig.pb' in names and 'base/manifest/AndroidManifest.xml' in names
 assert 'base/dex/classes.dex' in names
 assert not any('/tests/' in n or '/reports/' in n or '/tools/' in n or n.endswith(('.keystore','.jks','.b64')) for n in names)
 assert not any(n.endswith('/index.html') or n.endswith('/fatebound.html') for n in names)
 data=z.read('base/assets/data/v114-content.json'); expected=Path('godot/data/v114-content.json').read_bytes()
 assert data==expected,'Native content tables changed or missing'
 for name in names:
  if not name.endswith('.so'):continue
  b=z.read(name); assert b[:4]==b'\x7fELF'
  if b[4]!=2:continue
  endian='<' if b[5]==1 else '>'
  off=struct.unpack_from(endian+'Q',b,32)[0]; ent,num=struct.unpack_from(endian+'HH',b,54)
  align=[]
  for i in range(num):
   pos=off+i*ent
   if struct.unpack_from(endian+'I',b,pos)[0]==1:
    value=struct.unpack_from(endian+'Q',b,pos+48)[0]; assert value>=16384,(name,value);align.append(value)
  libs.append({'path':name,'load_segment_alignment':align})
 assert any('arm64-v8a' in x['path'] for x in libs)
report={'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'upload_certificate_sha256':fp,'matches_previous_vc21_certificate':True,'native_content_tables_equal':True,'test_and_signing_material_excluded':True,'native_64bit_libraries':libs,'physical_phone_tested':False}
p.with_name('PLAY_BUNDLE_VERIFICATION.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
