-- Certified, read-only attendance register export for Principal and assigned main Class Teachers.
-- Attendance source of truth remains the original daily registers and closure calendar.
-- Supabase reference implementation is not modified.
BEGIN;

CREATE TABLE IF NOT EXISTS public.attendance_export_events(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid NOT NULL,
  actor_role text NOT NULL,
  term_id uuid NOT NULL REFERENCES public.terms(id),
  class_id uuid NOT NULL REFERENCES public.classes(id),
  through_week_start date NOT NULL,
  generated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS attendance_export_events_class_time_idx
  ON public.attendance_export_events(class_id,generated_at DESC);
ALTER TABLE public.attendance_export_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.attendance_export_events FROM PUBLIC;
REVOKE ALL ON public.attendance_export_events FROM edusentia_worker_runtime;

CREATE OR REPLACE FUNCTION public.list_attendance_export_classes(target_term_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public','extensions' AS $body$
DECLARE role_name text;
BEGIN
  role_name:=public.current_app_role()::text;
  IF auth.uid() IS NULL OR role_name NOT IN ('principal','class_teacher') THEN
    RAISE EXCEPTION 'Attendance exports are available only to the Principal and assigned main Class Teachers' USING errcode='42501';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.terms t WHERE t.id=target_term_id AND t.deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Select a valid academic term' USING errcode='22023';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id',c.id,
      'name',c.name,
      'main_teacher',coalesce(nullif(btrim(concat_ws(' ',tr.first_name,nullif(tr.middle_name,''),tr.last_name)),''),'Not assigned')
    ) ORDER BY c.level_order,c.name::text)
    FROM public.classes c
    LEFT JOIN public.teachers tr ON tr.id=c.class_teacher_record_id AND tr.deleted_at IS NULL
    WHERE c.active AND c.deleted_at IS NULL
      AND (role_name='principal' OR public.is_assigned_class_teacher(c.id))
  ),'[]'::jsonb);
END
$body$;

CREATE OR REPLACE FUNCTION public.get_attendance_register_export(
  target_term_id uuid,
  target_class_id uuid,
  target_through_week_start date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'public','extensions' AS $body$
DECLARE
  role_name text;
  first_day date;
  last_day date;
  year_id uuid;
  term_label text;
  year_label text;
  class_label text;
  teacher_label text;
  first_week date;
  last_week date;
  selected_week date;
  through_day date;
  response jsonb;
BEGIN
  role_name:=public.current_app_role()::text;
  IF auth.uid() IS NULL OR role_name NOT IN ('principal','class_teacher') THEN
    RAISE EXCEPTION 'Attendance register export requires a Principal or main Class Teacher sign-in' USING errcode='42501';
  END IF;
  SELECT t.start_date,t.end_date,t.academic_year_id,t.name::text,y.name::text
    INTO first_day,last_day,year_id,term_label,year_label
    FROM public.terms t
    JOIN public.academic_years y ON y.id=t.academic_year_id AND y.deleted_at IS NULL
    WHERE t.id=target_term_id AND t.deleted_at IS NULL;
  IF first_day IS NULL OR last_day IS NULL OR last_day<first_day OR last_day-first_day>366 THEN
    RAISE EXCEPTION 'Select an academic term with valid dates within one school year' USING errcode='22023';
  END IF;
  SELECT c.name::text,
         coalesce(nullif(btrim(concat_ws(' ',tr.first_name,nullif(tr.middle_name,''),tr.last_name)),''),'Not assigned')
    INTO class_label,teacher_label
    FROM public.classes c
    LEFT JOIN public.teachers tr ON tr.id=c.class_teacher_record_id AND tr.deleted_at IS NULL
    WHERE c.id=target_class_id AND c.active AND c.deleted_at IS NULL;
  IF class_label IS NULL THEN
    RAISE EXCEPTION 'Select an active school class' USING errcode='22023';
  END IF;
  IF role_name='class_teacher' AND NOT public.is_assigned_class_teacher(target_class_id) THEN
    RAISE EXCEPTION 'Only the assigned main Class Teacher can export this class attendance' USING errcode='42501';
  END IF;

  first_week:=first_day-(extract(isodow from first_day)::integer-1);
  last_week:=last_day-(extract(isodow from last_day)::integer-1);
  IF target_through_week_start IS NOT NULL AND extract(isodow from target_through_week_start)::integer<>1 THEN
    RAISE EXCEPTION 'Selected week must begin on Monday' USING errcode='22023';
  END IF;
  selected_week:=coalesce(target_through_week_start,least(last_week,current_date-(extract(isodow from current_date)::integer-1)));
  IF selected_week<first_week OR selected_week>last_week THEN
    RAISE EXCEPTION 'Selected week is outside this academic term' USING errcode='22023';
  END IF;
  through_day:=least(last_day,selected_week+6);

  -- A successful export request is audited as "generated", not as proof that the browser saved it.
  INSERT INTO public.attendance_export_events(actor_id,actor_role,term_id,class_id,through_week_start)
    VALUES(auth.uid(),role_name,target_term_id,target_class_id,selected_week);

  SELECT jsonb_build_object(
    'generated_at',now(),
    'academic_year',year_label,
    'term',term_label,
    'term_start',first_day,
    'term_end',last_day,
    'class_id',target_class_id,
    'class_name',class_label,
    'main_teacher',teacher_label,
    'through_week_start',selected_week,
    'school',coalesce((SELECT jsonb_build_object(
      'name',ss.school_name,'motto',ss.motto,'address',ss.address,
      'phone',ss.phone,'email',ss.email,'website',ss.website,
      'logo_url',ss.logo_url,'primary_colour',ss.primary_colour,'accent_colour',ss.accent_colour
    ) FROM public.school_settings ss ORDER BY ss.created_at LIMIT 1),'{}'::jsonb),
    'weeks',coalesce((SELECT jsonb_agg(jsonb_build_object(
       'week_number',((g.d::date-first_week)/7)+1,
       'week_start',g.d::date,
       'start_date',greatest(g.d::date,first_day),
       'end_date',least(g.d::date+6,through_day)
    ) ORDER BY g.d)
    FROM generate_series(first_week::timestamp,selected_week::timestamp,'7 days') g(d)),'[]'::jsonb),
    'calendar',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'date',g.d::date,
      'day_status',CASE
        WHEN EXISTS(SELECT 1 FROM public.school_closures sc WHERE sc.term_id=target_term_id AND sc.deleted_at IS NULL
          AND g.d::date BETWEEN sc.start_date AND sc.end_date) THEN 'closed'
        WHEN g.d::date>current_date THEN 'upcoming'
        WHEN EXISTS(SELECT 1 FROM public.class_attendance_registers r
          WHERE r.term_id=target_term_id AND r.class_id=target_class_id AND r.attendance_date=g.d::date
          AND EXISTS(SELECT 1 FROM public.student_attendance_entries se WHERE se.register_id=r.id)) THEN 'recorded'
        ELSE 'unrecorded'
      END
    ) ORDER BY g.d)
    FROM generate_series(first_day::timestamp,through_day::timestamp,'1 day') g(d)
    WHERE extract(isodow from g.d)::integer<=5),'[]'::jsonb),
    'students',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'enrollment_id',e.id,
      'name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
      'admission_no',s.admission_no,
      'gender',CASE WHEN lower(btrim(coalesce(s.gender,'')))='male' THEN 'boys'
        WHEN lower(btrim(coalesce(s.gender,'')))='female' THEN 'girls'
        ELSE 'review' END
    ) ORDER BY CASE WHEN lower(btrim(coalesce(s.gender,'')))='male' THEN 1
      WHEN lower(btrim(coalesce(s.gender,'')))='female' THEN 2 ELSE 3 END,
      lower(concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)),s.admission_no::text)
    FROM public.enrollments e
    JOIN public.students s ON s.id=e.student_id AND s.deleted_at IS NULL AND s.status='active'
    WHERE e.academic_year_id=year_id AND e.class_id=target_class_id
      AND e.active AND e.deleted_at IS NULL),'[]'::jsonb),
    'marks',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'enrollment_id',a.enrollment_id,
      'date',r.attendance_date,
      'status',a.attendance_status
    ) ORDER BY r.attendance_date,a.enrollment_id)
    FROM public.class_attendance_registers r
    JOIN public.student_attendance_entries a ON a.register_id=r.id
    JOIN public.enrollments e ON e.id=a.enrollment_id AND e.active AND e.deleted_at IS NULL
      AND e.academic_year_id=year_id AND e.class_id=target_class_id
    JOIN public.students s ON s.id=e.student_id AND s.deleted_at IS NULL AND s.status='active'
    WHERE r.term_id=target_term_id AND r.class_id=target_class_id
      AND r.attendance_date BETWEEN first_day AND through_day
      AND extract(isodow from r.attendance_date)::integer<=5
      AND NOT EXISTS(SELECT 1 FROM public.school_closures sc
        WHERE sc.term_id=target_term_id AND sc.deleted_at IS NULL
          AND r.attendance_date BETWEEN sc.start_date AND sc.end_date)
    ),'[]'::jsonb)
  ) INTO response;

  RETURN response;
END
$body$;

REVOKE ALL ON FUNCTION public.list_attendance_export_classes(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_attendance_register_export(uuid,uuid,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_attendance_export_classes(uuid) TO edusentia_worker_runtime;
GRANT EXECUTE ON FUNCTION public.get_attendance_register_export(uuid,uuid,date) TO edusentia_worker_runtime;
INSERT INTO app.schema_migrations(version) VALUES('0087_attendance_register_pdf_export') ON CONFLICT DO NOTHING;
COMMIT;
