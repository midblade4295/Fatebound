#!/usr/bin/env node
// Export the exact original cue generator for optional auditioning; these WAVs are not extra runtime downloads.
'use strict';
const fs=require('node:fs'),path=require('node:path'),D=require('../src/game-audio');
const folder=process.argv[2]||'sound-preview';fs.mkdirSync(folder,{recursive:true});
function wav(samples,sr=32000){const b=Buffer.alloc(44+samples.length*2);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(sr,24);b.writeUInt32LE(sr*2,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(samples.length*2,40);samples.forEach((v,i)=>b.writeInt16LE(Math.round(Math.max(-1,Math.min(1,v)) * 32767),44+i*2));return b;}
const metadata=[];
for(const name of D.names){const r=D.render(name);fs.writeFileSync(path.join(folder,name+'.wav'),wav(r.samples));const sq=r.samples.reduce((a,x)=>a+x*x,0);metadata.push({cue:name,seconds:r.duration,peak:r.peak,rms:Math.sqrt(sq/r.samples.length)});}
const select=['menuOpen','tap','equip','purchase','roll','land','sword','axe','bow','magic','hit','crit','shield','shieldBreak','barrage','bulwark','horn','surge','meteor','victory'];
const parts=[],timeline=[];let offset=0;
for(const name of select){const r=D.render(name);timeline.push({at_seconds:offset/32000,cue:name});parts.push(r.samples,new Float32Array(8000));offset+=r.samples.length+8000;}
const all=new Float32Array(offset);let at=0;for(const p of parts){all.set(p,at);at+=p.length;}
fs.writeFileSync(path.join(folder,'fatebound-sound-demo.wav'),wav(all));fs.writeFileSync(path.join(folder,'cue-catalog.json'),JSON.stringify({original_design:true,sample_rate:32000,format:'16-bit mono WAV preview; runtime uses floating-point PCM and its own mixer',cues:metadata,demo_timeline:timeline},null,2)+'\n');
console.log(JSON.stringify({cues:metadata.length,demo_seconds:offset/32000,folder}));
