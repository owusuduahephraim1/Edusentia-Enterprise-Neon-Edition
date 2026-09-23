(() => {
  "use strict";

  if (window.__EDUSENTIA_TEACHER_SUBJECT_SUMMARY_V1__) return;
  window.__EDUSENTIA_TEACHER_SUBJECT_SUMMARY_V1__ = true;

  const PROFILE_TITLE = "My Profile";
  const SUBJECT_HEADING = "Subject assignments";
  let scheduled = false;

  const text = node => String(node?.textContent || "").trim();
  const keyOf = value => String(value || "").trim().toLocaleLowerCase();

  function compactTeacherSubjectSummary() {
    const content = document.getElementById("content");
    const pageTitle = document.getElementById("pageTitle");
    if (!content || text(pageTitle) !== PROFILE_TITLE) return;

    const heading = [...content.querySelectorAll("h4")]
      .find(node => text(node) === SUBJECT_HEADING);
    if (!heading) return;

    const chipRow = heading.nextElementSibling;
    if (!chipRow?.classList.contains("chip-row")) return;

    const pills = [...chipRow.querySelectorAll(":scope > .pill")];
    if (!pills.length) return;

    const uniqueNames = [];
    const seen = new Set();

    for (const pill of pills) {
      const raw = text(pill);
      const separator = raw.indexOf("•");
      const subjectName = (separator >= 0 ? raw.slice(separator + 1) : raw).trim();
      const subjectKey = keyOf(subjectName);
      if (!subjectName || seen.has(subjectKey)) continue;
      seen.add(subjectKey);
      uniqueNames.push(subjectName);
    }

    const alreadyCompact =
      pills.length === uniqueNames.length &&
      pills.every((pill, index) => text(pill) === uniqueNames[index]);

    if (!alreadyCompact) {
      chipRow.replaceChildren(...uniqueNames.map(subjectName => {
        const pill = document.createElement("span");
        pill.className = "pill";
        pill.textContent = subjectName;
        return pill;
      }));
    }

    const metric = [...content.querySelectorAll(".metric-card")]
      .find(card => text(card.querySelector("span")) === SUBJECT_HEADING);
    const count = metric?.querySelector("strong");
    if (count && text(count) !== String(uniqueNames.length)) {
      count.textContent = String(uniqueNames.length);
    }
  }

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      compactTeacherSubjectSummary();
    });
  }

  function start() {
    const content = document.getElementById("content");
    if (!content) return;
    new MutationObserver(schedule).observe(content, { childList: true, subtree: true });
    schedule();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
