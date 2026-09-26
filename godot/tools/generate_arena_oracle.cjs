const fs=require('node:fs'),A=require('../../multiplayer/src/arena-engine.js');
const players=Array.from({length:20},(_,i)=>({id:'test'+i,name:'Test '+i,bot:i>0,char:i%5,weapon:0}));
const cases=[];let index=0;
for(const a of 'SCHGEF')for(const b of 'SCHGEF')for(const c of 'SCHGEF'){
 const e=new A.Engine({id:'oracle',players,now:100000,seed:12345,practice:true});
 e.faces=()=>[a,b,c];const r=e.act('test0',{type:'roll',mult:1},100000);
 cases.push({faces:[a,b,c],result:r,heroes:e.s.heroes,towers:e.s.towers,score:e.s.score});index++;
}
const runs=[];
for(const seed of [1,77,12345]){
 const e=new A.Engine({id:'run'+seed,players,now:100000,seed,practice:true});const ticks=[];
 for(let t=100250;t<=470000&&!e.s.ended;t+=250){e.tick(t);if((t-100000)%5000===0||e.s.ended)ticks.push({at:t,seed:e.seed,state:e.snapshot()});}
 runs.push({seed,ticks,result:e.result('test0')});
}
fs.writeFileSync('godot/tests/arena-oracle.json',JSON.stringify({players,cases,runs}));console.log('oracle cases',index,'runs',runs.length);
