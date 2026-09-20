import fs from "node:fs";import path from "node:path";
const roots=["frontend","worker/src","database/migrations"];const forbidden=[/supabase\.co/i,/@supabase\//i,/createClient\s*\(/,/supabaseUrl/i,/supabaseAnonKey/i,/service_role/i,/functions\/v1/i];let failures=[];
for(const root of roots){for(const file of walk(root)){const text=fs.readFileSync(file,"utf8");for(const re of forbidden)if(re.test(text))failures.push(`${file}: ${re}`);}}
function walk(dir){if(!fs.existsSync(dir))return[];return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>{const p=path.join(dir,e.name);return e.isDirectory()?walk(p):/\.(js|mjs|ts|sql|html|jsonc?)$/i.test(e.name)?[p]:[]})}
if(failures.length){console.error("Forbidden legacy runtime references detected:\n"+failures.join("\n"));process.exit(1)}console.log("No Supabase runtime dependency detected in production source.");
