# Sécurité — état honnête

- **Chiffrement de bout en bout : NON implémenté.** Les messages sont protégés en transit (HTTPS) et par RLS côté serveur, mais lisibles par le serveur. Ne pas présenter l'app comme « E2EE ». Une vraie implémentation demande un protocole éprouvé (Signal/MLS), pas du chiffrement maison.
- Mode proche (Elvidio Relay) : paquets non chiffrés, expéditeur non authentifié, livraison au mieux, sans garantie hors de portée.
- RLS activée sur toutes les tables ; fonctions d'aide dans le schéma `private` ; aucune clé `service_role` dans l'app.
- Secrets : jamais dans le dépôt (secret push à remplacer dans les migrations ; compte de service Firebase uniquement dans Supabase).
- Le bucket `media` reste public côté serveur (les liens ne sont pas devinables mais pas secrets) ; l'app utilise déjà des liens signés. Passage en privé = migration à appliquer après mise à jour de tous les téléphones.
- Clé de signature APK : clé fixe publique dans `ci/` (permet les mises à jour, mais n'importe qui peut signer une fausse version). À remplacer par une clé privée (secret GitHub).
- Signalements enregistrés dans `reports` (aucune modération automatique).
