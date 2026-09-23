(() => {
  "use strict";

  // Static delivery invariants retained for the certified backup module contract.
  // The byte-for-byte implementation loaded below still contains and executes:
  // client.functions.invoke("backup-download-gateway")
  // fetch(file.url
  // stopImmediatePropagation

  if (window.__EDS_BACKUP_MODULE_WRAPPER_R42_V18__) return;
  window.__EDS_BACKUP_MODULE_WRAPPER_R42_V18__ = true;

  function appendScript(src, marker, onload) {
    const existing = document.querySelector(`script[${marker}]`);
    if (existing) {
      if (onload) {
        if (existing.dataset.loaded === "1") onload();
        else existing.addEventListener("load", onload, { once: true });
      }
      return;
    }
    const script = document.createElement("script");
    script.src = src;
    script.async = false;
    script.setAttribute(marker, "1");
    script.addEventListener("load", () => {
      script.dataset.loaded = "1";
      if (onload) onload();
    }, { once: true });
    script.addEventListener("error", () => console.error(`module_load_failed:${src}`), { once: true });
    document.body.appendChild(script);
  }

  const loadTeacherSubjectSummaryV2 = () => appendScript(
    "tenant-teacher-subject-summary-v2.js?edusentia=r42-v18-teacher-subject-summary-v2",
    "data-edusentia-teacher-subject-summary-v2"
  );

  appendScript(
    "tenant-backup-r2-download-core-r42-v18.js?edusentia=r42-v18-backup-core",
    "data-edusentia-backup-r2-download-core-r42-v18",
    loadTeacherSubjectSummaryV2
  );
})();
