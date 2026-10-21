-- PES Classic Room: risposta a un messaggio specifico nella stessa room.
-- Non modifica messaggi esistenti o credenziali.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS reply_to_id uuid NULL;

-- Verifica che il messaggio originale esista; la cancellazione del messaggio
-- originale lascia visibile la risposta, ma senza il riferimento.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'pcr_messages_reply_to_fkey'
      AND conrelid = 'public.messages'::regclass
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT pcr_messages_reply_to_fkey
      FOREIGN KEY (reply_to_id) REFERENCES public.messages(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS pcr_messages_reply_to_idx
  ON public.messages(reply_to_id) WHERE reply_to_id IS NOT NULL;

-- Non consentire risposte a messaggi appartenenti ad altre room.
CREATE OR REPLACE FUNCTION public.pcr_validate_message_reply()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.reply_to_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.messages m
    WHERE m.id = NEW.reply_to_id AND m.room_id = NEW.room_id
  ) THEN
    RAISE EXCEPTION 'Il messaggio a cui rispondi non appartiene a questa room';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pcr_validate_message_reply_trigger ON public.messages;
CREATE TRIGGER pcr_validate_message_reply_trigger
  BEFORE INSERT OR UPDATE OF reply_to_id, room_id ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.pcr_validate_message_reply();
