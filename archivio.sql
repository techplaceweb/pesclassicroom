-- Eseguire una sola volta nel SQL Editor di Supabase. Non elimina messaggi.
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS archived_at timestamptz;
-- Le chat archiviate nascondono ai normali utenti soltanto i messaggi precedenti
-- all'archiviazione. I nuovi messaggi restano leggibili e inviabili.
DROP POLICY IF EXISTS messages_read ON public.messages;
CREATE POLICY messages_read ON public.messages FOR SELECT TO authenticated
USING (public.can_room(room_id) AND (
  public.is_admin() OR (
    NOT hidden AND EXISTS (
      SELECT 1 FROM public.rooms r WHERE r.id = room_id
      AND (NOT r.archived OR (r.archived_at IS NOT NULL AND public.messages.created_at > r.archived_at))
    )
  )
));
