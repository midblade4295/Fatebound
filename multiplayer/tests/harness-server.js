// Test-only localhost fixture. Never used by the production systemd service.
const http=require('node:http');const {createServer}=require('../src/arena-server');let offset=0;const clock=()=>Date.now()+offset;
const {server,mm}=createServer({now:clock,allowLocal:true,rateLimit:10000});server.listen(8851,'127.0.0.1');
http.createServer((req,res)=>{const u=new URL(req.url,'http://localhost');const cmd=u.pathname;
if(cmd==='/advance'){let left=Number(u.searchParams.get('ms'));while(left>0){const step=Math.min(left,250);offset+=step;left-=step;for(const p of Object.values(mm.store.data.users))mm.state(p);mm.tick();}}
if(cmd==='/boost'){for(const r of mm.rooms.values())for(const h of r.engine.s.heroes){h.hp=h.maxHp;h.downUntil=0;h.focus=8;h.spell=2;h.ult=100;h.nextBot=clock()+1e9;h.rollAt=clock();}}
if(cmd==='/finish'){for(const r of mm.rooms.values()){for(const t of r.engine.s.towers)t.dmg=[1e8,0];r.engine.s.endAt=clock();}mm.tick();}
if(cmd==='/guild-progress'){for(const g of Object.values(mm.store.data.guilds)){g.progress=20;for(const id of g.members)g.contributions[id]=1;}}
if(cmd==='/reset'){mm.membership.clear();mm.rooms.clear();mm.lobbies=[];}
// Explicitly local-only state fixtures for synchronization regressions.
if(cmd==='/knockout'){for(const r of mm.rooms.values()){const h=r.engine.s.heroes.find(x=>x.id===u.searchParams.get('player'));if(h){h.hp=0;h.downUntil=clock()+Number(u.searchParams.get('ms')||45000);r.engine.s.revision++;}}}
if(cmd==='/force-faces'){const f=(u.searchParams.get('faces')||'').split(',');if(f.length===3&&f.every(x=>['S','C','H','G','E','F'].includes(x)))for(const r of mm.rooms.values()){r.engine.faces=()=>[...f];}}
if(cmd==='/substitute-roll'){for(const r of mm.rooms.values()){const h=r.engine.s.heroes.find(x=>x.id===u.searchParams.get('player'));if(h){const f=(u.searchParams.get('faces')||'G,G,E').split(',');h.hp=h.maxHp;h.downUntil=0;h.focus=8;h.rollAt=clock();h.substitute=true;r.engine.faces=()=>[...f];r.engine.act(h.id,{type:'roll',mult:1},clock());}}}
res.setHeader('Content-Type','application/json');res.end(JSON.stringify({now:clock(),rooms:mm.rooms.size,lobbies:mm.lobbies.length}));}).listen(8852,'127.0.0.1');
console.log('ready');
