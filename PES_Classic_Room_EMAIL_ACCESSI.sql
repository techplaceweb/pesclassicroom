-- PES Classic Room: permessi automatici, storico accessi e modifiche admin.
-- Eseguire una volta in Supabase > SQL Editor, come proprietario del progetto.
BEGIN;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS all_rooms boolean NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS updated_at timestamptz;
UPDATE public.profiles SET updated_at=coalesce(updated_at,created_at,now()) WHERE updated_at IS NULL;

-- Gli utenti già autorizzati a tutte le stanze attuali mantengono il permesso anche per le future.
UPDATE public.profiles p SET all_rooms=true WHERE p.role='user' AND EXISTS(SELECT 1 FROM public.rooms)
AND NOT EXISTS(SELECT 1 FROM public.rooms r WHERE NOT EXISTS(SELECT 1 FROM public.room_access a WHERE a.user_id=p.id AND a.room_id=r.id));

CREATE OR REPLACE FUNCTION public.pcr_touch_profile() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF NEW.username IS DISTINCT FROM OLD.username OR NEW.archived IS DISTINCT FROM OLD.archived OR NEW.all_rooms IS DISTINCT FROM OLD.all_rooms THEN
    NEW.updated_at=now();
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS pcr_profile_touch ON public.profiles;
CREATE TRIGGER pcr_profile_touch BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.pcr_touch_profile();

CREATE OR REPLACE FUNCTION public.pcr_is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role='admin' AND archived IS NOT TRUE)
$$;
REVOKE ALL ON FUNCTION public.pcr_is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pcr_is_admin() TO authenticated;

CREATE OR REPLACE FUNCTION public.pcr_set_room_preferences(p_user_id uuid,p_all_rooms boolean,p_room_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT public.pcr_is_admin() THEN RAISE EXCEPTION 'Solo ADMIN'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user_id AND role='user') THEN RAISE EXCEPTION 'Utente non trovato'; END IF;
 UPDATE public.profiles SET all_rooms=coalesce(p_all_rooms,false) WHERE id=p_user_id;
 DELETE FROM public.room_access WHERE user_id=p_user_id;
 INSERT INTO public.room_access(user_id,room_id)
 SELECT p_user_id,r.id FROM public.rooms r
 WHERE r.id=ANY(coalesce(p_room_ids,ARRAY[]::uuid[]))
    OR coalesce(p_all_rooms,false)
 ON CONFLICT DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION public.pcr_set_room_preferences(uuid,boolean,uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pcr_set_room_preferences(uuid,boolean,uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.pcr_new_room_grants() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 INSERT INTO public.room_access(user_id,room_id)
 SELECT p.id,NEW.id FROM public.profiles p
 WHERE p.role='user' AND p.all_rooms=true AND p.archived IS NOT TRUE
 ON CONFLICT DO NOTHING;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS pcr_room_auto_grants ON public.rooms;
CREATE TRIGGER pcr_room_auto_grants AFTER INSERT ON public.rooms FOR EACH ROW EXECUTE FUNCTION public.pcr_new_room_grants();

CREATE TABLE IF NOT EXISTS public.pcr_login_events(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pcr_login_events_user_time ON public.pcr_login_events(user_id,created_at DESC);
CREATE INDEX IF NOT EXISTS pcr_login_events_time ON public.pcr_login_events(created_at DESC);
ALTER TABLE public.pcr_login_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pcr_login_events_admin_read ON public.pcr_login_events;
CREATE POLICY pcr_login_events_admin_read ON public.pcr_login_events FOR SELECT TO authenticated USING(public.pcr_is_admin());
REVOKE ALL ON public.pcr_login_events FROM anon,authenticated;
GRANT SELECT ON public.pcr_login_events TO authenticated;

CREATE OR REPLACE FUNCTION public.pcr_record_login() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Non autenticato'; END IF;
 -- Un login viene registrato quando il browser conferma il login esplicito.
 INSERT INTO public.pcr_login_events(user_id) VALUES(auth.uid());
END $$;
REVOKE ALL ON FUNCTION public.pcr_record_login() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pcr_record_login() TO authenticated;

-- Il sito non prevede più limiti di capienza. Rimuove soltanto eventuali colonne di configurazione.
ALTER TABLE public.rooms DROP COLUMN IF EXISTS max_participants;
ALTER TABLE public.rooms DROP COLUMN IF EXISTS capacity;
COMMIT;

-- Email di contatto separata dall’alias tecnico di autenticazione.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS contact_email text;
