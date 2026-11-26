// Build an isolated Cloudflare Pages site for verify.edusentia.com.
// It intentionally contains NO administration, login, tenant workspace,
// native download bridge, application cookies, or deployment credentials.
// Usage: node scripts/build-verification-site.mjs
import { mkdirSync, rmSync, copyFileSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const repositoryRoot=resolve(dirname(fileURLToPath(import.meta.url)),"..");
const frontend=join(repositoryRoot,"frontend");
const dest=join(repositoryRoot,"dist","verification");

rmSync(dest,{recursive:true,force:true});
mkdirSync(join(dest,"assets"),{recursive:true});

for(const file of ["verify-card.js","verify-card.css"]){
  copyFileSync(join(frontend,file),join(dest,file));
}
copyFileSync(join(frontend,"assets","edusentia-mark.svg"),join(dest,"assets","edusentia-mark.svg"));

// Reuse the tested frontend verification component instead of maintaining
// a second copy of its card/document status logic.
let html=readFileSync(join(frontend,"verify-card.html"),"utf8");
if(!html.includes('<script src="config.js"></script><script src="verify-card.js"></script>'))
  throw new Error("The verification template script sequence has changed.");
html=html.replace(
  '<a href="./">Edusentia home</a>',
  '<a href="https://app.edusentia.com/">Edusentia application</a>'
);
writeFileSync(join(dest,"index.html"),html);
writeFileSync(join(dest,"verify-card.html"),html);

// Expose only a read-only public API origin. Full application configuration
// and private session credentials are intentionally excluded from the build.
writeFileSync(join(dest,"config.js"),[
  "// The standalone verification portal only uses token-bound public GET endpoints.",
  'window.EDS_MASTER_CONFIG=Object.freeze({apiBaseUrl:"https://api.edusentia.com"});',
  ""
].join("\n"));

writeFileSync(join(dest,"_headers"),[
  "/*",
  "  X-Content-Type-Options: nosniff",
  "  X-Frame-Options: DENY",
  "  Referrer-Policy: no-referrer",
  "  Permissions-Policy: camera=(), microphone=(), geolocation=()",
  "  X-Robots-Tag: noindex, nofollow, noarchive",
  "  Cache-Control: no-store",
  "  Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src https://api.edusentia.com; base-uri 'none'; object-src 'none'; form-action 'none'; frame-ancestors 'none'",
  ""
].join("\n"));
writeFileSync(join(dest,"robots.txt"),"User-agent: *\nDisallow: /\n");
console.log("Standalone document verification site built at dist/verification");
