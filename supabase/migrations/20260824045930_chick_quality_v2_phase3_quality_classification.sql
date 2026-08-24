-- Chick Quality V2 Phase 3: additive, registry-classified quality cache.
-- This migration is intentionally a repository file only; it is not applied
-- to a live project by the implementation workflow.

ALTER TABLE public.chick_quality
  ADD COLUMN IF NOT EXISTS quality_status text,
  ADD COLUMN IF NOT EXISTS quality_flags text;

ALTER TABLE public.chick_weights
  ADD COLUMN IF NOT EXISTS quality_status text,
  ADD COLUMN IF NOT EXISTS quality_flags text;

CREATE OR REPLACE FUNCTION public.chick_quality_legacy_flag(
  p_domain text
) RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $function$
  SELECT jsonb_build_array(
    jsonb_build_object(
      'tier', 'FLAG',
      'schemaKey', coalesce(nullif(btrim(p_domain), ''), 'chicks.unknown'),
      'fieldKey', '$sample',
      'code', 'legacy_quality_unclassified'
    )
  )::text
$function$;

UPDATE public.chick_quality
SET quality_status = 'FLAG',
    quality_flags = public.chick_quality_legacy_flag(domain)
WHERE quality_status IS NULL OR quality_flags IS NULL;

UPDATE public.chick_weights
SET quality_status = 'FLAG',
    quality_flags = public.chick_quality_legacy_flag(domain)
WHERE quality_status IS NULL OR quality_flags IS NULL;

CREATE OR REPLACE FUNCTION public.normalize_chick_quality_cache()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  -- The Data API caller is not a trusted classifier. Every cloud write gets
  -- a deterministic conservative cache; Flutter recomputes the exact
  -- registry classification in SQLite after pull.
  NEW.quality_status := 'FLAG';
  NEW.quality_flags := public.chick_quality_legacy_flag(NEW.domain);
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS normalize_chick_quality_cache
  ON public.chick_quality;
CREATE TRIGGER normalize_chick_quality_cache
BEFORE INSERT OR UPDATE
ON public.chick_quality
FOR EACH ROW EXECUTE FUNCTION public.normalize_chick_quality_cache();

DROP TRIGGER IF EXISTS normalize_chick_quality_cache
  ON public.chick_weights;
CREATE TRIGGER normalize_chick_quality_cache
BEFORE INSERT OR UPDATE
ON public.chick_weights
FOR EACH ROW EXECUTE FUNCTION public.normalize_chick_quality_cache();

ALTER TABLE public.chick_quality
  ALTER COLUMN quality_status SET NOT NULL,
  ALTER COLUMN quality_flags SET NOT NULL;

ALTER TABLE public.chick_weights
  ALTER COLUMN quality_status SET NOT NULL,
  ALTER COLUMN quality_flags SET NOT NULL;

DO $block$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conname = 'chick_quality_quality_status_check'
      AND conrelid = 'public.chick_quality'::regclass
  ) THEN
    ALTER TABLE public.chick_quality
      ADD CONSTRAINT chick_quality_quality_status_check
      CHECK (quality_status IN ('OK', 'FLAG', 'WARN', 'BLOCK'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conname = 'chick_weights_quality_status_check'
      AND conrelid = 'public.chick_weights'::regclass
  ) THEN
    ALTER TABLE public.chick_weights
      ADD CONSTRAINT chick_weights_quality_status_check
      CHECK (quality_status IN ('OK', 'FLAG', 'WARN', 'BLOCK'));
  END IF;
END
$block$;

REVOKE ALL ON FUNCTION public.chick_quality_legacy_flag(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.normalize_chick_quality_cache() FROM PUBLIC;
