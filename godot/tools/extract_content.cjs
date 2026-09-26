// Source tables only; no DOM or runtime game code is executed.
const fs=require('node:fs'),vm=require('node:vm'),crypto=require('node:crypto');
const source=fs.readFileSync('fatebound.html','utf8');
const hash=crypto.createHash('sha256').update(source).digest('hex');
if(hash!=='84697859827127e8c9285b0cf57578a8fc2bcedcb3cf8d3247772f0309f3b4e9')throw Error('Source changed');
function expression(name){const m=source.match(new RegExp('(?:const|let) '+name+'\\s*=\\s*([\\s\\S]*?);[ \t]*(?://[^\\n]*)?\\n'));if(!m)throw Error(name);return m[1];}
const names=['NAMES','CHARS','WEAPONS','TIERS','PERKS','SHARDS','SHARD_OF','RELICS','RANKS','DAILY_POOL','SEASON_NAMES','SEASON_TIERS','BOSS_NAMES','BOSS_TIERS','BOSS_MILESTONES','ULTS','BATTLE_LESSONS'];
const tables={};
for(const name of names){tables[name]=vm.runInNewContext('('+expression(name)+')',{}, {timeout:1000});}
tables.SEASON_TIERS.forEach(t=>t[0]*=20);
tables.SAVE_DEF=vm.runInNewContext('('+expression('SAVE_DEF')+')()',{}, {timeout:1000});
fs.writeFileSync('godot/data/v114-content.json',JSON.stringify({source_sha256:hash,tables},null,2)+'\n');
console.log('TABLES',names.map(n=>n+':'+Object.keys(tables[n]).length).join(' '));
