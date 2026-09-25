'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const D=require('../src/game-audio');
test('41 original cues: finite PCM, bounded peaks, silence at both edges and distinct content',()=>{
 const hashes=new Set();let seconds=0;
 for(const name of D.names){const r=D.render(name,0);assert.equal(r.sampleRate,32000);assert(r.duration>=.1&&r.duration<=1.7);assert.equal(r.samples[0],0);assert.equal(r.samples.at(-1),0);let sum=0,peak=0;
  for(const x of r.samples){assert(Number.isFinite(x));peak=Math.max(peak,Math.abs(x));sum+=x*x;}assert(peak<=.721&&peak>=.55);assert(Math.sqrt(sum/r.samples.length)>.03);hashes.add(crypto.createHash('sha256').update(Buffer.from(r.samples.buffer)).digest('hex'));seconds+=r.duration;
 }
 assert.equal(hashes.size,41);assert.equal(D.names.length,41);assert(seconds>20);
});
test('Sound variations are deterministic without touching Math.random or the gameplay RNG',()=>{
 const old=Math.random;Math.random=()=>{throw Error('Gameplay RNG consumed by sound');};
 try{assert.deepEqual(D.render('sword',1).samples,D.render('sword',1).samples);assert.notDeepEqual(D.render('sword',1).samples,D.render('sword',2).samples);}finally{Math.random=old;}
});
test('Unknown cue cannot allocate PCM',()=>assert.throws(()=>D.render('invalid')));

test('first sound survives a delayed mobile AudioContext resume instead of being dropped',async()=>{
 class Param{constructor(v=0){this.value=v;}setTargetAtTime(v){this.value=v;}}
 class Node{connect(){return this;}disconnect(){}}
 class Buffer{copyToChannel(){}}
 class Source extends Node{constructor(){super();this.onended=null;}start(){setTimeout(()=>this.onended&&this.onended(),5);}stop(){this.onended&&this.onended();}}
 class AC{
  constructor(){this.state='suspended';this.currentTime=0;this.sampleRate=48000;this.destination=new Node();}
  createDynamicsCompressor(){const n=new Node();for(const k of ['threshold','knee','ratio','attack','release'])n[k]=new Param();return n;}
  createWaveShaper(){return new Node();}
  createGain(){const n=new Node();n.gain=new Param(1);return n;}
  createBuffer(){return new Buffer();}
  createBufferSource(){return new Source();}
  createStereoPanner(){const n=new Node();n.pan=new Param(0);return n;}
  resume(){return new Promise(r=>setTimeout(()=>{this.state='running';r();},30));}
  suspend(){this.state='suspended';return Promise.resolve();}
 }
 const listeners={};
 const store=new Map();
 const win={AudioContext:AC,performance:{now:()=>Date.now()},document:{hidden:false,addEventListener:(t,f)=>{(listeners[t]??=[]).push(f);}},
  addEventListener(){},localStorage:{getItem:k=>store.get(k)||null,setItem:(k,v)=>store.set(k,String(v))}};
 const a=D.create(win);
 assert.equal(a.play('sword'),true);
 assert.equal(a.diagnostics.played,0);
 assert.equal(a.diagnostics.pending,1);
 await new Promise(r=>setTimeout(r,70));
 assert.equal(a.diagnostics.state,'running');
 assert.equal(a.diagnostics.pending,0);
 assert.equal(a.diagnostics.played,1);
 assert.equal(a.diagnostics.flushed,1);
 assert.equal(a.diagnostics.contexts,1);
});

test('AudioContext constructor falls back when latencyHint options are rejected',async()=>{
 let calls=0;
 class Param{constructor(v=0){this.value=v;}setTargetAtTime(v){this.value=v;}}
 class Node{connect(){return this;}disconnect(){}}
 class Source extends Node{start(){setTimeout(()=>this.onended&&this.onended(),1);}stop(){}}
 class AC{
  constructor(opts){calls++;if(opts)throw Error('options unsupported');this.state='running';this.currentTime=0;this.sampleRate=44100;this.destination=new Node();}
  createDynamicsCompressor(){const n=new Node();for(const k of ['threshold','knee','ratio','attack','release'])n[k]=new Param();return n;}
  createWaveShaper(){return new Node();}
  createGain(){const n=new Node();n.gain=new Param(1);return n;}
  createBuffer(){return {copyToChannel(){}};}
  createBufferSource(){return new Source();}
  createStereoPanner(){const n=new Node();n.pan=new Param();return n;}
  resume(){return Promise.resolve();}
 }
 const win={AudioContext:AC,performance:{now:()=>1},document:{hidden:false,addEventListener(){}},addEventListener(){},localStorage:{getItem(){return null;},setItem(){}}};
 const a=D.create(win);await a.unlock();assert.equal(calls,2);assert.equal(a.play('tap'),true);assert.equal(a.diagnostics.state,'running');
});
