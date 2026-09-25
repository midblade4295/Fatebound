"""Isolated legacy-web security/compatibility checks; never reads live saves."""
import importlib.util,json,tempfile,threading,unittest,urllib.request,urllib.error
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
spec=importlib.util.spec_from_file_location('host',Path(__file__).resolve().parents[2]/'server/fatebound_host.py')
host=importlib.util.module_from_spec(spec);spec.loader.exec_module(host)
class WebTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();p=Path(self.tmp.name)
  (p/'fatebound.html').write_text('<head></head><body>Game</body>')
  (p/'fatebound-client.js').write_text('//client')
  (p/'saves').mkdir();(p/'saves/SECRET.json').write_text('{"save":{}}')
  (p/'server').mkdir();(p/'server/fatebound_host.py').write_text('private source')
  (p/'fatebound-host.log').write_text('private log')
  class H(host.Handler):pass
  H.root=p;H.saves_dir=p/'saves';H.html_cache=None
  H.log_message=lambda *args:None
  self.server=host.Server(('127.0.0.1',0),H);self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
  self.base='http://127.0.0.1:'+str(self.server.server_port);self.root=p
 def tearDown(self):self.server.shutdown();self.server.server_close();self.thread.join();self.tmp.cleanup()
 def req(self,path,body=None,method=None,headers=None):
  data=None if body is None else json.dumps(body).encode()
  request=urllib.request.Request(self.base+path,data=data,method=method,headers=headers or {})
  try:r=urllib.request.urlopen(request,timeout=3)
  except urllib.error.HTTPError as e:r=e
  return r.status,r.read(),r.headers
 def test_hidden_folders_get_and_head(self):
  for path in ['/saves/','/saves/SECRET.json','/server/fatebound_host.py','/fatebound-host.log','/android/keystore/upload.jks.b64','/../saves/SECRET.json','/%73aves/SECRET.json','/%2e%2e/saves/SECRET.json','/.git/config','/sync-fatebound.sh']:
   for method in ['GET','HEAD']:self.assertEqual(self.req(path,method=method)[0],404,(path,method))
 def test_public_game_client_and_health(self):
  status,body,_=self.req('/');self.assertEqual(status,200);self.assertIn(b'fatebound-client.js',body)
  self.assertEqual(self.req('/fatebound-client.js')[0],200);self.assertEqual(json.loads(self.req('/health')[1])['webBuild'],113)
 def test_head_does_not_send_body(self):
  status,body,h=self.req('/',method='HEAD');self.assertEqual(status,200);self.assertEqual(body,b'');self.assertGreater(int(h['Content-Length']),0)
 def test_legacy_save_roundtrip_and_private_permissions(self):
  raw=json.dumps({'gold':123,'season':{'premium':True}})
  self.assertEqual(self.req('/api/save',{'playerId':'FB-TEST-110A','save':raw})[0],200)
  out=json.loads(self.req('/api/save?playerId=FB-TEST-110A')[1]);self.assertEqual(out['save'],raw)
  self.assertEqual((self.root/'saves/FB-TEST-110A.json').stat().st_mode&0o777,0o600)
 def test_bad_body_never_overwrites_save(self):
  for value in [[],None,2,'bad',{'playerId':'FB-TEST-110A','save':'not json'},{'playerId':'FB-TEST-110A','save':[]}]:
   self.assertEqual(self.req('/api/save',value,method='POST')[0],400)
  self.assertFalse((self.root/'saves/FB-TEST-110A.json').exists())
 def test_path_and_object_ids_rejected(self):
  for pid in ['../../x',{},['x'],'x','x/y',None]:self.assertEqual(self.req('/api/save',{'playerId':pid,'save':{}})[0],400)
 def test_cors_rejects_other_sites_allows_local_alpha(self):
  self.assertEqual(self.req('/api/save?playerId=SECRET',headers={'Origin':'https://evil.invalid'})[0],403)
  status,_,h=self.req('/health',headers={'Origin':'null'});self.assertEqual(status,200);self.assertEqual(h['Access-Control-Allow-Origin'],'null')
 def test_concurrent_save_writes_are_complete_json(self):
  def write(i):return self.req('/api/save',{'playerId':'FB-TEST-110A','save':{'revision':i}})[0]
  with ThreadPoolExecutor(max_workers=8) as pool:self.assertTrue(all(x==200 for x in pool.map(write,range(24))))
  data=json.loads((self.root/'saves/FB-TEST-110A.json').read_text());self.assertIn(data['save']['revision'],range(24))
  self.assertEqual(list((self.root/'saves').glob('.save-*')),[])
 def test_html_cache_invalidates_on_atomic_source_update(self):
  self.req('/');p=self.root/'fatebound.html.next';p.write_text('<head></head>New build');p.replace(self.root/'fatebound.html')
  self.assertIn(b'New build',self.req('/')[1])
 def test_game_gzip_is_exact_and_etag_revalidation_returns_no_body(self):
  import gzip
  (self.root/'fatebound.html').write_text('<head></head>'+'<b>Game art fixture</b>'*400)
  status,raw,plain=self.req('/');self.assertEqual(status,200)
  status,packed,h=self.req('/',headers={'Accept-Encoding':'gzip'})
  self.assertEqual(h['Content-Encoding'],'gzip');self.assertEqual(gzip.decompress(packed),raw)
  self.assertLess(len(packed),len(raw));self.assertEqual(h['ETag'],plain['ETag'])
  status,body,h304=self.req('/',headers={'Accept-Encoding':'gzip','If-None-Match':h['ETag']})
  self.assertEqual(status,304);self.assertEqual(body,b'');self.assertIn('must-revalidate',h304['Cache-Control'])
  (self.root/'fatebound.html').write_text('<head></head>Different release')
  status,body,new=self.req('/',headers={'If-None-Match':h['ETag']})
  self.assertEqual(status,200);self.assertNotEqual(h['ETag'],new['ETag'])
 def test_compression_can_be_declined_and_saves_are_never_cached(self):
  (self.root/'fatebound.html').write_text('<head></head>'+'repeated data'*200)
  status,raw,h=self.req('/',headers={'Accept-Encoding':'gzip;q=0,*;q=1'})
  self.assertEqual(status,200);self.assertIsNone(h.get('Content-Encoding'))
  self.req('/api/save',{'playerId':'FB-NETW-TEST','save':{'text':'test'*300}})
  status,b,h=self.req('/api/save?playerId=FB-NETW-TEST',headers={'Accept-Encoding':'gzip'})
  self.assertEqual(h['Cache-Control'],'no-store');self.assertIsNone(h.get('ETag'))
if __name__=='__main__':unittest.main(verbosity=2)
