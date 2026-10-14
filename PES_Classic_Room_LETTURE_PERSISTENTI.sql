-- Esegui una sola volta in Supabase SQL Editor.
-- Conserva l'ultima posizione di lettura di ogni utente per ogni room.
CREATE TABLE IF NOT EXISTS public.pcr_room_reads (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
 last_read_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,room_id)
);
CREATE INDEX IF NOT EXISTS pcr_room_reads_user_idx ON public.pcr_room_reads(user_id);
ALTER TABLE public.pcr_room_reads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pcr_reads_select ON public.pcr_room_reads;
CREATE POLICY pcr_reads_select ON public.pcr_room_reads FOR SELECT TO authenticated USING(user_id=auth.uid());
DROP POLICY IF EXISTS pcr_reads_insert ON public.pcr_room_reads;
CREATE POLICY pcr_reads_insert ON public.pcr_room_reads FOR INSERT TO authenticated WITH CHECK(user_id=auth.uid());
DROP POLICY IF EXISTS pcr_reads_update ON public.pcr_room_reads;
CREATE POLICY pcr_reads_update ON public.pcr_room_reads FOR UPDATE TO authenticated USING(user_id=auth.uid()) WITH CHECK(user_id=auth.uid());
GRANT SELECT,INSERT,UPDATE ON public.pcr_room_reads TO authenticated;
-- Non cambiare gli account Auth né le password.
-- Nota: la prima apertura della nuova versione inizializza la lettura alla
-- data dell'ultimo messaggio esistente per evitare di segnalare tutta la cronologia.
