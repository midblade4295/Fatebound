#!/usr/bin/env node
'use strict';
// Local administrator-only aggregate report. No network service or personal identifiers output.
const fs=require('node:fs');
const file=process.argv[2];if(!file){console.error('Usage: node metrics.js /path/to/arena.json');process.exit(2);}
const store=JSON.parse(fs.readFileSync(file,'utf8')),users=Object.values(store.users),now=Date.now(),DAY=86400000;
const matchReceipts=u=>Object.values(u.receipts||{}).filter(r=>!r.id.startsWith('guild:'));
function cohort(days){const eligible=users.filter(u=>now-u.createdAt>=(days+1)*DAY);const returned=eligible.filter(u=>Object.keys(u.days||{}).includes(new Date(u.createdAt+days*DAY).toISOString().slice(0,10)));return {eligibleDevices:eligible.length,completedBattleOnUtcCohortDay:returned.length,rate:eligible.length?returned.length/eligible.length:null};}
console.log(JSON.stringify({generatedAt:new Date(now).toISOString(),guestDevices:users.length,activeDevicesLast7Days:users.filter(u=>now-u.lastSeen<=7*DAY).length,devicesWithCompletedBattle:users.filter(u=>matchReceipts(u).length).length,devicesWithSecondCompletedBattle:users.filter(u=>matchReceipts(u).length>=2).length,claimedEligibleBattleReceipts:users.reduce((n,u)=>n+matchReceipts(u).filter(r=>r.claimed&&r.eligible).length,0),day1:cohort(1),day7:cohort(7),limitations:'Guest-device counts, not unique humans. D1/D7 count a completed battle on the exact UTC cohort day, not any app open. No A/B causality or monetization claims.'},null,2));
