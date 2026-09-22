import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("long operational lists are vertically bounded and scrollable",()=>{
  const css=read("frontend/style.css");
  assert.match(css,/bounded vertical scrolling for all operational lists/);
  assert.match(css,/\.panel>\.table-wrap,[\s\S]*max-height:clamp\(300px,54vh,560px\)/);
  assert.match(css,/overflow-y:auto/);
  assert.match(css,/scrollbar-gutter:stable both-edges/);
  assert.match(css,/position:sticky/);
});

test("Audit Trail exposes only System Administrator permanent reset controls",()=>{
  const ui=read("frontend/parity-audit-security-finance.js");
  const sql=read("database/reference-compat/0049y_audit_permanent_reset.sql");
  assert.match(ui,/Reset all audit history/);
  assert.match(ui,/Reset recent events/);
  assert.match(ui,/Delete all archives/);
  assert.match(ui,/RESET ACTIVE AUDIT/);
  assert.match(ui,/DELETE ALL AUDIT ARCHIVES/);
  assert.match(ui,/RESET ALL AUDIT HISTORY/);
  assert.match(ui,/isSystemAdmin\(\)/);
  assert.match(sql,/if not public\.is_system_admin\(\)/);
  assert.match(sql,/perform public\.require_sensitive_access\(\)/);
  assert.match(sql,/truncate table public\.audit_log restart identity/);
  assert.match(sql,/delete from public\.audit_log_archive_entries/);
  assert.match(sql,/delete from public\.audit_log_archives/);
  assert.match(sql,/PERMANENT_RESET_AUDIT_HISTORY/);
});

test("audit reset remains on the certified fixed RPC surface",()=>{
  const registry=read("worker/src/certified-rpc-registry.ts");
  assert.match(registry,/"reset_audit_log": \{/);
  assert.match(registry,/"confirmation_text"/);
  assert.match(registry,/"type": "text"/);
});
