alter policy "lecture média" on storage.objects to authenticated
  using (bucket_id = 'media' and private.can_read_media(name));
