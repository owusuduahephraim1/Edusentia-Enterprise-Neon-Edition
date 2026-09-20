import { scryptAsync } from "@noble/hashes/scrypt.js";
import { bytesToHex, hexToBytes, utf8ToBytes } from "@noble/hashes/utils.js";
const SCRYPT={N:2**15,r:8,p:1,dkLen:32,maxmem:40*1024*1024};

function constantTimeEqual(a:Uint8Array,b:Uint8Array){
  if(a.length!==b.length)return false;
  let diff=0;
  for(let i=0;i<a.length;i++)diff|=a[i]^b[i];
  return diff===0;
}

export function randomToken(bytes=32){const a=new Uint8Array(bytes);crypto.getRandomValues(a);return bytesToHex(a);}
export async function sha256Hex(value:string){const b=await crypto.subtle.digest("SHA-256",utf8ToBytes(value));return bytesToHex(new Uint8Array(b));}
export async function passwordHash(password:string,saltHex?:string){
  const salt=saltHex?hexToBytes(saltHex):(()=>{const x=new Uint8Array(16);crypto.getRandomValues(x);return x;})();
  const key=await scryptAsync(utf8ToBytes(password),salt,SCRYPT);
  return {algorithm:"scrypt-n32768-r8-p1",salt:bytesToHex(salt),hash:bytesToHex(key)};
}
export async function verifyPassword(password:string,saltHex:string,expectedHex:string){
  try{
    const actual=await passwordHash(password,saltHex);
    return constantTimeEqual(hexToBytes(actual.hash),hexToBytes(expectedHex));
  }catch{
    return false;
  }
}
