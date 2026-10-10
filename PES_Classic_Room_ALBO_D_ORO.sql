-- PES Classic Room: Albo d'oro. Eseguire in Supabase SQL Editor.
-- Non elimina né modifica dati delle chat o dei tornei.
CREATE TABLE IF NOT EXISTS public.honor_entries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
 trophy_name text NOT NULL CHECK (length(btrim(trophy_name)) BETWEEN 1 AND 100),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS honor_entries_user_idx ON public.honor_entries(user_id);
CREATE TABLE IF NOT EXISTS public.honor_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS honor_events_latest_idx ON public.honor_events(id DESC);
ALTER TABLE public.honor_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.honor_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.honor_entries,public.honor_events FROM anon;
REVOKE INSERT,UPDATE,DELETE ON public.honor_entries,public.honor_events FROM authenticated;
GRANT SELECT ON public.honor_entries,public.honor_events TO authenticated;
DROP POLICY IF EXISTS honor_entries_read ON public.honor_entries;
CREATE POLICY honor_entries_read ON public.honor_entries FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS honor_events_read ON public.honor_events;
CREATE POLICY honor_events_read ON public.honor_events FOR SELECT TO authenticated USING (true);

CREATE OR REPLACE FUNCTION public.pcr_honor_is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role='admin' AND NOT archived);
$$;
REVOKE ALL ON FUNCTION public.pcr_honor_is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pcr_honor_is_admin() TO authenticated;

CREATE OR REPLACE FUNCTION public.pcr_add_honor(p_user_id uuid,p_trophy_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id uuid;
BEGIN
 IF NOT public.pcr_honor_is_admin() THEN RAISE EXCEPTION 'Solo ADMIN può aggiornare l’Albo d’oro'; END IF;
 IF length(btrim(coalesce(p_trophy_name,''))) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Nome trofeo non valido'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user_id AND role='user' AND NOT archived) THEN RAISE EXCEPTION 'Giocatore non valido'; END IF;
 INSERT INTO public.honor_entries(user_id,trophy_name) VALUES(p_user_id,btrim(p_trophy_name)) RETURNING id INTO v_id;
 INSERT INTO public.honor_events(user_id) VALUES(p_user_id);
 RETURN v_id;
END;$$;
CREATE OR REPLACE FUNCTION public.pcr_edit_honor(p_entry_id uuid,p_trophy_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_user uuid;
BEGIN
 IF NOT public.pcr_honor_is_admin() THEN RAISE EXCEPTION 'Solo ADMIN'; END IF;
 IF length(btrim(coalesce(p_trophy_name,''))) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Nome trofeo non valido'; END IF;
 UPDATE public.honor_entries SET trophy_name=btrim(p_trophy_name) WHERE id=p_entry_id RETURNING user_id INTO v_user;
 IF v_user IS NULL THEN RAISE EXCEPTION 'Vittoria non trovata'; END IF;
 INSERT INTO public.honor_events(user_id) VALUES(v_user);
END;$$;
CREATE OR REPLACE FUNCTION public.pcr_delete_honor(p_entry_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_user uuid;
BEGIN
 IF NOT public.pcr_honor_is_admin() THEN RAISE EXCEPTION 'Solo ADMIN'; END IF;
 DELETE FROM public.honor_entries WHERE id=p_entry_id RETURNING user_id INTO v_user;
 IF v_user IS NULL THEN RAISE EXCEPTION 'Vittoria non trovata'; END IF;
 INSERT INTO public.honor_events(user_id) VALUES(v_user);
END;$$;
REVOKE ALL ON FUNCTION public.pcr_add_honor(uuid,text),public.pcr_edit_honor(uuid,text),public.pcr_delete_honor(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pcr_add_honor(uuid,text),public.pcr_edit_honor(uuid,text),public.pcr_delete_honor(uuid) TO authenticated;

-- Abilita aggiornamenti immediati dove Realtime è configurato; è previsto anche un controllo periodico nel sito.
DO $$ BEGIN
 ALTER PUBLICATION supabase_realtime ADD TABLE public.honor_entries;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
 ALTER PUBLICATION supabase_realtime ADD TABLE public.honor_events;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
