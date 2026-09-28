"""Fail-closed checks for the Siege Play AAB; never ship test, server or signing material."""
from pathlib import Path
import sys,zipfile,subprocess,re,hashlib,json,struct

def u32(data, offset):
 assert offset+4<=len(data),'Truncated Godot project setting'
 return struct.unpack_from('<I',data,offset)[0]

def packed_settings(data):
 assert data[:4]==b'ECFG' and len(data)>=8,'Invalid Godot project.binary header'
 props={};offset=8
 while offset<len(data):
  key_len=u32(data,offset);offset+=4
  assert offset+key_len<=len(data),'Truncated Godot project setting key'
  key=data[offset:offset+key_len].decode('utf-8');offset+=key_len
  value_len=u32(data,offset);offset+=4
  assert offset+value_len<=len(data) and key not in props,'Invalid Godot project setting value'
  props[key]=data[offset:offset+value_len];offset+=value_len
 return props

def string_setting(props,key):
 raw=props[key];assert len(raw)>=8 and u32(raw,0)==4,(key,'not a String')
 size=u32(raw,4);padded=(size+3)&~3
 assert len(raw)==8+padded and not any(raw[8+size:]),(key,'malformed String')
 return raw[8:8+size].decode('utf-8')

def bool_setting(props,key):
 raw=props[key];assert len(raw)==8 and u32(raw,0)==1,(key,'not a bool')
 value=u32(raw,4);assert value in (0,1),(key,'invalid bool')
 return bool(value)

p=Path(sys.argv[1]); assert p.exists() and p.stat().st_size>1_000_000
cert=subprocess.check_output(['keytool','-printcert','-jarfile',str(p)],text=True)
fp=re.search(r'SHA256:\s*([0-9A-F:]+)',cert)[1].replace(':','').lower()
assert fp=='6971a9123d610b397f6e9122c6cb241dbbe9c9c5fdbeb5a8751d5e2e80839084','Upload certificate does not match the existing Play bundle'
libs=[]
all_abis=set()
with zipfile.ZipFile(p) as z:
 assert z.testzip() is None
 names=z.namelist()
 assert 'BundleConfig.pb' in names and 'base/manifest/AndroidManifest.xml' in names
 assert 'base/dex/classes.dex' in names
 assert not any('/tests/' in n or '/reports/' in n or '/tools/' in n or '/server/' in n or n.endswith(('.keystore','.jks','.b64')) for n in names)
 assert not any(n.endswith('/index.html') or n.endswith('/fatebound.html') for n in names)
 # Godot's Gradle AAB uses an install-time asset pack rather than the APK's direct base
 # assets. Locate the game's module from its packed project settings (every export has one).
 project_paths=[n for n in names if n.endswith('/assets/project.binary')]
 assert len(project_paths)==1,('Missing or duplicate packed project settings',project_paths)
 content_module=project_paths[0].split('/',1)[0]
 assert content_module in ['base','assetPackInstallTime'],('Unexpected game asset delivery module',content_module)
 # The Siege-only app must be present; the removed dice-era app must not ship.
 for script in ['siege_app','screens','profile','economy','siege_mode','siege_sim','siege_view','siege_hud','siege_net']:
  assert any('/'+script+'.' in n and '/assets/' in n for n in names),'Missing Siege runtime script '+script
 for script in ['full_client','pages','progression','progress_store','solo_campaign','raid','arena_local','training','battlefield','dice_strip']:
  assert not any('/'+script+'.' in n and '/assets/' in n for n in names),'Removed dice-era script shipped: '+script
 props=packed_settings(z.read(project_paths[0]))
 assert string_setting(props,'rendering/renderer/rendering_method')=='mobile','Play bundle must render with Vulkan mobile'
 assert not bool_setting(props,'rendering/rendering_device/fallback_to_opengl3'),'OpenGL fallback must be disabled'
 for name in names:
  if not name.endswith('.so'):continue
  if '/lib/' in name:
   all_abis.add(name.split('/lib/',1)[1].split('/',1)[0])
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
 assert all_abis=={'armeabi-v7a','arm64-v8a','x86','x86_64'},('Missing Android ABI',sorted(all_abis))
 assert any('arm64-v8a' in x['path'] for x in libs)
 assert any('x86_64' in x['path'] for x in libs)
report={'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'upload_certificate_sha256':fp,'matches_existing_play_certificate':True,'siege_runtime_present_dice_era_absent':True,'content_module':content_module,'project_asset_path':project_paths[0],'vulkan_mobile_no_gl_fallback':True,'test_server_and_signing_material_excluded':True,'android_abis':sorted(all_abis),'native_64bit_libraries':libs,'physical_phone_tested':False}
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
assert root.attrib[android+'versionCode']=='24'
assert root.attrib[android+'versionName']=='1.2.0-siege-online'
sdk=root.find('uses-sdk');assert sdk.attrib[android+'minSdkVersion']=='24' and sdk.attrib[android+'targetSdkVersion']=='36'
application=root.find('application');assert application.attrib.get(android+'debuggable','false')=='false'
permissions=[item.attrib.get(android+'name') for item in root.findall('uses-permission')]
assert 'android.permission.INTERNET' in permissions
if content_module!='base':
 delivery=subprocess.check_output(['java','-jar',str(jar),'dump','manifest','--bundle='+str(p),'--module='+content_module],text=True)
 assert 'install-time' in delivery,('Game content not delivered at installation',delivery)
report.update(bundletool_validation_passed=True,package='com.fatebound.game',version_code=24,version_name='1.2.0-siege-online',min_sdk=24,target_sdk=36,debuggable=False,game_assets_available_at_install=True)
p.with_name('PLAY_BUNDLE_VERIFICATION.json').write_text(json.dumps(report,indent=2)+'\n')
print('FINAL_VALIDATION',json.dumps(report,indent=2))
