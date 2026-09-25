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
