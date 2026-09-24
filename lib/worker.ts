import 'server-only';
import {serviceClient} from './supabase/server';
export async function drain(){
 const db=serviceClient();const {data,error}=await db.rpc('crm_claim',{p_limit:10});if(error)throw error;
 let done=0,failed=0;
 for(const job of data||[]){const {error:e}=await db.rpc('crm_process',{p_id:job.id,p_lease:job.lease_token});if(e){failed++;await db.rpc('crm_retry',{p_id:job.id,p_lease:job.lease_token,p_error:'Falha no processamento; consultar logs do banco.'});}else done++;}
 return {done,failed};
}
