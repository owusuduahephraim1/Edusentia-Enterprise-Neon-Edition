-- Tenant-scoped school closures and weekly attendance. Supabase reference remains unchanged.
-- Installed through the existing operational tenant reconciler.
BEGIN;

CREATE TABLE IF NOT EXISTS public.school_closures(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  term_id uuid NOT NULL REFERENCES public.terms(id),
  start_date date NOT NULL,
  end_date date NOT NULL,
  closure_type text NOT NULL CHECK(closure_type IN ('public_holiday','midterm_break','school_break','emergency_closure','other')),
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 240),
  created_by uuid,
  updated_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  deleted_reason text,
  CONSTRAINT school_closure_date_range CHECK(end_date>=start_date)
);
CREATE INDEX IF NOT EXISTS school_closures_term_dates_idx
  ON public.school_closures(term_id,start_date,end_date) WHERE deleted_at IS NULL;
ALTER TABLE public.school_closures ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.school_closures FROM PUBLIC;
REVOKE ALL ON TABLE public.school_closures FROM edusentia_worker_runtime;

CREATE OR REPLACE FUNCTION public.list_school_closures(target_term_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','extensions' AS $body$
BEGIN
  IF auth.uid() IS NULL OR public.current_app_role() NOT IN ('system_admin','class_teacher','subject_teacher','principal','academic_admin') THEN
    RAISE EXCEPTION 'Staff authentication required' USING errcode='42501';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.terms t WHERE t.id=target_term_id AND t.deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Invalid academic term' USING errcode='22023';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id',c.id,'term_id',c.term_id,'start_date',c.start_date,'end_date',c.end_date,
      'closure_type',c.closure_type,'reason',c.reason,'updated_at',c.updated_at
    ) ORDER BY c.start_date,c.end_date,c.id)
    FROM public.school_closures c WHERE c.term_id=target_term_id AND c.deleted_at IS NULL
  ),'[]'::jsonb);
END
$body$;

CREATE OR REPLACE FUNCTION public.save_school_closure(
  target_term_id uuid,target_start_date date,target_end_date date,
  target_type text,reason_text text,target_closure_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $body$
DECLARE first_day date;last_day date;result_id uuid;
BEGIN
  IF NOT public.is_system_admin() THEN
    RAISE EXCEPTION 'Only the School System Administrator can manage school closures' USING errcode='42501';
  END IF;
  PERFORM public.require_sensitive_access();
  SELECT t.start_date,t.end_date INTO first_day,last_day FROM public.terms t
    WHERE t.id=target_term_id AND t.deleted_at IS NULL;
  IF first_day IS NULL OR last_day IS NULL THEN
    RAISE EXCEPTION 'Select a term with configured opening and closing dates' USING errcode='22023';
  END IF;
  IF target_start_date IS NULL OR target_end_date IS NULL OR target_start_date>target_end_date
    OR target_start_date<first_day OR target_end_date>last_day THEN
    RAISE EXCEPTION 'Closure dates must fall within the selected academic term' USING errcode='22023';
  END IF;
  IF target_type NOT IN ('public_holiday','midterm_break','school_break','emergency_closure','other')
    OR length(btrim(coalesce(reason_text,''))) NOT BETWEEN 3 AND 240 THEN
    RAISE EXCEPTION 'Choose a valid closure type and a reason of 3 to 240 characters' USING errcode='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('school_calendar:'||target_term_id::text));
  IF target_closure_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.school_closures c WHERE c.id=target_closure_id
      AND c.term_id=target_term_id AND c.deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Closure not found in this term' USING errcode='P0002'; END IF;
  IF EXISTS(SELECT 1 FROM public.class_attendance_registers r WHERE r.term_id=target_term_id
    AND r.attendance_date BETWEEN target_start_date AND target_end_date) THEN
    RAISE EXCEPTION 'Attendance already exists in this closure period. Reconcile recorded school days before closing them.' USING errcode='23514';
  END IF;
  IF EXISTS(SELECT 1 FROM public.school_closures c WHERE c.term_id=target_term_id
    AND c.deleted_at IS NULL AND (target_closure_id IS NULL OR c.id<>target_closure_id)
    AND c.start_date<=target_end_date AND c.end_date>=target_start_date) THEN
    RAISE EXCEPTION 'Closure dates overlap an existing school closure' USING errcode='23514';
  END IF;
  PERFORM set_config('app.change_reason','School closure: '||btrim(reason_text),true);
  IF target_closure_id IS NULL THEN
    INSERT INTO public.school_closures(term_id,start_date,end_date,closure_type,reason,created_by,updated_by)
    VALUES(target_term_id,target_start_date,target_end_date,target_type,btrim(reason_text),auth.uid(),auth.uid())
    RETURNING id INTO result_id;
  ELSE
    UPDATE public.school_closures c SET start_date=target_start_date,end_date=target_end_date,
      closure_type=target_type,reason=btrim(reason_text),updated_by=auth.uid(),updated_at=now()
    WHERE c.id=target_closure_id AND c.term_id=target_term_id AND c.deleted_at IS NULL RETURNING id INTO result_id;
  END IF;
  RETURN (SELECT jsonb_build_object('id',c.id,'start_date',c.start_date,'end_date',c.end_date,
    'closure_type',c.closure_type,'reason',c.reason) FROM public.school_closures c WHERE c.id=result_id);
END
$body$;

CREATE OR REPLACE FUNCTION public.archive_school_closure(target_closure_id uuid,reason_text text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $body$
DECLARE changed_id uuid;
BEGIN
  IF NOT public.is_system_admin() THEN
    RAISE EXCEPTION 'Only the School System Administrator can remove school closures' USING errcode='42501';
  END IF;
  PERFORM public.require_sensitive_access();
  IF length(btrim(coalesce(reason_text,'')))<3 THEN
    RAISE EXCEPTION 'Give a reason for removing this school closure' USING errcode='22023';
  END IF;
  UPDATE public.school_closures c SET deleted_at=now(),deleted_reason=btrim(reason_text),
    updated_by=auth.uid(),updated_at=now()
    WHERE c.id=target_closure_id AND c.deleted_at IS NULL RETURNING id INTO changed_id;
  IF changed_id IS NULL THEN RAISE EXCEPTION 'School closure not found' USING errcode='P0002'; END IF;
  RETURN jsonb_build_object('id',changed_id,'archived',true);
END
$body$;

-- Weekly read model and attendance reconciliation functions follow.

COMMIT;
