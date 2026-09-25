/* v114 Guild hall. The composer is mounted once and is never rewritten during render.
   The solo company feed is explicitly distinct from real expedition membership. */
(()=>{'use strict';
 const $=id=>document.getElementById(id),root=$('scrGuild');let mounted=false,composing=false,tab='overview';
 const rows=new Map();let messageKey='';
 const write=(id,v)=>{const n=$(id);if(n&&n.textContent!==String(v))n.textContent=String(v);};
 const stats={renders:0,mounts:0,sent:0};
 function mount(){if(mounted)return;mounted=true;stats.mounts++;
  root.classList.add('guild-hall');root.dataset.guildKey='stable-v114';
  root.innerHTML=`<header class="guild-hall-hero"><div class="guild-crest" aria-hidden="true">B</div><div><span class="guild-eyebrow">GUILD HALL</span><h2 id="guildHallName">Brass Company</h2><p id="guildHallSubtitle">Your company, shared goals, and next battle.</p></div></header>
  <div id="guildExpeditionSlot"></div>
  <div class="guild-tabs" role="tablist" aria-label="Guild sections"><button type="button" id="guildTab-overview" role="tab" data-guild-tab="overview" aria-controls="guildPane-overview" aria-selected="true">Overview</button><button type="button" id="guildTab-roster" role="tab" data-guild-tab="roster" aria-controls="guildPane-roster" aria-selected="false">Company</button><button type="button" id="guildTab-chat" role="tab" data-guild-tab="chat" aria-controls="guildPane-chat" aria-selected="false">War room</button></div>
  <section id="guildPane-overview" class="guild-pane" role="tabpanel" aria-labelledby="guildTab-overview">
   <section class="guild-live-card"><span class="guild-eyebrow">REAL GUILD · WEEKLY EXPEDITION</span><h3 id="guildLiveName">Make your next battle count</h3><p id="guildLiveText">Create a guild or join with a friend's code. Only real members contribute to the shared expedition.</p><div class="guild-expedition-track" aria-label="Expedition checkpoints"><span>01<br><b>Supply camp</b></span><span>02<br><b>Fort assault</b></span><span>03<br><b>Citadel</b></span></div><progress id="guildLiveProgress" max="120" value="0" aria-label="Weekly expedition progress"></progress><small id="guildLiveCount">Manage membership and milestones with Live guild above.</small></section>
   <section class="guild-company-card"><span class="guild-eyebrow">SOLO COMPANY SNAPSHOT</span><div class="guild-score-row"><div><strong id="guildCrowns">0 crowns</strong><small>BRASS COMPANY</small></div><span>VS</span><div><strong id="guildEnemyCrowns">0 crowns</strong><small>CRIMSON VOW</small></div></div><p>Hold contested towers through the final push. Solo company bots are not live guild members.</p><div class="guild-stat-grid"><span><b id="guildPoints">0</b>Points</span><span><b id="guildDamage">0</b>Damage</span><span><b id="guildKos">0</b>Knockouts</span></div></section>
   <section class="guild-role-card"><span class="guild-eyebrow">YOUR HERO</span><h3 id="guildHeroName"></h3><p id="guildHeroPerk"></p><small>Online battles use equalized level-10 equipment. Gold and XP from rolls are banked until match-end rewards.</small></section>
  </section>
  <section id="guildPane-roster" class="guild-pane" role="tabpanel" aria-labelledby="guildTab-roster" hidden><h3>Brass Company <small id="guildRosterCount"></small></h3><p class="guild-note" id="guildStanding"></p><p class="guild-note">This is the solo company roster. Your real guild's members appear under Live guild.</p><div id="guildRoster" class="guild-roster"></div></section>
  <section id="guildPane-chat" class="guild-pane guild-room" role="tabpanel" aria-labelledby="guildTab-chat" hidden><h3>Company war room</h3><p class="guild-note">Local solo messages and battle updates. Messages here are saved on this device, not broadcast to other players.</p><div class="chatlog" id="glog" role="log" aria-label="Company messages"></div><form id="guildComposer" autocomplete="off"><label class="guild-note" for="gmsg">Your message</label><div class="guild-composer-row"><input id="gmsg" name="message" type="text" dir="ltr" maxlength="120" inputmode="text" enterkeyhint="send" placeholder="Write a company message…" aria-label="Company message"><button type="submit" id="gsend">Send</button></div><small id="guildComposeStatus" role="status">Draft stays here when you change tabs.</small></form></section>`;
  const input=$('gmsg');try{input.value=localStorage.getItem('fatebound-guild-draft')||'';}catch(_){}
  input.addEventListener('compositionstart',()=>{composing=true;});input.addEventListener('compositionend',()=>{composing=false;saveDraft();});
  function saveDraft(){try{localStorage.setItem('fatebound-guild-draft',input.value);}catch(_){}write('guildComposeStatus',input.value.length+'/120 · device-local draft');}
  input.addEventListener('input',saveDraft);
  input.addEventListener('keydown',e=>{if(e.key==='Enter'&&(e.isComposing||composing||e.keyCode===229)){e.preventDefault();}});
  $('guildComposer').addEventListener('submit',e=>{
   e.preventDefault();if(composing)return;
   const value=input.value.trim();if(!value)return;
   feed('You: '+value,'you');stats.sent++;input.value='';saveDraft();SFX.confirm();
   try{const old=JSON.parse(localStorage.getItem('fatebound-company-chat')||'[]');const entries=Array.isArray(old)?old:[];entries.push({text:'You: '+value,at:Date.now()});localStorage.setItem('fatebound-company-chat',JSON.stringify(entries.slice(-30)));}catch(_){}
   renderMessages();write('guildComposeStatus','Message added to your local war room.');input.focus({preventScroll:true});
  });
  root.querySelector('.guild-tabs').addEventListener('click',e=>{const b=e.target.closest('[data-guild-tab]');if(b)setTab(b.dataset.guildTab);});
  root.querySelector('.guild-tabs').addEventListener('keydown',e=>{if(!['ArrowLeft','ArrowRight','Home','End'].includes(e.key))return;e.preventDefault();const list=['overview','roster','chat'],i=list.indexOf(tab);setTab(e.key==='Home'?list[0]:e.key==='End'?list[2]:list[(i+(e.key==='ArrowRight'?1:2))%3]);$('guildTab-'+tab).focus({preventScroll:true});});
 }
 function setTab(next){if(!['overview','roster','chat'].includes(next))return;tab=next;
  root.querySelectorAll('[data-guild-tab]').forEach(b=>{const active=b.dataset.guildTab===tab;b.setAttribute('aria-selected',String(active));b.tabIndex=active?0:-1;});
  for(const key of ['overview','roster','chat'])$('guildPane-'+key).hidden=key!==tab;
  root.scrollTop=0;SFX.tap();if(tab==='chat')renderMessages();
 }
 function renderMessages(){
  const log=$('glog');if(!log)return;let saved=[];try{saved=JSON.parse(localStorage.getItem('fatebound-company-chat')||'[]');}catch(_){}
  if(!Array.isArray(saved))saved=[];
  const current=feedLog.slice(0,25).map(f=>({text:f.text,cls:f.cls||''})).reverse();
  const items=[...saved.filter(x=>typeof x.text==='string'&&!current.some(c=>c.text===x.text)).slice(-20),...current];
  const key=JSON.stringify(items);if(key===messageKey)return;messageKey=key;
  const stick=log.scrollHeight-log.clientHeight-log.scrollTop<25,top=log.scrollTop,fragment=document.createDocumentFragment();
  for(const m of items){const n=document.createElement('p');n.textContent=m.text;n.className=m.cls||'';fragment.append(n);}
  if(!items.length){const n=document.createElement('p');n.textContent='No messages yet. Plan your next tower push here.';fragment.append(n);}
  log.replaceChildren(fragment);log.scrollTop=stick?log.scrollHeight:top;
 }
 function render(){if(!M||!player)return;mount();stats.renders++;
  const members=side(0),live=window.FBNext?.profile?.guild;
  write('guildHallName',live?.name||'Brass Company');write('guildHallSubtitle',live?'A real guild. A shared weekly expedition.':'Your solo company · connect a real guild below');
  write('guildLiveName',live?.name||'Make your next battle count');
  write('guildLiveText',live?`${live.members.length} real members · ${live.route} route · week ${live.week} UTC`:'Create a guild or join with a friend’s code. Only real members contribute to the shared expedition.');
  const progress=$('guildLiveProgress'),val=Math.min(120,live?.progress||0);if(progress.value!==val)progress.value=val;
  write('guildLiveCount',live?`${val}/120 shared expedition contribution`:'Manage membership and milestones with Live guild above.');
  write('guildCrowns',points(0)+' crowns');write('guildEnemyCrowns',points(1)+' crowns');write('guildPoints',points(0));write('guildDamage',fmtK(M.tally[0].damage));write('guildKos',M.tally[0].kos);
  write('guildStanding',`${members.length} solo fighters · ${members.filter(h=>!down(h)).length} standing`);write('guildRosterCount',members.length+'/20');
  write('guildHeroName',CHARS[SAVE.char||0].n);
  write('guildHeroPerk',[
   'Knight: increased health. Bulwark protects nearby allies and equips shields.',
   'Rogue: stronger critical strikes. Shadow Dance converts the next three rolls into critical strikes.',
   'Berserker: increased attack. Rampage gives five free ×1 rolls with double attack damage.',
   'Mage: stronger gold rolls and critical strikes, with slightly lower health. Meteor bypasses shields.',
   'Ranger: bonus attack, critical strength and Focus results. Volley fires six shots and restores Focus for knockouts.'
  ][SAVE.char||0]);
  // Stable keyed roster; never replace the composer, even after a new match changes IDs.
  for(const [id,row] of rows)if(!members.some(h=>h.id===id)){row.remove();rows.delete(id);}
  for(const h of members){let row=rows.get(h.id);if(!row){row=document.createElement('article');row.className='member';row.innerHTML='<canvas width="126" height="156" aria-hidden="true"></canvas><div><b class="member-name"></b><small class="member-hero"></small><small class="where"></small></div><div class="dmg"><b class="member-damage"></b><small>DAMAGE</small></div>';row.dataset.member=h.id;rows.set(h.id,row);$('guildRoster').append(row);}
   const put=(sel,v)=>{const n=row.querySelector(sel);if(n.textContent!==String(v))n.textContent=String(v);};
   put('.member-name',h.name);put('.member-hero',`${CHARS[h.char||0].n} · Lv ${h.level}`);put('.member-damage',fmtK(h.damage));const ti=h===player?h.tower:heroTower(h);put('.where',(ti==null?'On the map':'Tower '+(M.towers[ti]?.name||'?'))+(down(h)?' · Recovering':''));
   const cv=row.querySelector('canvas'),key=(h.char||0)+':'+(h.weapon||0);if(cv.dataset.portrait!==key){drawCharPortrait(cv,h.char||0,h.weapon||0);cv.dataset.portrait=key;}
  }
  if(tab==='chat')renderMessages();
 }
 window.FateboundGuild={render,setTab,get diagnostics(){return {...stats,composing,tab};}};
 if(screen==='guild')render();
})();
