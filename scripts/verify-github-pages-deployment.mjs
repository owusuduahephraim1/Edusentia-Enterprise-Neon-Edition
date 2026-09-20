import fs from "node:fs";import path from "node:path";
const fail=m=>{console.error(`GitHub Pages verification FAILED: ${m}`);process.exitCode=1};
if(fs.existsSync("CNAME")||fs.existsSync("frontend/CNAME"))fail("CNAME must not exist");
const cfg=fs.readFileSync("frontend/config.js","utf8"),manifest=JSON.parse(fs.readFileSync("frontend/manifest.webmanifest","utf8"));
if(!cfg.includes("repositoryBasePath"))fail("repository base path is not configurable");
if(manifest.start_url!=="./"||manifest.scope!=="./")fail("PWA must use repository-relative start_url and scope");
for(const root of ["frontend"]){for(const file of walk(root)){if(!/\.(js|html|css|json|webmanifest)$/i.test(file))continue;const t=fs.readFileSync(file,"utf8");if(/postgres(?:ql)?:\/\//i.test(t)||/DATABASE_URL|SESSION_PEPPER|R2_SECRET/i.test(t))fail(`server secret marker in ${file}`)}}
function walk(d){return fs.readdirSync(d,{withFileTypes:true}).flatMap(e=>{const p=path.join(d,e.name);return e.isDirectory()?walk(p):[p]})}
if(!process.exitCode)console.log("GitHub Pages deployment verification passed.");
