(() => {
  "use strict";
  if (window.EDS_STUDENT_PORTAL_V2_REFINEMENTS) return;
  window.EDS_STUDENT_PORTAL_V2_REFINEMENTS = true;

  const byText = (root, selector, text) => [...(root?.querySelectorAll?.(selector) || [])].find((node) => String(node.textContent || "").trim() === text);
  let calendarContext = null;
  let calendarPromise = null;
  let parentCalendarContext = null;
  let parentCalendarPromise = null;
  let parentCalendarLoadedAt = 0;

  function runtimeRole() {
    const runtime = window.EdusentiaFinanceRuntime;
    return String(runtime?.S?.role || runtime?.S?.boot?.profile?.role || "");
  }

  function setText(node, value) {
    if (!node) return;
    const next = String(value ?? "");
    if (String(node.textContent || "") !== next) node.textContent = next;
  }

  function prettyDate(value) {
    if (!value) return "";
    const date = new Date(`${value}T00:00:00`);
    if (Number.isNaN(date.getTime())) return String(value);
    return date.toLocaleDateString("en-GH", { day: "numeric", month: "short", year: "numeric" });
  }

  async function loadCalendarContext() {
    if (calendarContext) return calendarContext;
    if (calendarPromise) return calendarPromise;
    const runtime = window.EdusentiaFinanceRuntime;
    if (!runtime?.S?.client || runtimeRole() !== "student") return null;
    calendarPromise = runtime.S.client.rpc("get_academic_calendar_context").then(({ data, error }) => {
      calendarPromise = null;
      if (error) {
        console.warn("student_academic_calendar_context_failed", error);
        return null;
      }
      calendarContext = data || null;
      return calendarContext;
    }).catch((error) => {
      calendarPromise = null;
      console.warn("student_academic_calendar_context_failed", error);
      return null;
    });
    return calendarPromise;
  }

  async function loadParentCalendarContext(force = false) {
    const runtime = window.EdusentiaFinanceRuntime;
    if (!runtime?.S?.client || runtimeRole() !== "parent_guardian") return null;
    const fresh = parentCalendarContext && Date.now() - parentCalendarLoadedAt < 60000;
    if (!force && fresh) return parentCalendarContext;
    if (parentCalendarPromise) return parentCalendarPromise;

    parentCalendarPromise = runtime.S.client.rpc("get_academic_calendar_context").then(({ data, error }) => {
      parentCalendarPromise = null;
      if (error) {
        console.warn("parent_academic_calendar_context_failed", error);
        return null;
      }
      parentCalendarContext = data || null;
      parentCalendarLoadedAt = Date.now();
      return parentCalendarContext;
    }).catch((error) => {
      parentCalendarPromise = null;
      console.warn("parent_academic_calendar_context_failed", error);
      return null;
    });
    return parentCalendarPromise;
  }

  function refineOverview(root = document) {
    const quickHeading = byText(root, ".student-portal-panel-head h4", "Quick access");
    const quickPanel = quickHeading?.closest(".student-portal-panel");
    if (quickPanel) quickPanel.remove();

    root.querySelectorAll?.(".student-portal-grid").forEach((grid) => {
      const panels = [...grid.children].filter((child) => child.classList?.contains("student-portal-panel"));
      if (panels.length === 1 && panels[0].style.gridColumn !== "1 / -1") panels[0].style.gridColumn = "1 / -1";
    });
  }

  function refineProfile(root = document) {
    root.querySelectorAll?.(".student-portal-profile-card .student-portal-detail strong").forEach((value) => {
      if (String(value.textContent || "").trim() === "—") setText(value, "Not recorded");
    });

    const guardianHeading = byText(root, ".student-portal-profile-card h4", "Guardian Contact");
    const guardianCard = guardianHeading?.closest(".student-portal-profile-card");
    if (!guardianCard || guardianCard.dataset.emptyGuardianRefined === "1") return;

    const details = [...guardianCard.querySelectorAll(".student-portal-detail")];
    const contactRows = details.filter((row) => ["Guardian", "Phone", "Email"].includes(String(row.querySelector("span")?.textContent || "").trim()));
    const allMissing = contactRows.length === 3 && contactRows.every((row) => String(row.querySelector("strong")?.textContent || "").trim() === "Not recorded");
    if (!allMissing) return;

    contactRows.forEach((row) => row.remove());
    const note = document.createElement("div");
    note.className = "student-portal-missing-note";
    note.innerHTML = "<strong>No guardian contact is currently recorded for this student.</strong><span>Guardian details are maintained by the school through Student Management.</span>";
    guardianHeading.insertAdjacentElement("afterend", note);
    guardianCard.dataset.emptyGuardianRefined = "1";
  }

  function profileValue(root, label, value) {
    const studentHeading = byText(root, ".student-portal-profile-card h4", "Student Information");
    const card = studentHeading?.closest(".student-portal-profile-card");
    if (!card) return;
    const row = [...card.querySelectorAll(".student-portal-detail")].find((item) => String(item.querySelector("span")?.textContent || "").trim() === label);
    setText(row?.querySelector("strong"), value);
  }

  function upsertCalendarNote(target, id, title, copy) {
    if (!target) return;
    let note = document.getElementById(id);
    if (!note) {
      note = document.createElement("div");
      note.id = id;
      note.className = "student-portal-calendar-note";
      target.insertAdjacentElement("beforebegin", note);
    }
    const html = `<strong>${title}</strong><span>${copy}</span>`;
    if (note.innerHTML !== html) note.innerHTML = html;
  }

  function clearCalendarNote(id) {
    document.getElementById(id)?.remove();
  }

  function refineInactiveAttendanceMetric(root, context) {
    const metric = [...(root.querySelectorAll?.(".student-portal-metric") || [])].find((item) => String(item.querySelector("span")?.textContent || "").trim() === "Attendance");
    if (!metric || context?.term) return;
    setText(metric.querySelector("strong"), "No active term");
    setText(metric.querySelector("small"), context?.next_period ? `${context.next_period.term_name} begins ${prettyDate(context.next_period.term_start_date)}` : "No active term scheduled");
  }

  function refineAttendanceHistory(root, context) {
    const attendanceHeading = byText(root, ".student-portal-panel-head h4", "Attendance History");
    const attendancePanel = attendanceHeading?.closest(".student-portal-panel");
    const table = attendancePanel?.querySelector("table");
    const tbody = table?.tBodies?.[0];
    if (!attendancePanel || !tbody) return { panel: attendancePanel, visibleRows: 0 };

    const emptyRow = tbody.querySelector("tr.student-portal-attendance-history-empty");
    const rows = [...tbody.rows].filter((row) => row !== emptyRow);
    const next = context?.next_period || null;
    const hideFutureAcademicYear = !context?.academic_year && Boolean(next?.academic_year_name);

    rows.forEach((row) => {
      const year = String(row.cells?.[0]?.textContent || "").trim();
      const shouldHide = hideFutureAcademicYear && year === String(next.academic_year_name);
      if (row.hidden !== shouldHide) row.hidden = shouldHide;
      if (shouldHide) row.dataset.calendarFutureHidden = "1";
      else delete row.dataset.calendarFutureHidden;
    });

    const visibleRows = rows.filter((row) => !row.hidden).length;
    if (visibleRows === 0 && !emptyRow) {
      const empty = tbody.insertRow();
      empty.className = "student-portal-attendance-history-empty";
      const cell = empty.insertCell();
      cell.colSpan = Math.max(1, table.tHead?.rows?.[0]?.cells?.length || 9);
      cell.className = "student-portal-attendance-history-empty-cell";
      cell.textContent = "No historical attendance records yet.";
    } else if (visibleRows > 0 && emptyRow) {
      emptyRow.remove();
    }
    return { panel: attendancePanel, visibleRows };
  }

  function applyCalendarContext(root = document, context = null) {
    if (!context) return;
    const activeYear = context.academic_year || null;
    const activeTerm = context.term || null;
    const next = context.next_period || null;
    const period = root.querySelector?.(".student-portal-period");
    const periodTitle = period?.querySelector("strong");
    const periodCopy = period?.querySelector("span");

    if (context.active && activeYear) {
      setText(periodTitle, activeYear.name || "Current academic year");
      setText(periodCopy, activeTerm?.name || "No active term");
      profileValue(root, "Academic year", activeYear.name || "Current academic year");
      profileValue(root, "Current term", activeTerm?.name || "No active term");
    } else {
      setText(periodTitle, "No active academic period");
      setText(periodCopy, next ? `Next: ${next.academic_year_name} • ${next.term_name} • ${prettyDate(next.term_start_date)}` : "No upcoming period scheduled");
      profileValue(root, "Academic year", "No active academic year");
      profileValue(root, "Current term", "No active term");
    }

    const classMetric = [...(root.querySelectorAll?.(".student-portal-metric") || [])].find((metric) => String(metric.querySelector("span")?.textContent || "").trim() === "Current class" || String(metric.querySelector("span")?.textContent || "").trim() === "Class");
    if (classMetric) {
      const label = classMetric.querySelector("span");
      const small = classMetric.querySelector("small");
      if (context.active) {
        setText(label, "Current class");
        setText(small, "Current active enrollment");
      } else {
        setText(label, "Class");
        setText(small, next ? `Next academic period begins ${prettyDate(next.term_start_date)}` : "Latest school enrollment");
      }
    }

    refineInactiveAttendanceMetric(root, context);
    const attendanceState = refineAttendanceHistory(root, context);
    const attendancePanel = attendanceState.panel;
    if (!activeTerm) {
      root.querySelector?.(".student-portal-attendance-cards")?.remove();
      if (attendancePanel) {
        const trailing = attendanceState.visibleRows > 0 ? "Historical attendance remains available below." : "There are no historical attendance records yet.";
        const copy = next ? `There is no active term today. ${next.academic_year_name} ${next.term_name} begins ${prettyDate(next.term_start_date)}. ${trailing}` : `There is no active term today. ${trailing}`;
        upsertCalendarNote(attendancePanel, "studentPortalAttendanceCalendarNote", "No active term", copy);
      }
    } else {
      clearCalendarNote("studentPortalAttendanceCalendarNote");
    }

    const timetableHeading = byText(root, ".student-portal-panel-head h4", "Class Timetable");
    const timetablePanel = timetableHeading?.closest(".student-portal-panel");
    if (!context.active && timetablePanel) {
      const copy = next ? `No academic period is active today. The timetable area may show the student's next enrolled academic year. The next scheduled period is ${next.academic_year_name} ${next.term_name}, beginning ${prettyDate(next.term_start_date)}.` : "No academic period is active today.";
      upsertCalendarNote(timetablePanel, "studentPortalTimetableCalendarNote", "Between academic periods", copy);
    } else {
      clearCalendarNote("studentPortalTimetableCalendarNote");
    }
  }

  function applyParentCalendarContext(root = document, context = null) {
    if (!context || runtimeRole() !== "parent_guardian") return;
    const heading = [...(root.querySelectorAll?.(".panel-header h3") || [])].find((node) => String(node.textContent || "").trim() === "Current Academic Period");
    const copy = heading?.closest(".panel-header")?.querySelector("p");
    if (!copy) return;

    const year = context.academic_year || null;
    const term = context.term || null;
    const next = context.next_period || null;
    const desired = context.active && year
      ? `${year.name || "Current academic year"} • ${term?.name || "No active term"}`
      : next
        ? `No active academic period • Next: ${next.academic_year_name} • ${next.term_name} • ${prettyDate(next.term_start_date)}`
        : "No active academic period • No upcoming period scheduled";
    setText(copy, desired);
  }

  function installStyle() {
    if (document.getElementById("edsStudentPortalV2RefinementStyle")) return;
    const style = document.createElement("style");
    style.id = "edsStudentPortalV2RefinementStyle";
    style.textContent = ".student-portal-missing-note,.student-portal-calendar-note{margin:8px 0 12px;padding:12px 13px;border:1px solid var(--line,#d8e1ef);border-radius:12px;background:#f8fbff}.student-portal-missing-note strong,.student-portal-calendar-note strong{display:block;font-size:11px;color:#32455d;margin-bottom:4px}.student-portal-missing-note span,.student-portal-calendar-note span{display:block;font-size:10px;line-height:1.45;color:var(--muted,#64748b)}.student-portal-calendar-note{background:#fffaf0;border-color:#ead8ad}.student-portal-calendar-note strong{color:#6f571f}.student-portal-attendance-history-empty-cell{text-align:center!important;padding:24px 16px!important;color:var(--muted,#64748b);font-size:11px!important}";
    document.head.appendChild(style);
  }

  let timer = 0;
  function refine() {
    clearTimeout(timer);
    timer = setTimeout(async () => {
      installStyle();
      const role = runtimeRole();
      if (role === "parent_guardian") {
        const context = parentCalendarContext || await loadParentCalendarContext();
        applyParentCalendarContext(document, context);
        return;
      }
      if (role !== "student") return;
      refineOverview(document);
      refineProfile(document);
      const context = calendarContext || await loadCalendarContext();
      applyCalendarContext(document, context);
    }, 20);
  }

  const observer = new MutationObserver(refine);
  observer.observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener("pageshow", refine, { passive: true });
  document.addEventListener("click", (event) => {
    if (event.target.closest("#refreshButton")) {
      calendarContext = null;
      calendarPromise = null;
      parentCalendarContext = null;
      parentCalendarPromise = null;
      parentCalendarLoadedAt = 0;
    }
    if (event.target.closest(".student-portal-nav-item,.student-portal-action,.nav-item,#refreshButton")) refine();
  }, true);
  refine();
})();
