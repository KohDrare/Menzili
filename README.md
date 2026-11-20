# Menzïli — Commande en ligne

Site de commande du snack **Menzïli**, Rue Haute 326, 1000 Bruxelles (Marolles), à deux pas de l'hôpital Saint-Pierre.

- À emporter : retrait au comptoir à l'heure choisie
- Livraison Saint-Pierre : livré au service, commande avant 10:30, réduction personnel −10 %
- Les commandes sont envoyées au snack via WhatsApp (aucun serveur nécessaire)

## Modifier le site

Tout se trouve dans `index.html` (page unique, sans dépendances) :

- `CONFIG` : numéro WhatsApp qui reçoit les commandes, horaires, réduction, créneaux de livraison, minimum de commande
- `MENU` : catégories, produits, prix, options (sauces, crudités, suppléments…)
- `OFFERS` : les grandes offres de l'accueil (à valider avec le patron)
- `ATL` : ingrédients et prix de l'Atelier (sandwich sur mesure). Visuels : `assets/atelier/` — un calque 900×360 par ingrédient (même cadre que le pain, on les empile), `pain-dessus.webp` pour le couvercle qui se referme à la fin, et `ic/` pour les pastilles de choix

## Hébergement

GitHub Pages, branche `main`, dossier racine.

Plan de communication et visibilité : `plan/` (en ligne sur `/plan/`).

`assets/` contient le logo détouré (fond clair / fond foncé).

## Photos

`assets/menu/` : photos d'illustration provisoires (Pexels, licence gratuite usage commercial). Chaque produit a `ID-t.jpg` (vignette 240×240) et `ID.jpg` (900×600), où ID est l'identifiant du produit dans `MENU` (s1, s2…). Pour mettre une vraie photo, remplace simplement les deux fichiers en gardant le même nom.

## Pied de page, réseaux et pages légales

Dans `CONFIG` (début du script de `index.html`) :

- `links` : Instagram, TikTok, Facebook, lien d'avis Google. Tant qu'un lien est vide, l'icône s'affiche grisée (« bientôt »).
- `legal` : nom de l'exploitant, forme juridique, numéro BCE, e-mail. Les champs entre crochets apparaissent surlignés en jaune sur les pages Mentions légales, Confidentialité, Conditions de vente et Allergènes, tant qu'ils ne sont pas remplis. Ces textes sont des modèles à faire relire.

## Comptes clients (connexion + historique)

Sans configuration, le site fonctionne déjà : le profil et l'historique restent sur le téléphone du client.
Pour activer les vrais comptes (historique sur tous les appareils), il faut un projet Supabase (gratuit) :

1. Crée un projet sur supabase.com — choisis une région **Europe** (RGPD).
2. **SQL Editor** → colle et exécute `supabase/schema.sql`.
3. **Authentication → Providers → Email** : activé.
4. **Authentication → Email Templates → Magic Link** : remplace le contenu par un message qui contient le code, par exemple :
   `Ton code Menzïli : {{ .Token }}` (le site demande un code à 6 chiffres, pas un lien).
5. **Authentication → URL Configuration → Site URL** : `https://kohdrare.github.io/Menzili/`
6. **Project Settings → API** : copie `Project URL` et la clé `anon public` dans `CONFIG.account` (`supabaseUrl`, `supabaseAnonKey`).

La clé `anon` est publique par conception : la sécurité est assurée par les règles RLS du fichier SQL (chaque client ne voit que ses propres données).
Pour des envois d'e-mails fiables en production, configure un SMTP personnalisé dans Supabase (l'envoi intégré est limité).

## Points clients (QR scanné au comptoir)

Remplace la carte fidélité à tampons (toujours dans le code, réactivable avec `CONFIG.points.enabled = false`).

- **Client** : « Mon profil » → « Mes points » → « Montrer mon QR ». Le QR change toutes les 10 minutes (une capture d'écran ne sert pas longtemps) ; un code de 9 caractères est affiché dessous si la caméra ne lit pas.
- **Personnel** : page `/staff/` (ex. `https://kohdrare.github.io/Menzili/staff/`), à ajouter sur l'écran d'accueil du téléphone. Connexion par e-mail, scan du QR, saisie du montant payé → points ajoutés. Boutons pour offrir une récompense (les points sont retirés). Les mouvements de moins de 15 minutes peuvent être annulés.
- **Règles** : `CONFIG.points` dans `index.html` (`perEuro`, `rewards`). Recopier les mêmes valeurs dans `CFG` en haut de `staff/index.html`.

### Mise en place (une fois)

1. Supabase → **SQL Editor** → colle et exécute `supabase/points.sql`.
2. Chaque employé se connecte une fois sur le site (Mon profil) avec son e-mail.
3. Pour l'ajouter au personnel, exécute dans le SQL Editor (en remplaçant prénom et e-mail) :
   ```sql
   insert into public.team (user_id, name)
   select id, 'Prénom' from auth.users where email = 'adresse@exemple.be'
   on conflict (user_id) do update set name = excluded.name;
   ```
   Retirer quelqu'un : `delete from public.team where user_id = (select id from auth.users where email = 'adresse@exemple.be');`

Sécurité : seuls les comptes de la table `team` peuvent ajouter ou retirer des points (vérifié côté serveur par les fonctions SQL). Un client ne peut ni se donner de points, ni descendre sous zéro, ni lire la liste du personnel.

Bibliothèques incluses dans `assets/vendor/` : qrcode-generator (MIT) pour afficher le QR, jsQR (Apache-2.0) pour le scanner.

## Carte fidélité

`assets/fidelite.jpg` est affichée dans « Mon profil ». Les tampons (positions calées sur les 9 cercles de la carte) se remplissent avec les sandwichs commandés sur le site : sandwichs chauds et froids, créations de l'Atelier, Menu Pause. Au 9e tampon, le 10e sandwich est offert. Le message WhatsApp le signale au snack, qui le déduit au retrait ou à la livraison.
Règle modifiable dans `CONFIG.loyalty.every`.

⚠️ Clés Supabase : seule la clé **publishable** (`sb_publishable_…`) va dans le site. La clé **secret** (`sb_secret_…`) ne doit jamais être publiée ni partagée.

## Méthodes de connexion (numéro, Google, Apple)

Le site lit automatiquement les méthodes activées dans Supabase (Authentication → Sign In / Providers) : un bouton apparaît pour chaque méthode activée, sans toucher au code.

Pour toutes les méthodes, ajoute l'adresse du site dans **Authentication → URL Configuration → Redirect URLs** : `https://kohdrare.github.io/Menzili/**`

- **E-mail** : déjà actif (code à 6 chiffres, voir plus haut pour le modèle d'e-mail).
- **Numéro de téléphone (SMS)** : Providers → Phone → activer, puis brancher un fournisseur SMS (Twilio, MessageBird, Vonage ou Textlocal). Les SMS sont payants (quelques centimes par code).
- **Google** (gratuit) : dans Google Cloud Console → APIs & Services → Credentials → *Create OAuth client ID* (type « Web application »). Dans *Authorized redirect URIs*, colle l'URL de callback affichée par Supabase (`https://awrvyfeagqicwjcswutw.supabase.co/auth/v1/callback`). Copie ensuite le Client ID et le Client Secret dans Supabase → Providers → Google.
- **Apple** : nécessite un compte Apple Developer (payant, abonnement annuel). Crée un *Services ID* et une clé *Sign in with Apple*, puis renseigne-les dans Supabase → Providers → Apple (même URL de callback).
