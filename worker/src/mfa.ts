import type { Env } from "./types";
import { sha256Hex } from "./crypto";

const B32="ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const enc=new TextEncoder();
const dec=new TextDecoder();

function b64url(bytes:Uint8Array){let s="";for(const b of bytes)s+=String.fromCharCode(b);return btoa(s).replaceAll("+","-").replaceAll("/","_").replace(/=+$/,"");}
function unb64url(value:string){const normalized=value.replaceAll("-","+").replaceAll("_","/")+"=".repeat((4-value.length%4)%4);const s=atob(normalized);return Uint8Array.from(s,c=>c.charCodeAt(0));}

function base32Encode(bytes:Uint8Array){
  let bits=0,value=0,out="";
  for(const byte of bytes){value=(value<<8)|byte;bits+=8;while(bits>=5){out+=B32[(value>>>(bits-5))&31];bits-=5;}}
  if(bits>0)out+=B32[(value<<(5-bits))&31];
  return out;
}
function base32Decode(value:string){
  let bits=0,buffer=0;const out:number[]=[];
  for(const ch of value.toUpperCase().replace(/=|\s|-/g,"")){
    const n=B32.indexOf(ch);if(n<0)throw new Error("invalid_base32");
    buffer=(buffer<<5)|n;bits+=5;
    if(bits>=8){out.push((buffer>>>(bits-8))&255);bits-=8;}
  }
  return new Uint8Array(out);
}

async function mfaKey(env:Env){
  const material=await crypto.subtle.digest("SHA-256",enc.encode("edusentia:mfa:v1:"+env.SESSION_PEPPER));
  return crypto.subtle.importKey("raw",material,{name:"AES-GCM"},false,["encrypt","decrypt"]);
}

export function generateTotpSecret(){
  const bytes=new Uint8Array(20);crypto.getRandomValues(bytes);return base32Encode(bytes);
}
export async function encryptTotpSecret(env:Env,secret:string){
  const iv=new Uint8Array(12);crypto.getRandomValues(iv);const key=await mfaKey(env);
  const cipher=await crypto.subtle.encrypt({name:"AES-GCM",iv},key,enc.encode(secret));
  return `v1.${b64url(iv)}.${b64url(new Uint8Array(cipher))}`;
}
export async function decryptTotpSecret(env:Env,value:string){
  const [version,ivRaw,cipherRaw]=String(value||"").split(".");
  if(version!=="v1"||!ivRaw||!cipherRaw)throw new Error("invalid_mfa_secret");
  const key=await mfaKey(env);
  const plain=await crypto.subtle.decrypt({name:"AES-GCM",iv:unb64url(ivRaw)},key,unb64url(cipherRaw));
  return dec.decode(plain);
}
async function totpAt(secret:string,counter:number){
  const key=await crypto.subtle.importKey("raw",base32Decode(secret),{name:"HMAC",hash:"SHA-1"},false,["sign"]);
  const msg=new Uint8Array(8);new DataView(msg.buffer).setBigUint64(0,BigInt(counter),false);
  const mac=new Uint8Array(await crypto.subtle.sign("HMAC",key,msg));
  const offset=mac[mac.length-1]&15;
  const binary=((mac[offset]&127)<<24)|(mac[offset+1]<<16)|(mac[offset+2]<<8)|mac[offset+3];
  return String(binary%1_000_000).padStart(6,"0");
}
export async function verifyTotp(secret:string,codeRaw:string,now=Date.now()){
  const code=String(codeRaw||"").replace(/\s/g,"");
  if(!/^\d{6}$/.test(code))return false;
  const counter=Math.floor(now/30000);
  for(const drift of [-1,0,1])if(await totpAt(secret,counter+drift)===code)return true;
  return false;
}
export function otpauthUri(secret:string,email:string,tenantName:string){
  const issuer="Edusentia Enterprise";
  const label=encodeURIComponent(`${issuer}:${email}`);
  const params=new URLSearchParams({secret,issuer,algorithm:"SHA1",digits:"6",period:"30"});
  if(tenantName)params.set("organization",tenantName);
  return `otpauth://totp/${label}?${params.toString()}`;
}
export function generateRecoveryCodes(count=8){
  const alphabet="ABCDEFGHJKLMNPQRSTUVWXYZ23456789",codes:string[]=[];
  for(let i=0;i<count;i++){
    const bytes=new Uint8Array(12);crypto.getRandomValues(bytes);
    const raw=Array.from(bytes,b=>alphabet[b&31]).join("");
    codes.push(`${raw.slice(0,4)}-${raw.slice(4,8)}-${raw.slice(8,12)}`);
  }
  return codes;
}
export function normalizeRecoveryCode(code:string){return String(code||"").toUpperCase().replace(/[^A-Z2-9]/g,"");}
export async function recoveryCodeHash(env:Env,code:string){return sha256Hex(`edusentia:recovery:v1:${normalizeRecoveryCode(code)}:${env.SESSION_PEPPER}`);}
