-- P0-10 CG-02 through CG-12, DEL-15, DEL-17.
-- The study bucket stays absent until DEL-15 is signed off.
-- Authenticated parents cannot upload into it. A later service-role pipeline
-- may write only after study_audio scope and a written consent id.

drop policy if exists study_audio_owner_select on storage.objects;
drop policy if exists study_audio_owner_insert on storage.objects;
drop policy if exists study_audio_owner_update on storage.objects;
drop policy if exists study_audio_owner_delete on storage.objects;
drop policy if exists study_audio_service_delete on storage.objects;

delete from storage.buckets where id = 'study-audio';
