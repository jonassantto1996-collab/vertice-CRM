import 'server-only';
import {createServerClient} from '@supabase/ssr';
import {createClient} from '@supabase/supabase-js';
import {cookies} from 'next/headers';

// Public project identifiers already distributed in .env.example. They confer
// no privileged access: every user operation is protected by Auth and RLS.
const defaultProjectUrl='https://jucsyhcamxwgkshzkazv.supabase.co';
const defaultPublishableKey='sb_publishable_bfy4Yq_hLeFcaT9o3Ldjzw_kL-EwJ00';
function projectUrl(){return process.env.NEXT_PUBLIC_SUPABASE_URL?.trim()||defaultProjectUrl;}
function publishableKey(){
 const configured=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim()||process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim();
 if(configured)return configured;
 if(projectUrl()===defaultProjectUrl)return defaultPublishableKey;
 throw new Error('Configure a chave publicável para o projeto Supabase selecionado.');
}
export async function sessionClient(){
 const jar=await cookies();
 return createServerClient(projectUrl(),publishableKey(),{cookies:{
  getAll:()=>jar.getAll(),
  setAll:values=>values.forEach(({name,value,options})=>jar.set(name,value,options)),
 }});
}
export function serviceClient(){
 // Privileged credentials never have a source-code fallback.
 const secret=process.env.SUPABASE_SECRET_KEY;
 if(!secret)throw new Error('Integração pendente de configuração do servidor.');
 return createClient(projectUrl(),secret,{auth:{persistSession:false,autoRefreshToken:false}});
}
