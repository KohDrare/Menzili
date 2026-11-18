# Menzïli — Commande en ligne

Site de commande du snack **Menzïli**, Rue Haute 326, 1000 Bruxelles (Marolles), à deux pas de l'hôpital Saint-Pierre.

- À emporter : retrait au comptoir à l'heure choisie
- Livraison Saint-Pierre : livré au service, commande avant 10:30, réduction personnel −10 %
- Les commandes sont envoyées au snack via WhatsApp (aucun serveur nécessaire)

## Modifier le site

Tout se trouve dans `index.html` (page unique, sans dépendances) :

- `CONFIG` : numéro WhatsApp qui reçoit les commandes, horaires, réduction, créneaux de livraison, minimum de commande
- `MENU` : catégories, produits, prix, options (sauces, crudités, suppléments…)

## Hébergement

GitHub Pages, branche `main`, dossier racine.

Plan de communication et visibilité : `plan/` (en ligne sur `/plan/`).

`assets/` contient le logo détouré (fond clair / fond foncé).

## Photos

`assets/menu/` : photos d'illustration provisoires (Pexels, licence gratuite usage commercial). Chaque produit a `ID-t.jpg` (vignette 240×240) et `ID.jpg` (900×600), où ID est l'identifiant du produit dans `MENU` (s1, s2…). Pour mettre une vraie photo, remplace simplement les deux fichiers en gardant le même nom.
