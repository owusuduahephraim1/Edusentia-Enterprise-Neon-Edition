(() => {
  "use strict";

  function runtime() {
    return window.EdusentiaFinanceRuntime || null;
  }

  function currentRole() {
    return String(runtime()?.S?.role || runtime()?.S?.boot?.profile?.role || "");
  }

  function installParentDashboardRefinements() {
    if (window.EDS_PARENT_PUBLISHED_RESULTS_DASHBOARD_V1) return;
    window.EDS_PARENT_PUBLISHED_RESULTS_DASHBOARD_V1 = true;

    const content = document.getElementById("content");
    if (!content) return;

    let summary = null;
    let summaryPromise = null;
    let summaryLoadedAt = 0;
    let timer = 0;

    const setText = (node, value) => {
      if (!node) return;
      const next = String(value ?? "");
      if (String(node.textContent || "") !== next) node.textContent = next;
    };

    function isParentDashboard() {
      if (currentRole() !== "parent_guardian") return false;
      return [...content.querySelectorAll(".page-head h3")].some((node) => String(node.textContent || "").trim() === "Parent and Guardian Dashboard");
    }

    async function loadSummary(force = false) {
      const client = runtime()?.S?.client;
      if (!client || currentRole() !== "parent_guardian") return null;
      const fresh = summary && Date.now() - summaryLoadedAt < 60000;
      if (!force && fresh) return summary;
      if (summaryPromise) return summaryPromise;

      summaryPromise = client.rpc("list_my_children_reports").then(({ data, error }) => {
        summaryPromise = null;
        if (error) {
          console.warn("parent_published_results_summary_failed", error);
          return null;
        }
        const children = Array.isArray(data?.children) ? data.children : [];
        const reports = children.flatMap((child) => Array.isArray(child?.reports) ? child.reports.map((report) => ({ ...report, child })) : []);
        const averages = reports.map((entry) => Number(entry.average)).filter(Number.isFinite);
        summary = {
          children,
          reports,
          published: reports.length,
          average: averages.length ? averages.reduce((total, value) => total + value, 0) / averages.length : null,
        };
        summaryLoadedAt = Date.now();
        return summary;
      }).catch((error) => {
        summaryPromise = null;
        console.warn("parent_published_results_summary_failed", error);
        return null;
      });
      return summaryPromise;
    }

    function statCard(label) {
      return [...content.querySelectorAll(".stat-card")].find((card) => String(card.querySelector("span")?.textContent || "").trim() === label) || null;
    }

    function refineParentPeriodPanel(resultSummary) {
      const heading = [...content.querySelectorAll(".panel-header h3")].find((node) => String(node.textContent || "").trim() === "Current Academic Period");
      const panel = heading?.closest(".panel");
      const body = panel?.querySelector(".panel-body");
      if (!body) return;

      const published = Number(resultSummary?.published || 0);
      const desired = published > 0
        ? `<div class="empty parent-academic-record-note"><strong>${published} published report card${published === 1 ? "" : "s"} available</strong><span>Authorized academic records are read-only and can be opened from My Children.</span></div>`
        : '<div class="empty parent-academic-record-note"><strong>No published report cards yet</strong><span>Academic records will appear in My Children after the school publishes them.</span></div>';
      if (body.innerHTML !== desired) body.innerHTML = desired;
    }

    function refineParentResultsPanel(resultSummary) {
      const heading = [...content.querySelectorAll(".panel-header h3")].find((node) => ["Class Performance", "Latest Published Results"].includes(String(node.textContent || "").trim()));
      const panel = heading?.closest(".panel");
      const header = heading?.closest(".panel-header");
      const copy = header?.querySelector("p");
      const body = panel?.querySelector(".panel-body");
      if (!heading || !body) return;

      setText(heading, "Latest Published Results");
      setText(copy, "Most recent authorized report for each linked child");

      const children = Array.isArray(resultSummary?.children) ? resultSummary.children : [];
      const latest = children.map((child) => ({ child, report: Array.isArray(child?.reports) ? child.reports[0] : null })).filter((entry) => entry.report);
      let list = body.querySelector(".bar-list");
      if (!list) {
        body.innerHTML = '<div class="bar-list"></div>';
        list = body.querySelector(".bar-list");
      }
      if (!list) return;

      if (!latest.length) {
        const desired = '<div class="empty"><strong>No published results</strong></div>';
        if (list.innerHTML !== desired) list.innerHTML = desired;
        return;
      }

      list.innerHTML = "";
      latest.forEach(({ child, report }) => {
        const average = Number(report.average || 0);
        const row = document.createElement("div");
        row.className = "bar-item";
        const label = document.createElement("label");
        label.textContent = `${child.full_name || "Student"} • ${report.academic_year_name || ""} ${report.term_name || ""}`.trim();
        const track = document.createElement("div");
        track.className = "bar-track";
        const fill = document.createElement("span");
        fill.style.width = `${Math.max(0, Math.min(100, Number.isFinite(average) ? average : 0))}%`;
        track.appendChild(fill);
        const value = document.createElement("b");
        value.textContent = Number.isFinite(average) ? average.toLocaleString("en-GH", { minimumFractionDigits: 1, maximumFractionDigits: 1 }) : "—";
        row.append(label, track, value);
        list.appendChild(row);
      });
    }

    async function apply(force = false) {
      if (!isParentDashboard()) return;
      const resultSummary = await loadSummary(force);
      if (!resultSummary || !isParentDashboard()) return;

      const publishedCard = statCard("Published Reports");
      setText(publishedCard?.querySelector("strong"), resultSummary.published);

      const averageCard = statCard("Average");
      setText(averageCard?.querySelector("strong"), resultSummary.published > 0 && Number.isFinite(resultSummary.average)
        ? `${resultSummary.average.toLocaleString("en-GH", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`
        : "No results");

      refineParentPeriodPanel(resultSummary);
      refineParentResultsPanel(resultSummary);
    }

    function schedule(force = false) {
      clearTimeout(timer);
      timer = setTimeout(() => apply(force), 40);
    }

    const observer = new MutationObserver(() => schedule(false));
    observer.observe(content, { childList: true, subtree: true });
    window.addEventListener("pageshow", () => schedule(false), { passive: true });
    document.addEventListener("click", (event) => {
      if (event.target.closest("#refreshButton")) {
        summary = null;
        summaryPromise = null;
        summaryLoadedAt = 0;
        schedule(true);
      } else if (event.target.closest('.nav-item,[data-view="dashboard"]')) {
        schedule(false);
      }
    }, true);
    schedule(false);
  }

  function installParentNotificationRouting() {
    if (window.EDS_PARENT_NOTIFICATION_ROUTING_V1) return;
    window.EDS_PARENT_NOTIFICATION_ROUTING_V1 = true;
    const content = document.getElementById("content");
    if (!content) return;

    let timer = 0;
    function childrenNavigation() {
      return document.querySelector('.nav-item[data-view="children"]') ||
        [...document.querySelectorAll(".nav-item")].find((item) => String(item.textContent || "").trim().includes("My Children")) || null;
    }

    function refineButtons() {
      if (currentRole() !== "parent_guardian") return;
      content.querySelectorAll('[data-notification-report]').forEach((button) => {
        if (button.textContent !== "View in My Children") button.textContent = "View in My Children";
        button.setAttribute("aria-label", "View published report in My Children");
        button.dataset.parentNotificationRoute = "children";
      });
    }

    function schedule() {
      clearTimeout(timer);
      timer = setTimeout(refineButtons, 20);
    }

    document.addEventListener("click", (event) => {
      const button = event.target.closest?.('[data-notification-report]');
      if (!button || currentRole() !== "parent_guardian") return;
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      const nav = childrenNavigation();
      if (nav) nav.click();
      else console.warn("parent_notification_children_navigation_unavailable");
    }, true);

    const observer = new MutationObserver(schedule);
    observer.observe(content, { childList: true, subtree: true });
    window.addEventListener("pageshow", schedule, { passive: true });
    schedule();
  }

  installParentDashboardRefinements();
  installParentNotificationRouting();

  function loadRefinements() {
    if (window.EDS_STUDENT_PORTAL_V2_REFINEMENTS || document.querySelector('script[data-edusentia-student-portal-v2-refinements]')) return;
    const patch = document.createElement("script");
    patch.src = "tenant-student-portal-v2-refinements.js?edusentia=r40-student-calendar-context-v2";
    patch.defer = true;
    patch.dataset.edusentiaStudentPortalV2Refinements = "1";
    patch.addEventListener("error", () => console.error("student_portal_v2_refinements_load_failed"), { once: true });
    document.body.appendChild(patch);
  }

  if (window.EDS_STUDENT_PORTAL_V2) {
    loadRefinements();
    return;
  }

  const existing = document.querySelector('script[data-edusentia-student-portal-v2]');
  if (existing) {
    existing.addEventListener("load", loadRefinements, { once: true });
    return;
  }

  const script = document.createElement("script");
  script.src = "tenant-student-portal-v2.js?edusentia=r40-student-sidebar-v2-stable";
  script.defer = true;
  script.dataset.edusentiaStudentPortalV2 = "1";
  script.addEventListener("load", loadRefinements, { once: true });
  script.addEventListener("error", () => console.error("student_portal_v2_load_failed"), { once: true });
  document.body.appendChild(script);
})();
