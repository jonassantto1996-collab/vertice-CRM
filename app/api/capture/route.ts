import {serviceClient} from '@/lib/supabase/server';
import {reply,body} from '@/lib/http';
import {after} from 'next/server';
import {drain} from '@/lib/worker';
export async function POST(req:Request){try{
 const token=req.headers.get('authorization')?.replace(/^Bearer /,'');const key=req.headers.get('idempotency-key');if(!token)return reply({error:'Token obrigatório'},401);if(!key||key.length>200)return reply({error:'Idempotency-Key obrigatório (até 200 caracteres)'},400);
 const b=await body(req);if(!String(b.name||'').trim())return reply({error:'Informe o nome'},400);
 const payload={name:String(b.name).slice(0,120),phone:String(b.phone||'').slice(0,30),email:String(b.email||'').slice(0,200),business:String(b.business||'').slice(0,120),message:String(b.message||'').slice(0,6000),source:'Site',utm_campaign:String(b.utm_campaign||'').slice(0,200),contactKey:b.phone?'phone:'+String(b.phone).replace(/\D/g,''):b.email?'email:'+String(b.email).trim().toLowerCase():undefined};
 const db=serviceClient();const {data,error}=await db.rpc('crm_capture',{p_token:token,p_key:key,p_payload:payload});if(error){if(error.code==='P0429')return new Response(JSON.stringify({error:'Limite de entradas atingido. Repita com a mesma Idempotency-Key.'}),{status:429,headers:{'Content-Type':'application/json','Retry-After':'60','Cache-Control':'no-store'}});return reply({error:'Captura recusada'},400);}
 after(async()=>{try{await drain()}catch{console.error('CRM worker pending retry')}});return reply({accepted:true,id:data},202);
 }catch{return reply({error:'Integração indisponível ou dados inválidos'},503)}}
