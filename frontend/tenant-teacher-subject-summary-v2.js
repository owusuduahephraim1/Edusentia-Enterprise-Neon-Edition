(() => {
  "use strict";

  if (window.__EDUSENTIA_TEACHER_SUBJECT_SUMMARY_V2__) return;
  window.__EDUSENTIA_TEACHER_SUBJECT_SUMMARY_V2__ = true;

  const text = node => String(node?.textContent || "").trim();
  const keyOf = value => String(value || "").trim().toLocaleLowerCase();
  let scheduled = false;

  function applyCompactTeacherSubjects() {
    const content = document.getElementById("content");
    const pageTitle = document.getElementById("pageTitle");
    if (!content || text(pageTitle) !== "My Profile") return;

    const heading = [...content.querySelectorAll(".section-title h4, h4")]
      .find(node => text(node) === "Subject assignments");
    if (!heading) return;

    const sectionTitle = heading.closest(".section-title") || heading;
    const chipList = sectionTitle.nextElementSibling;
    if (!chipList?.classList.contains("chip-list")) return;

    const chips = [...chipList.querySelectorAll(":scope > .chip")];
    if (!chips.length) return;

    const uniqueNames = [];
    const seen = new Set();
    for (const chip of chips) {
      const raw = text(chip);
      const parts = raw.split("•");
      const subjectName = (parts.length > 1 ? parts.slice(1).join("•") : raw).trim();
      const subjectKey = keyOf(subjectName);
      if (!subjectName || seen.has(subjectKey)) continue;
      seen.add(subjectKey);
      uniqueNames.push(subjectName);
    }

    const currentNames = chips.map(text);
    const alreadyCompact = currentNames.length === uniqueNames.length &&
      currentNames.every((value, index) => value === uniqueNames[index]);

    if (!alreadyCompact) {
      chipList.replaceChildren(...uniqueNames.map(subjectName => {
        const chip = document.createElement("span");
        chip.className = "chip";
        chip.textContent = subjectName;
        return chip;
      }));
    }

    const metric = [...content.querySelectorAll(".metric.maturity-metric, .metric")]
      .find(node => text(node.querySelector("span")) === "Subject assignments");
    const count = metric?.querySelector("strong");
    if (count && text(count) !== String(uniqueNames.length)) count.textContent = String(uniqueNames.length);
  }

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      applyCompactTeacherSubjects();
    });
  }

  function start() {
    const content = document.getElementById("content");
    if (!content) return;
    new MutationObserver(schedule).observe(content, { childList: true, subtree: true });
    schedule();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
  window.addEventListener("pageshow", schedule, { passive: true });
})();
