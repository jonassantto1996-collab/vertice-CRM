import {createHmac,timingSafeEqual} from 'node:crypto';
export function validSignature(raw,signature,secret){
 if(!secret||!/^sha256=[a-f0-9]{64}$/.test(signature||''))return false;
 const expected=createHmac('sha256',secret).update(raw).digest();
 return timingSafeEqual(Buffer.from(signature.slice(7),'hex'),expected);
}
export function normalizeMeta(body){
 const out=[];
 for(const entry of body.entry||[]){
  if(body.object==='instagram')for(const item of entry.messaging||[]){
   const m=item.message;if(!m?.mid||m.is_echo||m.is_deleted||!item.sender?.id||!item.recipient?.id)continue;
   out.push({provider:'instagram',externalId:String(item.recipient.id),key:`ig:${m.mid}`,payload:{source:'Instagram',name:'Contato do Instagram',contactKey:`ig:${item.recipient.id}:${item.sender.id}`,message:String(m.text||'[Mensagem com mídia]').slice(0,6000)}});
  }
  if(body.object==='whatsapp_business_account')for(const change of entry.changes||[]){
   const v=change.value;if(!v?.metadata?.phone_number_id)continue;
   for(const m of v.messages||[]){if(!m.id||!m.from)continue;const profile=v.contacts?.find(c=>c.wa_id===m.from)?.profile;
    out.push({provider:'whatsapp',externalId:String(v.metadata.phone_number_id),key:`wa:${m.id}`,payload:{source:'WhatsApp',name:profile?.name||'Contato do WhatsApp',phone:m.from,contactKey:`wa:${v.metadata.phone_number_id}:${m.from}`,message:String(m.text?.body||`[Mensagem ${m.type||'com mídia'}]`).slice(0,6000)}});
   }
  }
 }
 return out;
}
