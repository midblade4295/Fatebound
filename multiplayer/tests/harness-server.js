// Test-only localhost fixture. Never used by the production systemd service.
const http=require('node:http');const {createServer}=require('../src/arena-server');let offset=0;const clock=()=>Date.now()+offset;
const {server,mm}=createServer({now:clock,allowLocal:true,rateLimit:10000});server.listen(8851,'127.0.0.1');
http.createServer((req,res)=>{const u=new URL(req.url,'http://localhost');const cmd=u.pathname;
if(cmd==='/advance'){let left=Number(u.searchParams.get('ms'));while(left>0){const step=Math.min(left,250);offset+=step;left-=step;for(const p of Object.values(mm.store.data.users))mm.state(p);mm.tick();}}
if(cmd==='/boost'){for(const r of mm.rooms.values())for(const h of r.engine.s.heroes){h.hp=h.maxHp;h.downUntil=0;h.focus=8;h.spell=2;h.ult=100;h.nextBot=clock()+1e9;h.rollAt=clock();}}
if(cmd==='/finish'){for(const r of mm.rooms.values()){r.engine.s.towers[9].dmg=[1e8,0];r.engine.s.endAt=clock();}mm.tick();}
if(cmd==='/guild-progress'){for(const g of Object.values(mm.store.data.guilds)){g.progress=20;for(const id of g.members)g.contributions[id]=1;}}
if(cmd==='/reset'){mm.membership.clear();mm.rooms.clear();mm.lobbies=[];}
res.setHeader('Content-Type','application/json');res.end(JSON.stringify({now:clock(),rooms:mm.rooms.size,lobbies:mm.lobbies.length}));}).listen(8852,'127.0.0.1');
console.log('ready');
