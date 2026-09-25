/* v111: bounded, local UI state. No MutationObserver, animation loop or global input gate. */
(()=>{'use strict';
const $=id=>document.getElementById(id);let chestOpener=null,audioOpener=null,chestKey='';
const icons={chest:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 10V8a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4v2M3 10h18v10H3zm0 3h18M10 11h4v5h-4z" fill="none" stroke="currentColor" stroke-width="1.8"/></svg>',audio:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 10v4h4l5 4V6l-5 4H4m12-2c3 2 3 6 0 8m3-11c5 4 5 10 0 14" fill="none" stroke="currentColor" stroke-width="1.8"/></svg>'};
function addButton(parent,id,html,title,action){if($(id)||!parent)return;const b=document.createElement('button');b.type='button';b.id=id;b.className='comfort-button';b.innerHTML=html;b.setAttribute('aria-label',title);b.title=title;b.onclick=action;parent.append(b);}
function modal(id,title){let box=$(id);if(box)return box;box=document.createElement('div');box.id=id;box.className='overlay comfort-modal';box.hidden=true;box.innerHTML=`<section class="comfort-panel" role="dialog" aria-modal="true" aria-labelledby="${id}Title"><header><h2 id="${id}Title">${title}</h2><button class="comfort-close" aria-label="Close">×</button></header><div class="comfort-scroll"></div><footer></footer></section>`;document.body.append(box);
 box.querySelector('.comfort-close').onclick=()=>close(id);
 box.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();e.stopPropagation();close(id);return;}if(e.key!=='Tab')return;const nodes=[...box.querySelectorAll('button,input,select')].filter(n=>!n.disabled&&!n.hidden&&n.getClientRects().length);const a=nodes[0],b=nodes.at(-1);if(e.shiftKey&&document.activeElement===a){e.preventDefault();b?.focus({preventScroll:true});}else if(!e.shiftKey&&document.activeElement===b){e.preventDefault();a?.focus({preventScroll:true});}});
 return box;
}
function close(id){const box=$(id);if(!box||box.hidden)return;box.hidden=true;SFX.menuClose();const opener=id==='soundSettings'?audioOpener:chestOpener;if(opener?.isConnected)opener.focus({preventScroll:true});}
function waiting(){return !!(window.FBNext?.active||window.FBNext?.searching||TRAIN||$('roll').classList.contains('busy')||QTE||giftState);}
function count(){const r=rollTrack();return Math.max(0,r.ready||0)+(SAVE.pendingOpenChest?1:0)+(SAVE.chests?.length||0);}
function refreshBadges(){const n=count(),label=n>99?'99+':String(n);for(const id of ['homeChests','battleChests','mapChests']){const b=$(id);if(!b)continue;const badge=b.querySelector('b');if(badge.textContent!==label)badge.textContent=label;b.classList.toggle('has-rewards',n>0);b.setAttribute('aria-label',`Chests: ${n} saved. Open chest inbox.`);}if(!$('chestInbox')?.hidden)renderInbox();}
function openChests(){if(TRAIN){toast('Finish or exit training to open your saved chests.','info');return;}chestOpener=document.activeElement;const box=modal('chestInbox','Your chests');chestKey='';renderInbox();box.hidden=false;SFX.menuOpen();box.querySelector('.comfort-close').focus({preventScroll:true});}
function renderInbox(){const box=$('chestInbox');if(!box)return;const r=rollTrack(),locked=waiting(),match=!!(M&&!M.lobby&&!M.ended),pending=SAVE.pendingOpenChest,stored=SAVE.chests?.length||0;
 const key=JSON.stringify([r.ready,r.progress,r.gold,r.shards,!!pending,stored,locked,match]);if(chestKey===key)return;chestKey=key;
 const pane=box.querySelector('.comfort-scroll'),scroll=pane.scrollTop;
 pane.innerHTML='<p class="comfort-note">No countdown. These rewards stay saved until collected. You can close this window and come back.</p>';
 const section=(title,desc,buttonId,buttonText,disabled)=>{const s=document.createElement('section');s.className='chest-card';const h=document.createElement('h3');h.textContent=title;s.append(h);const p=document.createElement('p');p.textContent=desc;s.append(p);if(buttonId){const b=document.createElement('button');b.id=buttonId;b.textContent=buttonText;b.disabled=disabled;s.append(b);}pane.append(s);};
 section(`${r.ready||0} roll chest${r.ready===1?'':'s'} ready`,r.ready?`${fmt(r.gold)} gold · ${Object.entries(r.shards||{}).filter(([,n])=>n>0).map(([k,n])=>`${fmt(n)} ${k} shards`).join(' · ')}`:`${20-r.progress} Focus to the next solo battle chest. Online matches award their separate completion rewards.`,r.ready?'collectRollChests':null,'Collect roll rewards',locked);
 if(pending)section('Unopened loot drop','Choose Open now or Hold for the existing ×3 end-of-match bonus. Dismissing the window does not lose it.','inspectLootChest','Choose how to open',locked);
 if(stored)section(`${stored} stored loot chest${stored===1?'':'s'}`,match?'Held loot opens with its existing ×3 rewards at the end of the solo battle. These chests are not on a short timer.':'Open stored loot with the existing ×3 held-chest rewards. Gold and shards depend on the chest level and its saved multiplier.',match?null:'collectStoredChests','Open stored loot',locked);
 if(locked)section('Battle keeps running',window.FBNext?.active?'Existing offline chests are safe. Collect them from Home after this online match.':'Finish the current roll or reward choice to collect safely.');
 const err=document.createElement('p');err.id='chestInboxError';err.setAttribute('role','status');pane.append(err);
 const run=fn=>{try{if(waiting())return;fn();chestKey='';refreshBadges();}catch(e){$('chestInboxError').textContent='Your chests are still saved. '+e.message;SFX.error();}};
 $('collectRollChests')?.addEventListener('click',()=>run(()=>claimRollTrack()));
 $('inspectLootChest')?.addEventListener('click',()=>run(()=>{close('chestInbox');openChest(chestFrom||{name:'An enemy'});}));
 $('collectStoredChests')?.addEventListener('click',()=>run(()=>{
  if(M&&!M.lobby&&!M.ended)return;
  let gold=0,shards=0;atomicEconomy(()=>{const items=SAVE.chests.splice(0);for(const c of items){const reward=rollChest(3,c);grantChest(reward);gold+=reward.gold;shards+=reward.shards;}});
  SFX.chest();toast(`Stored loot collected: +${fmt(gold)} gold · +${fmt(shards)} shards`,'reward');
 }));
 let later=box.querySelector('footer button');if(!later){later=document.createElement('button');later.textContent='Later — keep saved';later.onclick=()=>close('chestInbox');box.querySelector('footer').append(later);}pane.scrollTop=scroll;
}
function openSound(){audioOpener=document.activeElement;const box=modal('soundSettings','Sound studio');const p=SFX.volumes;
 box.querySelector('.comfort-scroll').innerHTML=`<p class="comfort-note">Original weapon, impact, magic and menu sounds. Combat and interface levels can be adjusted separately.</p>${[['master','Master volume'],['combat','Combat & spells'],['ui','Menus & rewards']].map(([key,label])=>`<label class="audio-level" for="audio-${key}"><span>${label}<output id="audioValue-${key}">${Math.round(p[key]*100)}%</output></span><input id="audio-${key}" data-audio-level="${key}" type="range" min="0" max="100" step="1" value="${Math.round(p[key]*100)}"></label>`).join('')}<button id="audioMute"></button><p id="audioStatus" class="audio-status" role="status" aria-live="polite"></p><h3>Try the sounds</h3><div class="audio-previews"><button data-preview="sword">Sword</button><button data-preview="crit">Critical hit</button><button data-preview="bulwark">Bulwark</button><button data-preview="horn">War Horn</button><button data-preview="surge">Arcane Surge</button><button data-preview="menuOpen">Menu</button></div><p class="comfort-note">Sound respects your mute setting and stops when the game is in the background.</p>`;
 const status=(msg)=>{const el=$('audioStatus');if(el)el.textContent=msg;};
 const paint=()=>{const b=$('audioMute'),d=SFX.diagnostics;b.textContent=SFX.muted?'Unmute all sounds':'Mute all sounds';b.setAttribute('aria-pressed',String(SFX.muted));status(SFX.muted?'Sound is muted. Tap Unmute, then try a sample.':d.state==='running'?'Audio ready. Tap a sample to hear it.':d.lastError||'Tap any sample once to enable audio.');};paint();
 box.querySelectorAll('[data-audio-level]').forEach(input=>{input.oninput=()=>{const key=input.dataset.audioLevel;SFX.setVolumes({[key]:Number(input.value)/100});$('audioValue-'+key).textContent=input.value+'%';paint();};});
 $('audioMute').onclick=()=>{SFX.toggle();paint();document.querySelectorAll('.mute').forEach(b=>b.textContent=SFX.muted?'🔇':'🔊');};
 box.querySelectorAll('[data-preview]').forEach(b=>b.onclick=()=>{const cue=b.dataset.preview,label=b.textContent,vol=SFX.volumes,bus=cue==='menuOpen'?'ui':'combat';b.classList.add('playing');setTimeout(()=>b.classList.remove('playing'),260);
  if(SFX.muted){status('Sound is muted. Tap Unmute all sounds first.');return;}
  if(vol.master<=0||vol[bus]<=0){status((vol.master<=0?'Master volume':bus==='ui'?'Menus & rewards':'Combat & spells')+' is at 0%. Raise it to hear this sample.');return;}
  const accepted=SFX.play(cue,{group:'preview:'+cue});
  status(accepted?`Starting ${label}…`:'Audio could not start yet. Tap this sample again.');
  SFX.unlock().then(ok=>{const d=SFX.diagnostics;if(SFX.muted)return status('Sound is muted.');if(ok||d.state==='running')status(`Playing ${label}. If it is still silent, check your phone media volume.`);else status(d.lastError||'Chrome blocked audio. Tap a sample again.');});
 });
 box.querySelector('footer').innerHTML='<button id="soundDone">Done</button>';$('soundDone').onclick=()=>close('soundSettings');box.hidden=false;SFX.unlock().then(()=>paint());SFX.menuOpen();box.querySelector('.comfort-close').focus({preventScroll:true});
}
function install(){
 const wallet=document.querySelector('.wallet');addButton(wallet,'homeChests',icons.chest+'<b>0</b>','Saved chests',openChests);addButton(wallet,'homeAudio',icons.audio,'Sound settings',openSound);
 const tools=$('battleTools');addButton(tools,'battleChests',icons.chest+'<span>Chests</span><b>0</b>','Saved chests',openChests);
 const map=$('warHead');addButton(map,'mapChests',icons.chest+'<b>0</b>','Saved chests',openChests);
 const later=document.createElement('button');later.id='chestLater';later.textContent='Decide later — keep saved';later.onclick=()=>{$('chestUI').hidden=true;refreshBadges();SFX.menuClose();};$('chestUI').querySelector('.panel').append(later);
 modal('chestInbox','Your chests');modal('soundSettings','Sound studio');refreshBadges();
}
window.FateboundUX={openChests,openSound,refreshBadges,close};install();
// One delegated menu feedback listener. It never prevents, captures or stops input.
document.addEventListener('click',e=>{const b=e.target.closest?.('button');if(!b||b.disabled||b.closest('#soundSettings'))return;
 if(b.matches('#roll,#rally,#ultBar,[data-cast],#parry,#battleCoach button,#qte button'))return;
 if(b.matches('[data-equip],[data-char]'))SFX.equip();else SFX.tap();});
addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' ')SFX.unlock();},{passive:true});
})();
