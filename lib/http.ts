import {NextResponse} from 'next/server';
export const reply=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
export async function body(req:Request,max=30000){
 const reader=req.body?.getReader();if(!reader)throw new Error('Corpo ausente');
 let size=0;const chunks=[];while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>max){await reader.cancel();throw new Error('Dados muito extensos');}chunks.push(value);}
 return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
export function sameOrigin(req:Request){const origin=req.headers.get('origin');return !origin||origin===new URL(req.url).origin||origin===process.env.NEXT_PUBLIC_SITE_URL;}
