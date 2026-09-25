'use strict';
const zlib=require('node:zlib'),{promisify}=require('node:util');
const gzip=promisify(zlib.gzip),brotli=promisify(zlib.brotliCompress);
function encoding(header){
 const q=new Map();
 for(const part of String(header||'').toLowerCase().split(',')){
  const [name,...params]=part.trim().split(';');if(!name)continue;
  const p=params.map(x=>x.trim()).find(x=>x.startsWith('q='));const quality=p?Number(p.slice(2)):1;
  q.set(name,Number.isFinite(quality)&&quality>=0&&quality<=1?quality:0);
 }
 const value=k=>q.has(k)?q.get(k):(q.get('*')||0);
 const candidates=['br','gzip'].filter(k=>value(k)>0).sort((a,b)=>value(b)-value(a));
 return candidates[0]||null;
}
async function compress(buffer,header){
 const type=encoding(header);if(!type||buffer.length<256)return {body:buffer,encoding:null};
 const body=type==='br'?await brotli(buffer,{params:{[zlib.constants.BROTLI_PARAM_QUALITY]:4}}):await gzip(buffer,{level:6});
 return body.length<buffer.length?{body,encoding:type}:{body:buffer,encoding:null};
}
module.exports={encoding,compress};
