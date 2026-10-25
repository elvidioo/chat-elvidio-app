-- Les anciens liens publics cessent de fonctionner ; l'app utilise des liens signés (build 43+).
update storage.buckets set public = false where id = 'media';
