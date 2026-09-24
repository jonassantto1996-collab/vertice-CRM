import {sessionClient} from '@/lib/supabase/server';
import {NextResponse} from 'next/server';
import type {EmailOtpType} from '@supabase/supabase-js';
export async function GET(req:Request){const url=new URL(req.url),db=await sessionClient();const hash=url.searchParams.get('token_hash'),type=url.searchParams.get('type') as EmailOtpType;
 if(hash&&['signup','email','recovery','invite'].includes(type)){const {error}=await db.auth.verifyOtp({token_hash:hash,type});if(!error)return NextResponse.redirect(new URL(type==='recovery'?'/?recover=1':'/',url.origin));}
 const code=url.searchParams.get('code');if(code){const {error}=await db.auth.exchangeCodeForSession(code);if(!error)return NextResponse.redirect(new URL(url.searchParams.get('next')==='recover'?'/?recover=1':'/',url.origin));}
 return NextResponse.redirect(new URL('/?auth_error=1',url.origin));}
