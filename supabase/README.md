# Migrations Supabase

Fichiers numérotés par date, à appliquer dans l'ordre (SQL Editor ou `supabase db push`).
Elles reflètent ce qui est appliqué sur le projet `chat-elvidio`.
Les secrets ne sont jamais dans le dépôt : remplacer `__PUSH_SECRET__` (migrations push) par la valeur privée
(la même que dans la fonction Edge `push`).
Aucune migration ne supprime de données de production.
