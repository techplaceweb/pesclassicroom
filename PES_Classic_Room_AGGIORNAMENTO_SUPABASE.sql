-- Esegui una sola volta in Supabase > SQL Editor.
-- Conserva il pin per ogni room, visibile a tutti i partecipanti.
-- La policy RLS già esistente consente SOLO ad ADMIN di aggiornare rooms.
ALTER TABLE public.rooms
ADD COLUMN IF NOT EXISTS pinned_message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL;

-- Consenti anche allegati comuni, massimo 5 MB; il bucket rimane PRIVATO.
UPDATE storage.buckets
SET file_size_limit=5242880,
    allowed_mime_types=ARRAY[
      'image/jpeg','image/png','image/webp','image/gif',
      'application/pdf','text/plain','application/zip','application/x-zip-compressed',
      'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation'
    ]
WHERE id='room-images';
