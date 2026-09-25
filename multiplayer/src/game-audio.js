/* Fatebound sound workshop v111. Original layered PCM synthesis; no external samples.
   Separate sound RNG never consumes gameplay RNG. All output shares one bounded mixer. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.FateboundSoundDesign=api;})(globalThis,function(){
'use strict';
const SR=32000,TAU=Math.PI*2,clamp=(n,a,b)=>Math.max(a,Math.min(b,n));
const names=['tap','menuOpen','menuClose','confirm','equip','purchase','error','roll','land','sword','axe','bow','magic','hit','crit','shield','shieldBreak','hurt','ko','barrage','bulwark','horn','surge','shadow','rampage','meteor','volley','coin','gift','energy','level','flip','chestReady','chest','countdown','tension','miss','matchStart','victory','defeat','parry'];
const UI=new Set(['tap','menuOpen','menuClose','confirm','equip','purchase','error','coin','gift','level','chestReady','chest']);
const duration={tap:.12,menuOpen:.3,menuClose:.28,confirm:.36,equip:.32,purchase:.6,error:.28,roll:1.05,land:.23,sword:.37,axe:.46,bow:.35,magic:.5,hit:.26,crit:.65,shield:.5,shieldBreak:.63,hurt:.24,ko:.7,barrage:.95,bulwark:1.05,horn:1.25,surge:1.2,shadow:.68,rampage:1.15,meteor:1.35,volley:.9,coin:.34,gift:.63,energy:.48,level:1.1,flip:.78,chestReady:.64,chest:1.1,countdown:.22,tension:.72,miss:.3,matchStart:1.3,victory:1.65,defeat:1.15,parry:.56};
function render(name,variant=0,sr=SR){
 if(!Object.hasOwn(duration,name))throw Error('Unknown sound: '+name);
 sr=clamp(Number(sr)||SR,8000,96000);const len=Math.ceil(duration[name]*sr),out=new Float32Array(len);
 let seed=2166136261;for(const c of name+':'+variant)seed=Math.imul(seed^c.charCodeAt(0),16777619)>>>0;
 const rnd=()=>{seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return (seed>>>0)/4294967296;};
 const vary=UI.has(name)?1:.98+rnd()*.04;
 function tone(start,dur,f,end,gain,decay=6,partials=[1],attack=.003){
  end=(end||f)*vary;f*=vary;let phase=0;const beg=Math.round(start*sr),n=Math.round(dur*sr);
  for(let i=0;i<n&&beg+i<len;i++){const u=i/n,t=i/sr,hz=f*Math.pow(Math.max(.05,end/f),u);phase+=TAU*hz/sr;
   let v=0;for(let k=0;k<partials.length;k++)v+=partials[k]*Math.sin(phase*(k+1));
   const env=Math.min(1,t/attack)*Math.exp(-decay*u)*Math.min(1,(dur-t)/.012);
   out[beg+i]+=v*gain*env;
  }
 }
 function air(start,dur,gain,low=600,high=6500,shape=2,attack=.008){
  const beg=Math.round(start*sr),n=Math.round(dur*sr),lo=1-Math.exp(-TAU*low/sr),hi=1-Math.exp(-TAU*Math.min(high,sr*.42)/sr);let a=0,b=0;
  for(let i=0;i<n&&beg+i<len;i++){const x=rnd()*2-1,u=i/n,t=i/sr;a+=hi*(x-a);b+=lo*(x-b);out[beg+i]+=(a-b)*gain*Math.min(1,t/attack)*Math.pow(1-u,shape)*Math.min(1,(dur-t)/.012);}
 }
 const bell=(at,f,g=.25,d=.35)=>{[1,2.76,5.4].forEach((k,i)=>tone(at,d,f*k,f*k,g*[1,.23,.065][i],7+i*3));};
 const thud=(at,g=.5,low=95)=>{tone(at,.22,low*1.8,low*.5,g,7);air(at,.065,g*.55,180,1900,3,.002);};
 const metal=(at,g=.4)=>{[540,1270,2130,3490].forEach((f,i)=>tone(at,.36,f,f*.98,g*[.65,.35,.16,.065][i],6+i*2));air(at,.055,g*.6,1500,8500,3,.001);};
 const swish=(at,g=.5,d=.13)=>air(at,d,g,650,8500,1.2,.025);
 const chord=(notes,at=.02,step=.09,g=.2,d=.45)=>notes.forEach((f,i)=>{tone(at+i*step,d,f,f,g,4,[1,.2,.06],.012);bell(at+i*step,f*2,g*.22,d*.75);});
 const brass=(at,f,d=.6,g=.2)=>tone(at,d,f,f*1.004,g,1.6,[1,.42,.18,.08,.035],.07);
 switch(name){
 case'tap':thud(0,.16,240);bell(.004,740,.12,.09);break;
 case'menuOpen':air(0,.19,.25,400,3800,1.4,.018);chord([440,660],.015,.07,.2,.2);break;
 case'menuClose':air(0,.15,.18,350,2800,2,.005);chord([660,440],.008,.06,.16,.17);break;
 case'confirm':chord([523.25,783.99],.005,.07,.22,.27);break;
 case'equip':thud(0,.36,190);metal(.045,.25);break;
 case'purchase':[0,.07,.12,.21].forEach((t,i)=>bell(t,[1046,1568,1318,2093][i],.18,.31));thud(.015,.14,240);break;
 case'error':tone(0,.15,220,190,.23,4,[1,.12]);tone(.12,.15,164,154,.2,5);break;
 case'roll':for(let i=0;i<14;i++){const t=.008+i*.053+i*i*.00125;thud(t,.2*(1-i/25),220+rnd()*150);air(t,.035,.15,1400,6700,3,.001);}break;
 case'land':[0,.035,.073].forEach((t,i)=>{thud(t,.4/(1+i*.7),165+i*40);metal(t,.045);});break;
 case'sword':swish(0,.65,.16);thud(.11,.5,135);metal(.115,.33);break;
 case'axe':swish(0,.64,.19);thud(.14,.75,83);metal(.15,.22);air(.14,.13,.4,190,3300,3,.002);break;
 case'bow':tone(0,.22,330,160,.43,6,[1,.25,.1]);swish(.025,.45,.14);thud(.16,.44,180);break;
 case'magic':tone(0,.25,280,920,.28,3,[1,.2]);air(.03,.27,.32,800,7900,1.2,.04);thud(.21,.5,105);bell(.22,1174,.15,.26);break;
 case'hit':thud(0,.62,120);air(.002,.09,.38,500,3700,3,.002);break;
 case'crit':swish(0,.65,.15);thud(.105,.85,62);metal(.11,.5);air(.115,.3,.6,210,5800,2,.002);bell(.13,1660,.07,.35);break;
 case'shield':thud(0,.28,125);metal(.012,.65);tone(.018,.43,280,275,.32,6);break;
 case'shieldBreak':metal(0,.7);thud(.012,.55,90);for(let i=0;i<9;i++)bell(.035+i*.038,1350+rnd()*3200,.1*(1-i/14),.18);air(.045,.4,.4,1800,10000,2,.002);break;
 case'hurt':thud(0,.55,92);air(.002,.13,.37,320,2100,4,.002);break;
 case'ko':thud(0,.68,75);metal(.02,.16);tone(.05,.55,165,48,.36,5);air(.03,.4,.24,120,2300,2);break;
 case'barrage':[0,.19,.4].forEach((t,i)=>{swish(t,.5,.14);thud(t+.1,.55+i*.12,100-i*18);metal(t+.11,.3);air(t+.11,.3,.35,240,4500,3);});break;
 case'bulwark':thud(.02,.55,65);tone(.02,.9,138.59,277.18,.32,1.8,[1,.12],.06);metal(.24,.25);chord([277.18,415.3,554.37],.24,.13,.21,.53);air(.08,.7,.3,500,3800,1,.15);break;
 case'horn':brass(.02,196,1.05,.32);brass(.12,293.66,.92,.23);brass(.35,392,.75,.11);air(.02,.8,.085,180,1100,1.6,.06);break;
 case'surge':tone(0,.65,164.81,1318.51,.21,1.3,[1,.15],.05);air(.05,.78,.38,1800,9400,1,.07);chord([329.63,493.88,659.26,987.77],.12,.13,.19,.5);break;
 case'shadow':swish(.0,.52,.22);swish(.24,.62,.18);tone(0,.4,440,110,.2,3);metal(.34,.32);thud(.34,.46,82);break;
 case'rampage':[0,.18,.39,.63].forEach((t,i)=>thud(t,.7,70+i*6));brass(.11,98,.83,.22);air(.28,.5,.2,300,3700,2);break;
 case'meteor':air(0,.67,.45,170,3200,.6,.03);tone(0,.61,640,50,.32,1.1);thud(.56,1,43);air(.56,.67,.8,140,5400,2,.002);metal(.56,.32);break;
 case'volley':for(let i=0;i<6;i++){tone(i*.11,.17,360-i*12,150,.19,5,[1,.16]);swish(i*.11+.02,.3,.13);thud(i*.11+.16,.22,170);}break;
 case'coin':bell(0,1568,.23,.22);bell(.07,2093,.16,.25);break;
 case'gift':chord([659.25,880,1318.51],.015,.1,.2,.38);air(.08,.36,.12,2200,9000,2);break;
 case'energy':tone(0,.35,392,1174,.23,2.5);bell(.1,1174,.15,.31);break;
 case'level':chord([261.63,329.63,392,523.25],.02,.14,.25,.61);brass(.48,261.63,.52,.1);break;
 case'flip':thud(0,.36,95);chord([392,523.25,659.25],.055,.12,.25,.5);break;
 case'chestReady':thud(0,.24,180);bell(.03,784,.21,.36);bell(.17,1174,.19,.36);break;
 case'chest':thud(0,.3,170);air(.02,.17,.22,130,1900,1);metal(.09,.14);chord([523.25,659.25,783.99,1046.5],.17,.12,.22,.47);break;
 case'countdown':thud(0,.18,220);bell(.01,880,.25,.16);break;
 case'tension':tone(.015,.59,220,660,.24,1.5,[1,.1],.025);[0,.19,.38].forEach(t=>thud(t,.19,100));break;
 case'miss':tone(0,.21,330,180,.16,4,[1,.08]);air(.01,.18,.12,450,1800,2);break;
 case'matchStart':brass(.03,196,.85,.26);brass(.2,293.66,.9,.23);thud(.015,.48,75);chord([392,523.25,784],.36,.13,.23,.47);break;
 case'victory':chord([261.63,329.63,392,523.25],.02,.18,.23,.79);brass(.62,261.63,.82,.21);brass(.65,392,.76,.15);thud(.04,.26,85);break;
 case'defeat':chord([293.66,246.94,196],.025,.22,.18,.59);air(.06,.68,.1,140,1300,1.8);break;
 case'parry':metal(0,.66);bell(.04,1568,.22,.4);thud(.015,.36,150);break;
 }
 // DC removal, soft saturation and edge fades: every cue ends at digital silence.
 let prev=0,hp=0,peak=0;for(let i=0;i<len;i++){const x=out[i];hp=x-prev+.995*hp;prev=x;const env=Math.min(1,i/(sr*.002),(len-1-i)/(sr*.008));out[i]=Math.tanh(hp*1.15)*Math.max(0,env);peak=Math.max(peak,Math.abs(out[i]));}
 const target=UI.has(name)?.56:.72,scale=peak>0?target/peak:1;for(let i=0;i<len;i++)out[i]*=scale;
 out[0]=0;out[len-1]=0;return {samples:out,sampleRate:sr,duration:len/sr,peak:target};
}
function create(win){
 win=win||window;let ac=null,mixer=null,master=null,buses={},unlocked=false,resuming=null,muted=false,serial=0;
 const voices=new Set(),cache=new Map(),last=new Map(),stats={played:0,dropped:0,contexts:0,peakVoices:0,counts:{}};
 let prefs={master:.7,combat:.8,ui:.6};
 try{muted=win.localStorage.getItem('ds-mute')==='1';const p=JSON.parse(win.localStorage.getItem('fatebound-audio-prefs')||'null');if(p)for(const k of Object.keys(prefs))if(Number.isFinite(p[k]))prefs[k]=clamp(p[k],0,1);}catch(_){}
 function stopAll(){for(const v of [...voices]){try{v.node.stop();}catch(_){}v.done();}}
 function volumes(){if(!ac)return;const t=ac.currentTime;master.gain.setTargetAtTime(muted?0:prefs.master,t,.012);for(const k of ['combat','ui'])buses[k].gain.setTargetAtTime(prefs[k],t,.012);}
 function init(){if(ac)return ac;if(!unlocked)return null;try{
  const C=win.AudioContext||win.webkitAudioContext;if(!C)return null;ac=new C({latencyHint:'interactive'});stats.contexts++;
  mixer=ac.createDynamicsCompressor();mixer.threshold.value=-13;mixer.knee.value=10;mixer.ratio.value=7;mixer.attack.value=.003;mixer.release.value=.14;
  const limiter=ac.createWaveShaper(),curve=new Float32Array(2049);for(let i=0;i<curve.length;i++){const x=i*2/(curve.length-1)-1;curve[i]=.7*Math.tanh(2.5*x)/Math.tanh(2.5);}limiter.curve=curve;limiter.oversample='2x';master=ac.createGain();mixer.connect(limiter);limiter.connect(master);master.connect(ac.destination);for(const k of ['combat','ui']){buses[k]=ac.createGain();buses[k].connect(mixer);}volumes();
 }catch(_){ac=null;}return ac;}
 function unlock(){unlocked=true;const a=init();if(a&&(a.state==='suspended'||a.state==='interrupted')&&!resuming&&!win.document.hidden){resuming=a.resume().catch(()=>{}).finally(()=>{resuming=null;});}return a;}
 function play(name,opt={}){
  if(!Object.hasOwn(duration,name)||muted||!unlocked||win.document.hidden||prefs.master<=0)return false;
  const bus=opt.bus==='ui'||UI.has(name)?'ui':'combat';if(prefs[bus]<=0)return false;const a=init();if(!a||a.state!=='running')return false;
  const now=win.performance.now(),gap=bus==='ui'?55:opt.ambient?160:35,key=opt.group||name;
  if(now-(last.get(key)||-1e6)<gap){stats.dropped++;return false;}
  if(voices.size>=16){if(opt.ambient){stats.dropped++;return false;}const v=[...voices].find(v=>v.ambient)||voices.values().next().value;try{v.node.stop();}catch(_){}v.done();}
  last.set(key,now);const variant=UI.has(name)?0:(serial++%3),ck=name+':'+variant;let buffer=cache.get(ck);
  if(!buffer){const pcm=render(name,variant);buffer=a.createBuffer(1,pcm.samples.length,pcm.sampleRate);buffer.copyToChannel(pcm.samples,0);cache.set(ck,buffer);}
  const src=a.createBufferSource(),g=a.createGain(),pan=a.createStereoPanner?.();src.buffer=buffer;g.gain.value=clamp(Number.isFinite(opt.gain)?opt.gain:1,0,1);src.connect(g);if(pan){pan.pan.value=clamp(Number(opt.pan)||0,-.65,.65);g.connect(pan);pan.connect(buses[bus]);}else g.connect(buses[bus]);
  const v={node:src,ambient:!!opt.ambient,done(){if(!voices.delete(v))return;try{src.disconnect();g.disconnect();pan?.disconnect();}catch(_){}}};voices.add(v);src.onended=v.done;
  try{src.start(a.currentTime+clamp(Number(opt.delay)||0,0,.7));}catch(_){v.done();return false;}
  stats.played++;stats.counts[name]=(stats.counts[name]||0)+1;stats.peakVoices=Math.max(stats.peakVoices,voices.size);return true;
 }
 function setVolumes(values){for(const k of Object.keys(prefs))if(Number.isFinite(values[k]))prefs[k]=clamp(values[k],0,1);try{win.localStorage.setItem('fatebound-audio-prefs',JSON.stringify(prefs));}catch(_){}volumes();return {...prefs};}
 const weapon=(cls)=>cls==='axe'?'axe':cls==='magic'?'magic':cls==='bow'||cls==='crossbow'?'bow':'sword';
 const api={play,unlock,setVolumes,get volumes(){return {...prefs};},get muted(){return muted;},toggle(){muted=!muted;try{win.localStorage.setItem('ds-mute',muted?'1':'0');}catch(_){}if(muted)stopAll();volumes();return muted;},stopAll,
  strike(cls,critical=false,opt={}){return play(critical?'crit':weapon(cls),opt);},spell(k,opt={}){return play({barrage:'barrage',bulwark:'bulwark',hold:'bulwark',horn:'horn',surge:'surge'}[k]||'magic',opt);},ultimate(char,opt={}){return play(['bulwark','shadow','rampage','meteor','volley'][Number(char)]||'magic',opt);},
  outcome(result,cls,opt={}){const symbol=result.symbol||result.action;if(symbol==='S'||symbol==='C')return api.strike(cls,symbol==='C',opt);return play({H:'shield',G:'coin',E:'energy',F:'gift'}[symbol]||'miss',opt);},
  get diagnostics(){return {...stats,counts:{...stats.counts},voices:voices.size,cached:cache.size,state:ac?.state||'locked',muted,prefs:{...prefs}};}};
 for(const name of names)if(!Object.hasOwn(api,name))api[name]=(opt)=>play(name,typeof opt==='object'?opt:{});
 api.rally=api.horn;
 win.document.addEventListener('visibilitychange',()=>{if(win.document.hidden){stopAll();if(ac?.state==='running')ac.suspend().catch(()=>{});}else if(unlocked&&!muted)unlock();});
 win.addEventListener('pagehide',stopAll);
 return api;
}
return {names,duration,render,create,sampleRate:SR};
});
