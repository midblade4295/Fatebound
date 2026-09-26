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
 # Godot's Gradle AAB uses an install-time asset pack rather than the APK's
 # direct base assets. Find the exact game-relative asset in either layout.
 candidates=[n for n in names if n.endswith('/assets/data/v114-content.json')]
 assert len(candidates)==1,('Missing or duplicate content asset',candidates,[n for n in names if n.endswith(('.json','.pck'))])
 content_path=candidates[0]
 data=z.read(content_path); expected=Path('godot/data/v114-content.json').read_bytes()
 assert data==expected,'Native content tables changed or missing'
 content_module=content_path.split('/',1)[0]
 for script in ['full_client','game_api','progression','progress_store','solo_campaign','raid','arena_local','training','legacy_import','pages']:
  assert any('/'+script+'.' in n and '/assets/' in n for n in names),'Missing native runtime script '+script
 assert content_module in ['base','assetPackInstallTime'],('Unexpected game asset delivery module',content_module)
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
report={'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'upload_certificate_sha256':fp,'matches_previous_vc21_certificate':True,'native_content_tables_equal':True,'content_module':content_module,'content_asset_path':content_path,'test_and_signing_material_excluded':True,'native_64bit_libraries':libs,'physical_phone_tested':False}
p.with_name('PLAY_BUNDLE_VERIFICATION.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))

# Use Google's validator and inspect the actual protobuf manifest, not merely
# the intended export settings. Downloaded tool does not contain signing data.
import urllib.request,xml.etree.ElementTree as ET
jar=Path('/tmp/bundletool-all-1.18.3.jar')
if not jar.exists():
 urllib.request.urlretrieve('https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar',jar)
subprocess.run(['java','-jar',str(jar),'validate','--bundle='+str(p)],check=True)
manifest=subprocess.check_output(['java','-jar',str(jar),'dump','manifest','--bundle='+str(p),'--module=base'],text=True)
root=ET.fromstring(manifest);android='{http://schemas.android.com/apk/res/android}'
assert root.attrib['package']=='com.fatebound.game'
assert root.attrib[android+'versionCode']=='22'
assert root.attrib[android+'versionName']=='1.1.0'
sdk=root.find('uses-sdk');assert sdk.attrib[android+'minSdkVersion']=='24' and sdk.attrib[android+'targetSdkVersion']=='36'
application=root.find('application');assert application.attrib.get(android+'debuggable','false')=='false'
permissions=[item.attrib.get(android+'name') for item in root.findall('uses-permission')]
assert 'android.permission.INTERNET' in permissions
if content_module!='base':
 delivery=subprocess.check_output(['java','-jar',str(jar),'dump','manifest','--bundle='+str(p),'--module='+content_module],text=True)
 assert 'install-time' in delivery,('Game content not delivered at installation',delivery)
report.update(bundletool_validation_passed=True,package='com.fatebound.game',version_code=22,version_name='1.1.0',min_sdk=24,target_sdk=36,debuggable=False,game_assets_available_at_install=True)
p.with_name('PLAY_BUNDLE_VERIFICATION.json').write_text(json.dumps(report,indent=2)+'\n')
print('FINAL_VALIDATION',json.dumps(report,indent=2))
