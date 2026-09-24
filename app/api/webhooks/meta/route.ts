import {serviceClient} from '@/lib/supabase/server';
import {reply} from '@/lib/http';
import {validSignature,normalizeMeta} from '@/lib/meta.mjs';
import {drain} from '@/lib/worker';
import {after} from 'next/server';
export const dynamic='force-dynamic';
export async function GET(req:Request){const p=new URL(req.url).searchParams;if(process.env.META_VERIFY_TOKEN&&p.get('hub.mode')==='subscribe'&&p.get('hub.verify_token')===process.env.META_VERIFY_TOKEN)return new Response(p.get('hub.challenge'),{headers:{'Cache-Control':'no-store'}});return reply({error:'Verificação recusada'},403);}
export async function POST(req:Request){
 if(!process.env.META_APP_SECRET)return reply({error:'Canal não configurado'},503);
 try{const reader=req.body?.getReader();if(!reader)return reply({error:'Corpo ausente'},400);let n=0;const parts=[];while(true){const {done,value}=await reader.read();if(done)break;n+=value.byteLength;if(n>1000000){await reader.cancel();return reply({error:'Payload excedido'},413)}parts.push(value)}const raw=Buffer.concat(parts);
 if(!validSignature(raw,req.headers.get('x-hub-signature-256'),process.env.META_APP_SECRET))return reply({error:'Assinatura inválida'},401);
 const events=normalizeMeta(JSON.parse(raw.toString('utf8')));if(events.length>100)return reply({error:'Lote excedido'},413);const db=serviceClient();
 // Bind the signed recipient account to the tenant; never trust a tenant ID in the webhook.
 const {data:channels,error}=await db.from('crm_channels').select('company_id,provider,external_id').eq('enabled',true).in('external_id',[...new Set(events.map((e:any)=>e.externalId))]);if(error)throw error;
 const jobs=events.flatMap((e:any)=>{const channel=channels?.find(c=>c.provider===e.provider&&c.external_id===e.externalId);return channel?[{company_id:channel.company_id,dedup_key:e.key,payload:e.payload}]:[]});
 if(jobs.length){const {error}=await db.from('crm_jobs').upsert(jobs,{onConflict:'company_id,dedup_key',ignoreDuplicates:true});if(error)throw error;after(async()=>{try{await drain()}catch{console.error('CRM Meta batch queued for retry')}});}
 return reply({received:true});
 }catch{return reply({error:'Não foi possível persistir o evento'},503)}
}
