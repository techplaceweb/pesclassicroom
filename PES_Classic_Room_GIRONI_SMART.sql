-- Eseguire una sola volta in Supabase SQL Editor prima di caricare il nuovo HTML.
-- Aggiornamento non distruttivo: conserva competizioni, utenti, risultati e notifiche.
ALTER TABLE public.pcr_competitions
  ADD COLUMN IF NOT EXISTS group_size integer;
ALTER TABLE public.pcr_competition_members
  ADD COLUMN IF NOT EXISTS group_no integer NOT NULL DEFAULT 1;
ALTER TABLE public.pcr_competition_matches
  ADD COLUMN IF NOT EXISTS group_no integer NOT NULL DEFAULT 1;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pcr_comp_group_size_check') THEN
  ALTER TABLE public.pcr_competitions ADD CONSTRAINT pcr_comp_group_size_check CHECK (group_size IS NULL OR group_size IN (2,4,8,10));
 END IF;
END $$;
UPDATE public.pcr_competitions SET group_size=4 WHERE format='groups' AND group_size IS NULL;
CREATE INDEX IF NOT EXISTS pcr_comp_members_group_idx ON public.pcr_competition_members(competition_id,group_no);
CREATE INDEX IF NOT EXISTS pcr_comp_matches_group_idx ON public.pcr_competition_matches(competition_id,group_no,round_no);
