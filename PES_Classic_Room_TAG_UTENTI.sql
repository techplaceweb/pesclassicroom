-- Eseguire nel SQL Editor di Supabase prima di pubblicare il nuovo HTML.
CREATE TABLE IF NOT EXISTS public.room_mentions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
 room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
 sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(),
 read_at timestamptz,
 UNIQUE(message_id,recipient_id)
);
CREATE INDEX IF NOT EXISTS room_mentions_recipient ON public.room_mentions(recipient_id,read_at,created_at DESC);
ALTER TABLE public.room_mentions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pcr_mentions_read ON public.room_mentions;
CREATE POLICY pcr_mentions_read ON public.room_mentions FOR SELECT TO authenticated USING(recipient_id=auth.uid());
DROP POLICY IF EXISTS pcr_mentions_insert ON public.room_mentions;
CREATE POLICY pcr_mentions_insert ON public.room_mentions FOR INSERT TO authenticated WITH CHECK (
 sender_id=auth.uid() AND recipient_id<>auth.uid()
 AND EXISTS (SELECT 1 FROM public.messages m WHERE m.id=message_id AND m.room_id=room_mentions.room_id AND m.author_id=auth.uid()
 AND m.body ~* ('(^|[^[:alnum:]_.-])@' || (SELECT p.username FROM public.profiles p WHERE p.id=room_mentions.recipient_id) || '([^[:alnum:]_.-]|$)'))
 AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=recipient_id AND p.archived IS NOT TRUE)
 AND (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=recipient_id AND p.role='admin') OR EXISTS (SELECT 1 FROM public.room_access a WHERE a.user_id=recipient_id AND a.room_id=room_mentions.room_id))
);
DROP POLICY IF EXISTS pcr_mentions_update ON public.room_mentions;
CREATE POLICY pcr_mentions_update ON public.room_mentions FOR UPDATE TO authenticated USING(recipient_id=auth.uid()) WITH CHECK(recipient_id=auth.uid());
-- Il destinatario può modificare soltanto read_at; non può alterare l'identità del tag.
CREATE OR REPLACE FUNCTION public.pcr_guard_mention_update() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.message_id IS DISTINCT FROM OLD.message_id OR NEW.room_id IS DISTINCT FROM OLD.room_id OR NEW.sender_id IS DISTINCT FROM OLD.sender_id OR NEW.recipient_id IS DISTINCT FROM OLD.recipient_id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
 RAISE EXCEPTION 'Solo lo stato di lettura è modificabile'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS pcr_guard_mention_update_trigger ON public.room_mentions;
CREATE TRIGGER pcr_guard_mention_update_trigger BEFORE UPDATE ON public.room_mentions FOR EACH ROW EXECUTE FUNCTION public.pcr_guard_mention_update();
GRANT SELECT,INSERT,UPDATE ON public.room_mentions TO authenticated;
-- Per notifiche immediate: abilita la tabella nella pubblicazione Realtime.
DO $$ BEGIN
 ALTER PUBLICATION supabase_realtime ADD TABLE public.room_mentions;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
