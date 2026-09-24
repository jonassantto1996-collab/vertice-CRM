import {timingSafeEqual} from 'node:crypto';
import {drain} from '@/lib/worker';
import {reply} from '@/lib/http';
export const dynamic='force-dynamic';
export async function GET(req:Request){const expected=`Bearer ${process.env.CRON_SECRET||''}`,actual=req.headers.get('authorization')||'';if(!process.env.CRON_SECRET||actual.length!==expected.length||!timingSafeEqual(Buffer.from(actual),Buffer.from(expected)))return reply({error:'Não autorizado'},401);try{return reply(await drain())}catch{return reply({error:'Worker indisponível'},503)}}
