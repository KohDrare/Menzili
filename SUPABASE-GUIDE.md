# Refaire Supabase sur le compte Google du Menzïli

Guide pas à pas pour recréer toute la partie serveur (comptes clients, points, commandes, espace personnel) dans un **nouveau projet Supabase**, ouvert avec le compte Google du Menzïli.

Durée : environ 30 minutes.

> ⚠️ **Supprimer l'ancien projet efface tout ce qu'il contient** : comptes clients, points, commandes, liste du personnel. Rien n'est récupérable ensuite. Suis l'ordre ci-dessous : on crée et on teste le nouveau projet **avant** de supprimer l'ancien, pour que le site ne soit jamais en panne.

---

## 1. Créer le nouveau projet

1. Va sur **supabase.com** → *Sign in* → **Continue with Google** → choisis le **compte Google du Menzïli**.
2. Crée une organisation (ex. « Menzïli »), plan **Free**.
3. **New project** :
   - Nom : `Menzili`
   - Mot de passe de la base : clique sur *Generate*, puis **garde-le** dans un endroit sûr (gestionnaire de mots de passe). On n'en a pas besoin pour le site, mais il sert en cas de dépannage.
   - Région : **Europe (Frankfurt)** ou une autre région Europe (RGPD).
4. Attends 1 à 2 minutes que le projet soit prêt.

## 2. Créer les tables et les fonctions (une seule commande)

1. Menu de gauche → **SQL Editor** → *New query*.
2. Ouvre le fichier **`supabase/installation-complete.sql`** du dépôt GitHub, copie **tout** son contenu et colle-le.
3. Clique sur **Run**. Résultat attendu : *Success. No rows returned*.

Ce fichier contient, dans le bon ordre : les profils et l'historique (`schema.sql`), les points et le QR (`points.sql`), les commandes en direct (`commandes.sql`). Il peut être relancé sans risque.

Vérification (facultatif), dans une nouvelle requête :

```sql
select tablename from pg_tables where schemaname = 'public';
```

Tu dois voir : `profiles`, `orders`, `team`, `points_ledger`, `qr_tokens`, `shop_orders`.

## 3. Connexion par e-mail (code à 6 chiffres)

1. **Authentication → Sign In / Providers → Email** : activé.
   Si un réglage **Email OTP length** existe, mets **6**.
2. **Authentication → Emails → Templates**, modifie ces deux modèles pour qu'ils contiennent le code :
   - **Magic Link** et **Confirm signup**. Par exemple :
     - Sujet : `Ton code Menzïli`
     - Contenu : `<h2>Ton code Menzïli : {{ .Token }}</h2><p>Il est valable quelques minutes.</p>`
   Le site demande un **code**, pas un lien : `{{ .Token }}` est obligatoire.
3. **Authentication → URL Configuration** :
   - **Site URL** : `https://kohdrare.github.io/Menzili/`
   - **Redirect URLs** → *Add URL* : `https://kohdrare.github.io/Menzili/**`

## 4. Connexion avec Google

Le site affiche le bouton Google tout seul dès que Google est activé dans Supabase.

1. Dans Supabase : **Authentication → Sign In / Providers → Google**. Note l'**URL de callback** affichée, de la forme
   `https://XXXXXXXX.supabase.co/auth/v1/callback` (XXXXXXXX = l'identifiant du nouveau projet).
2. Va sur **console.cloud.google.com** avec le **compte Google du Menzïli** → crée un projet (ex. « Menzili site »).
3. **APIs & Services → OAuth consent screen** (ou *Google Auth Platform*) :
   - Type : **External**, nom de l'app : `Menzïli`, e-mail d'assistance : celui du Menzïli.
   - Publie l'application (*Publish app*) pour que tout le monde puisse se connecter.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID** :
   - Type : **Web application**
   - *Authorized JavaScript origins* : `https://kohdrare.github.io`
   - *Authorized redirect URIs* : l'URL de callback notée à l'étape 1.
5. Copie le **Client ID** et le **Client Secret**, colle-les dans Supabase → Providers → Google → **Enable** → *Save*.

> Si tu gardes l'ancien client OAuth (sur ton compte perso), il faut au minimum remplacer son *Authorized redirect URI* par celle du nouveau projet. Le refaire sur le compte du Menzïli est plus propre.

## 5. Brancher le site sur le nouveau projet

1. Supabase → **Project Settings → API Keys** (ou *Data API*) :
   - **Project URL** : `https://XXXXXXXX.supabase.co`
   - **Publishable key** : `sb_publishable_…`
2. Envoie-moi ces deux valeurs et je fais le changement, ou modifie-les toi-même à **deux endroits** :
   - `index.html` → `CONFIG.account` → `supabaseUrl` et `supabaseAnonKey`
   - `staff/index.html` → `CFG` (en haut du script) → `supabaseUrl` et `supabaseAnonKey`

> ⚠️ Seule la clé **publishable** (`sb_publishable_…`) va dans le site : elle est publique par conception. La clé **secret** (`sb_secret_…`) ne doit **jamais** être mise dans le site ni partagée.

## 6. Recréer le personnel

Les comptes sont propres à chaque projet : tout le monde repart de zéro.

1. Chaque membre du personnel se connecte **une fois** sur le site (Mon profil), avec son e-mail ou Google.
2. Dans **SQL Editor**, pour chacun (remplace le prénom et l'e-mail) :

```sql
insert into public.team (user_id, name)
select id, 'Prénom' from auth.users where email = 'adresse@exemple.be'
on conflict (user_id) do update set name = excluded.name;
```

3. Vérifier la liste :

```sql
select t.name, u.email from public.team t join auth.users u on u.id = t.user_id;
```

Retirer quelqu'un :

```sql
delete from public.team where user_id = (select id from auth.users where email = 'adresse@exemple.be');
```

## 7. Tester avant de supprimer l'ancien projet

- [ ] Se connecter sur le site avec un e-mail (le code arrive bien) et avec Google.
- [ ] Mon profil → **Mon QR** : le QR s'affiche.
- [ ] Ouvrir `kohdrare.github.io/Menzili/staff/` avec un compte du personnel : l'onglet **Commandes** s'affiche.
- [ ] Passer une petite commande test sur le site **sans être connecté** : elle apparaît dans l'espace personnel avec le son, et la page de suivi du client se met à jour quand on la passe en « En préparation ».
- [ ] Scanner le QR d'un client et lui ajouter des points.
- [ ] Annuler la commande test (bouton ⋯ → Annuler).

## 8. Supprimer l'ancien projet

Seulement quand tout fonctionne :

1. Ouvre l'**ancien** projet (compte perso) dans Supabase.
2. **Project Settings → General → Delete project** → confirme avec le nom du projet.

Pense aussi à supprimer l'ancien client OAuth dans ton Google Cloud perso s'il ne sert plus.

---

### En option : e-mails fiables

L'envoi d'e-mails intégré à Supabase est limité (quelques e-mails par heure). Pour un vrai lancement, configure un expéditeur dans **Authentication → Emails → SMTP Settings** (par exemple Resend, Brevo ou l'adresse e-mail du Menzïli) : les codes de connexion arriveront plus vite et ne tomberont pas en spam.
