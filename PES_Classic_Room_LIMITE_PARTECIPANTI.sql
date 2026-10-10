-- PES Classic Room - limiti di partecipanti alle room
-- Eseguire una sola volta in Supabase SQL Editor. Non cancella messaggi o utenti.
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS max_participants integer;
ALTER TABLE public.rooms DROP CONSTRAINT IF EXISTS rooms_max_participants_check;
ALTER TABLE public.rooms ADD CONSTRAINT rooms_max_participants_check
  CHECK (max_participants IS NULL OR max_participants BETWEEN 1 AND 1000);

CREATE TABLE IF NOT EXISTS public.room_live_seats (
 room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 last_seen timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(room_id,user_id)
);
CREATE INDEX IF NOT EXISTS room_live_seats_expiry_idx ON public.room_live_seats(room_id,last_seen);
ALTER TABLE public.room_live_seats ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.room_live_seats FROM anon, authenticated;

-- Lock per room: anche due ingressi contemporanei non possono superare il limite.
CREATE OR REPLACE FUNCTION public.pcr_enter_room(p_room_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_user uuid := auth.uid(); v_limit integer; v_closed boolean; v_role text; v_archived boolean; v_count integer;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Autenticazione richiesta'; END IF;
 SELECT role,archived INTO v_role,v_archived FROM public.profiles WHERE id=v_user;
 IF v_role IS NULL OR v_archived THEN RAISE EXCEPTION 'Utente non autorizzato'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_room_id::text,0));
 SELECT max_participants,closed INTO v_limit,v_closed FROM public.rooms WHERE id=p_room_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Room inesistente'; END IF;
 IF v_role='admin' THEN RETURN true; END IF;
 IF v_closed THEN RETURN false; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_access WHERE room_id=p_room_id AND user_id=v_user) THEN
  RAISE EXCEPTION 'Accesso alla room non autorizzato';
 END IF;
 DELETE FROM public.room_live_seats WHERE room_id=p_room_id AND last_seen < now()-interval '65 seconds';
 IF EXISTS(SELECT 1 FROM public.room_live_seats WHERE room_id=p_room_id AND user_id=v_user) THEN
  UPDATE public.room_live_seats SET last_seen=now() WHERE room_id=p_room_id AND user_id=v_user;
  RETURN true;
 END IF;
 SELECT count(*) INTO v_count FROM public.room_live_seats WHERE room_id=p_room_id;
 IF v_limit IS NOT NULL AND v_count >= v_limit THEN RETURN false; END IF;
 INSERT INTO public.room_live_seats(room_id,user_id,last_seen) VALUES(p_room_id,v_user,now());
 RETURN true;
END; $$;

CREATE OR REPLACE FUNCTION public.pcr_heartbeat_room(p_room_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_user uuid := auth.uid(); v_updated integer;
BEGIN
 IF v_user IS NULL THEN RETURN false; END IF;
 IF EXISTS(SELECT 1 FROM public.profiles WHERE id=v_user AND role='admin' AND NOT archived) THEN RETURN true; END IF;
 UPDATE public.room_live_seats SET last_seen=now()
 WHERE room_id=p_room_id AND user_id=v_user AND last_seen>=now()-interval '65 seconds';
 GET DIAGNOSTICS v_updated = ROW_COUNT;
 RETURN v_updated>0;
END; $$;

CREATE OR REPLACE FUNCTION public.pcr_leave_room(p_room_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF auth.uid() IS NULL THEN RETURN; END IF;
 DELETE FROM public.room_live_seats WHERE room_id=p_room_id AND user_id=auth.uid();
END; $$;

REVOKE ALL ON FUNCTION public.pcr_enter_room(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pcr_heartbeat_room(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pcr_leave_room(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pcr_enter_room(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pcr_heartbeat_room(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pcr_leave_room(uuid) TO authenticated;
