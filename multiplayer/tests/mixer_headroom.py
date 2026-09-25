"""Render the real browser mixer for all cues at maximum volume. No game fixtures shipped."""
from pathlib import Path
BASE=Path(__file__).with_name('browser_tests.py');space={'__file__':str(BASE)}
exec(BASE.read_text().split('with sync_playwright() as pw:')[0],space)
globals().update({k:v for k,v in space.items() if not k.startswith('__')})
with sync_playwright() as pw:
 b=pw.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage'])
 try:
  p=ready_page(b)
  values=p.evaluate('''async()=>{const out=[];for(const cue of FateboundSoundDesign.names){const ctx=new OfflineAudioContext(1,64000,32000);Object.defineProperty(ctx,'state',{get:()=> 'running'});const win={AudioContext:function(){return ctx},localStorage:{getItem:()=>null,setItem:()=>{}},document:{hidden:false,addEventListener:()=>{}},performance,addEventListener:()=>{}};const a=FateboundSoundDesign.create(win);a.unlock();a.setVolumes({master:1,combat:1,ui:1});for(let i=0;i<16;i++)a.play(cue,{group:'stress'+i,delay:.08});const r=await ctx.startRendering();let peak=0,energy=0;for(const x of r.getChannelData(0)){if(!Number.isFinite(x))throw Error(cue+' has nonfinite PCM');peak=Math.max(peak,Math.abs(x));energy+=x*x;}out.push({cue,peak,rms:Math.sqrt(energy/r.length),maxVoices:a.diagnostics.peakVoices});}return out;}''')
  assert len(values)==41
  assert all(v['peak']<.98 and v['peak']>.01 and v['maxVoices']==16 for v in values),values
  result={'source_sha256':SOURCE_SHA256,'cue_count':len(values),'simultaneous_voices':16,'volume':'all buses 100%','maximum_sample_peak':max(v['peak'] for v in values),'status':'PASS','measurements':values,'environment':'Chromium OfflineAudioContext with the actual production mixer graph, not physical speakers'}
  (ROOT/'ui-audio/mixer-headroom.json').write_text(json.dumps(result,indent=2))
  print(json.dumps({k:v for k,v in result.items() if k!='measurements'},indent=2),flush=True)
 finally:b.close()
