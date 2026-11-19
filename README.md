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
- `ATL` : ingrédients et prix de l'Atelier (sandwich sur mesure, ingrédients dessinés en SVG)

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
