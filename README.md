# Moovi Admin

Back-office de la plateforme Moovi (Vue 3 + Vite + Pinia, design Bootstrap
existant). Toutes les données viennent de l'API Moovi (`../api`), routes
`/api/admin/*` réservées aux comptes administrateurs.

## Écrans

| Écran | Rôle |
| --- | --- |
| Tableau de bord | Activité (courses, encaissements, commissions par jour), chauffeurs en ligne, alertes à traiter |
| Carte des chauffeurs | Carte OpenStreetMap (Leaflet, sans clé). Chargée une seule fois, puis 100 % temps réel par Socket.IO : chaque position arrive avec la fiche du chauffeur, les changements de course et de disponibilité aussi ; aucune requête périodique. Marqueurs animés, signal perdu signalé après 2 min, info-bulle avec accès à la fiche et à la course |
| Courses | Recherche et filtres (statut, règlement, dates) ; fiche : trajet, chronologie, offres, discussion, paiements, mouvements de portefeuille, évaluations, annulation |
| Paiements | Paiements Mobile Money PawaPay des courses (dont débits en double à rembourser) et mouvements des portefeuilles chauffeurs |
| Chauffeurs | Filtres (dossier, en ligne, véhicule, bloqués) ; fiche : documents à valider/refuser, véhicules, portefeuille (historique, ajustement motivé), courses, mise hors ligne, suspension |
| Validation des dossiers | File des dossiers en attente |
| Flotte | Véhicules déclarés, validation / refus |
| Utilisateurs | Passagers, chauffeurs, administrateurs ; fiche : courses, avis, suspension, message ciblé |
| Codes promo | Création, utilisations, activation |
| Notifications | Message à tous, aux passagers, aux chauffeurs ou aux chauffeurs en ligne |
| Paramètres | Configuration en vigueur (lecture seule, modifiable dans le `.env` de l'API) et état du serveur |

Les badges du menu et la cloche se mettent à jour toutes les minutes.

## Compte administrateur

Créé côté API :

```powershell
cd ..\api
.venv\Scripts\flask.exe --app wsgi.py create-admin --email vous@exemple.com --password "<mot de passe fort>"
```

## Développement

```sh
npm install
npm run dev        # http://localhost:5173, API définie dans .env.development
npm run lint
```

L'adresse de l'API se règle dans `.env.development` / `.env.production`
(`VITE_API_URL`, par défaut `http://192.168.1.114:5000`). L'API doit autoriser
l'origine du back-office (`CORS_ORIGINS` dans son `.env`).

## Mise en ligne

Deux possibilités :

1. **Servi par l'API (recommandé)** : `npm run build:api` compile dans
   `../api/app/static/admin`. Le back-office est alors disponible sur
   `http://<serveur>:5000/admin`, sur la même origine que l'API (pas de CORS).
2. **Hébergé à part** : `npm run build` produit `dist/` (site statique). Le
   serveur web doit renvoyer `index.html` pour toute adresse inconnue
   (navigation de l'application).

Le jeton de session est conservé dans le navigateur (localStorage) et renouvelé
automatiquement ; la déconnexion le révoque côté API.
