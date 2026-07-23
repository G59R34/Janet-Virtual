-- Private distribution bucket for approved crew software. Signed URLs are issued server-side.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('crew-downloads', 'crew-downloads', false, 15728640, array['application/octet-stream', 'application/x-msi', 'application/x-msdownload'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
