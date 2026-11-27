# Moovi VTC — API Flask & Temps Réel (Socket.IO + MySQL)

Backend Flask complet remplaçant Firebase (Auth, Firestore, Storage) pour l'application mobile Moovi VTC, avec gestion temps réel par **WebSockets (Flask-SocketIO)** et persistance **MySQL (`moovi_bd`)**.

## Architecture du projet

```
api/
├─ app.py                     # Point d'entrée Flask + Socket.IO
├─ requirements.txt           # Dépendances Python
├─ pytest.ini                 # Configuration des tests
├─ .env / .env.example        # Variables d'environnement MySQL & clés API
├─ app/
│  ├─ __init__.py             # Factory create_app() + commandes CLI
│  ├─ extensions.py           # db, migrate, jwt, cors, socketio
│  ├─ configs/config.py       # Configurations dev / test / prod
│  ├─ models/                 # Modèles SQLAlchemy (MySQL)
│  │  ├─ user.py              # User, OtpCode, TokenBlocklist, DeviceToken
│  │  ├─ driver.py            # Driver, DriverDocument
│  │  ├─ vehicle.py           # Véhicules multiples par chauffeur
│  │  ├─ benefits.py          # Promotions, parrainages et crédits
│  │  ├─ ride.py              # Ride, RideOffer, RideRating
│  │  ├─ wallet.py            # WalletTransaction
│  │  └─ chat.py              # RideMessage, Notification
│  ├─ tools/                  # Utilitaires et intégrations
│  │  ├─ auth_helpers.py      # OTP, JWT, décorateurs rôles
│  │  ├─ geo.py               # Haversine, ETA, normalisation téléphones
│  │  ├─ pricing.py           # Tarifs, bornes (500..50000 XAF), commission 15%
│  │  ├─ storage.py           # Stockage local fichiers (avatars & documents)
│  │  ├─ sms.py               # Envoi OTP SMS
│  │  ├─ google_maps.py       # Proxy Places & Routes v2
│  │  ├─ pawapay.py           # Mobile Money : recharge chauffeur + paiement des courses
│  │  ├─ realtime.py          # Émissions Socket.IO & notifications
│  │  ├─ background_jobs.py   # Expiration et présence des chauffeurs
│  │  └─ responses.py         # Réponses JSON & gestionnaire d'erreurs
│  └─ views/                  # Blueprints REST & gestionnaires WebSocket
│     ├─ health.py            # / et /api/health
│     ├─ auth.py              # /api/auth/* (OTP, email, refresh, logout)
│     ├─ users.py             # /api/users/* (profil, avatar, historique)
│     ├─ drivers.py           # /api/drivers/* (inscription, docs, GPS, nearby)
│     ├─ rides.py             # /api/rides/* (courses, offres, statuts, notes)
│     ├─ wallet.py            # /api/wallet/* (solde, PawaPay)
│     ├─ payments.py          # /api/rides/*/pay/* et /api/webhooks/*
│     ├─ maps.py              # /api/maps/* (Places, Routes)
│     ├─ chat.py              # /api/rides/*/messages
│     ├─ notifications.py     # /api/notifications/*
│     ├─ admin.py             # /api/admin/* (validation documents, stats)
│     ├─ files.py             # /api/files/*
│     └─ realtime.py          # Événements Socket.IO temps réel
└─ tests/
   └─ test_api_and_realtime.py
```

## Démarrage rapide

```powershell
# Créer / mettre à jour les tables MySQL (migrations Alembic)
.venv\Scripts\flask.exe --app wsgi.py db upgrade

# Créer un compte administrateur (interface http://<serveur>:5000/admin)
.venv\Scripts\flask.exe --app wsgi.py create-admin --email vous@exemple.com --password "<mot de passe fort>"

# (Optionnel) Ajouter 15 chauffeurs de test à Libreville
.venv\Scripts\flask.exe --app app.py seed-test-drivers --count 15

# Ajouter des données de démonstration (développement uniquement)
.venv\Scripts\flask.exe --app app.py seed-demo-data

# Lancer le serveur Flask + Socket.IO
.venv\Scripts\python.exe app.py

# Exécuter les tests automatisés
.venv\Scripts\python.exe -m pytest -v
```

La commande `seed-demo-data` crée sans doublons un compte passager, cinq
chauffeurs fictifs, des véhicules et quatre courses d’exemple. Les chauffeurs
portent le marqueur de test; en développement, connectez les comptes via OTP
avec les numéros `+24107000001` (passager) et `+24107000011` à `+24107000015`
(chauffeurs). La commande est refusée en production et n’efface aucune donnée.

## Envoi des codes OTP avec WAHA (temporaire)

L'API envoie les OTP par WhatsApp avec l'endpoint WAHA documenté
`POST /api/sendText`. Dans le `.env` de l'API, configurez
`SMS_PROVIDER=waha`, `WAHA_BASE_URL=http://localhost:3000`, le nom de session
WAHA (`WAHA_SESSION=default`) et la clé requise par votre instance dans
`WAHA_API_KEY`. La clé reste côté serveur et ne doit pas être intégrée à
l'application mobile. Redémarrez Flask après cette configuration.

Le numéro de test WhatsApp est `+22891596443`. `OTP_DEBUG_RETURN_CODE=true`
renvoie le code dans la réponse API : n'importe qui pourrait alors se connecter
sur n'importe quel numéro. L'option est désactivée dans le `.env` et n'est
activée que par la configuration de tests automatisés. Une erreur WAHA produit une réponse
`502 OTP_DELIVERY_FAILED`, sans faux succès. WAHA doit pouvoir joindre WhatsApp
via une session connectée; `localhost` désigne la machine où tourne l'API Flask.

## Application mobile (Flutter)

L'application `moovi_mobile-master` n'utilise plus Firebase : authentification,
profils, chauffeurs, courses, offres, portefeuille, documents et fichiers passent
tous par cette API. Les clés de services tiers sont uniquement dans le `.env`
de l'API :

| Variable | Usage |
| --- | --- |
| `GOOGLE_MAPS_API_KEY` | Proxy Places / Routes (`/api/maps/*`) |
| `GOOGLE_MAPS_MOBILE_API_KEY` | SDK Google Maps natif Android, injecté au build par Gradle (`android/app/build.gradle.kts` lit `../api/.env`, ou `MAPS_API_KEY` en variable d'environnement / `local.properties`). À restreindre au package `wicotech.com.moovi` + empreinte SHA-1 dans la console Google. |
| `PAWAPAY_TOKEN`, `PAWAPAY_PRODUCTION`, `PAWAPAY_WEBHOOK_SECRET` | Seul prestataire de paiement : recharge du portefeuille chauffeur (`/api/wallet/recharge`) et paiement des courses par le passager (`/api/rides/<id>/pay/mobile-money`, Airtel / Moov Money) |
| `WAHA_*` | Envoi des codes OTP par WhatsApp |

L'application pointe par défaut sur `http://192.168.1.114:5000`
(`lib/services/api_client.dart`) : un simple `flutter run` ou
`flutter build apk --release` suffit, et l'APK obtenu peut être partagé tel
quel aux téléphones connectés au même réseau Wi-Fi que le serveur.

- L'API doit écouter sur toutes les interfaces (`HOST=0.0.0.0`, valeur par
  défaut de `app.py`) et le port 5000 doit être ouvert dans le pare-feu Windows.
- Le HTTP non chiffré est autorisé uniquement vers `192.168.1.114` et
  `10.0.2.2` (`android/app/src/main/res/xml/network_security_config.xml`,
  `ios/Runner/Info.plist`). Si l'IP du serveur change, mettre à jour ces deux
  fichiers et l'URL par défaut.
- Pour une autre API sans modifier le code :
  `flutter build apk --dart-define=MOOVI_API_URL=https://api.exemple.com`.
  Une diffusion publique doit passer en HTTPS (`wss://` pour Socket.IO).
- L'APK release est signé avec `android/app/moovi-release.jks` (mots de passe
  dans `android/key.properties`, tous deux exclus de git). **Sauvegarder ces deux
  fichiers** : sans eux, impossible de publier une mise à jour de l'application.
- Mode chauffeur : en ligne, une notification permanente (service de position
  de premier plan) garde la position et le temps réel actifs en arrière-plan ;
  les nouvelles courses et les messages s'affichent en notification système.

### Temps réel dans l'application

L'application ouvre une connexion Socket.IO authentifiée dès la connexion de
l'utilisateur (`lib/services/realtime_service.dart`) et la ferme à la
déconnexion. Les écrans s'abonnent via `liveApi` : les données sont rechargées
depuis l'API à chaque événement pertinent (environ 0,3 s), et une
interrogation périodique ne sert plus que de secours quand le socket est coupé.

| Écran | Événements |
| --- | --- |
| Courses disponibles (chauffeur) | `ride:new`, `ride:taken`, `ride:expired`, `ride:cancelled` |
| Offres reçues (passager) | `ride:offer_received`, `ride:accepted` |
| Suivi de course (deux côtés) | `ride:accepted`, `ride:status_changed`, `ride:paid`, `ride:cancelled`, `ride:expired`, `ride:driver_location` |
| Chauffeurs sur la carte | `driver:location_updated`, `driver:availability_changed` |
| Portefeuille | `wallet:updated`, `ride:paid` |
| Documents chauffeur | `driver:verification_updated`, notifications `document_reviewed` |
| Chat de course | `ride:message` (envoi par `POST /api/rides/<id>/messages`) |
| Notifications + bandeau | `notification:new` |
| Mise hors ligne par le serveur | `driver:offline` |

Le chauffeur envoie sa position par `driver:location_update` (repli REST si le
socket est coupé). Quand l'état change par une route REST (passage en ligne,
inscription, course créée ou acceptée), l'API inscrit elle-même les connexions
Socket.IO concernées dans les rooms (`sync_driver_rooms`, `add_user_to_room`) ;
chaque événement est émis une seule fois par connexion (`emit_to_rooms`).
Cette inscription côté serveur vaut pour un seul processus : en multi-worker,
l'application se réabonne aussi aux courses via `join_ride`, mais le passage en
ligne nécessite un gestionnaire de messages partagé (Redis).

Test d'intégration temps réel (API de test démarrée au préalable) :

```powershell
flutter test test/realtime_e2e_test.dart --dart-define=MOOVI_API_URL=http://127.0.0.1:5055
```

## Back-office d'administration

Le back-office est l'application Vue du dossier `../Moovi`. Compilé avec
`npm run build:api`, il est servi par l'API sur `http://<serveur>:5000/admin`
(connexion avec un compte créé par `create-admin`). Il couvre tableau de bord,
courses, paiements, chauffeurs (dossiers, documents, portefeuilles, suspension),
flotte, carte des chauffeurs en direct, utilisateurs, codes promo, notifications
et paramètres. Les sockets des administrateurs rejoignent la room `admins` : chaque
position y arrive avec la fiche complète du chauffeur (`admin:driver_update`),
ainsi que les changements d'état des courses ; la carte (OpenStreetMap) ne
fait aucune requête périodique. Voir
`../Moovi/README.md`.

Routes dédiées (`/api/admin/*`, administrateur uniquement) : `overview`,
`drivers/map` (positions, état disponible / en course / hors ligne),
`users`, `users/<id>/status`, `drivers` (+ `offline`, `wallet-adjustment`,
`transactions`, `rides`, validation des documents et véhicules), `vehicles`,
`rides`, `payments` (+ `refunded`), `wallet-transactions`, `notifications`,
`promo-codes`, `settings`.

`REQUIRE_DRIVER_VERIFICATION=true` : un chauffeur ne peut se mettre en ligne
qu'une fois son dossier validé dans le back-office.

## Sécurité et mise en production

| Réglage `.env` | Valeur | Pourquoi |
| --- | --- | --- |
| `OTP_DEBUG_RETURN_CODE` | `false` | Sinon le code OTP est lisible dans la réponse de l'API. |
| `FLASK_DEBUG` | `false` | Le débogueur Werkzeug permet d'exécuter du code à distance. |
| `REQUIRE_DRIVER_VERIFICATION` | `true` | Aucun chauffeur sans dossier validé. |
| `CORS_ORIGINS` | domaines séparés par des virgules | Ne concerne que les navigateurs ; l'application mobile n'envoie pas d'origine. |
| `SOCKETIO_MESSAGE_QUEUE`, `RATELIMIT_STORAGE_URI` | `redis://…` | Obligatoires dès que l'API tourne sur plusieurs processus. |
| `LOG_FOLDER`, `LOG_LEVEL` | `logs`, `INFO` | Journal tournant `logs/moovi-api.log` (5 × 5 Mo). |
| `SUPPORT_PHONE`, `SUPPORT_WHATSAPP`, `SUPPORT_EMAIL` | contacts | Affichés dans l'écran « Assistance » de l'application. |

`python app.py` est réservé au développement (il refuse `APP_ENV=production`).
En production, sous Linux, derrière un proxy HTTPS (nginx ou Caddy) :

```bash
APP_ENV=production gunicorn --worker-class gthread --workers 1 --threads 100 \
  --bind 127.0.0.1:5000 wsgi:app
```

Le schéma de base est versionné dans `migrations/` (Alembic) : après une
modification des modèles, `flask --app wsgi.py db migrate -m "…"` puis
`flask --app wsgi.py db upgrade`. La base existante a été marquée à la
révision initiale (`db stamp head`).

PawaPay est le seul prestataire de paiement (recharges chauffeur et paiement
des courses). Les paiements sont réels : `PAWAPAY_PRODUCTION=true` avec un
jeton de production. Pour des essais sans argent réel, passer
`PAWAPAY_SIMULATE=true`. Le webhook `POST /api/webhooks/pawapay` confirme
recharges et courses ; sans `PAWAPAY_WEBHOOK_SECRET`, l'API revérifie chaque
statut auprès de PawaPay avant de créditer quoi que ce soit.

## Règles métier et sécurité (audit du 27/11/2026)

- **Commission** : prélevée sur le portefeuille dès que le chauffeur termine la
  course, quel que soit le règlement. Solde négatif ⇒ chauffeur bloqué et mis
  hors ligne immédiatement (temps réel).
- **Paiement Mobile Money (PawaPay)** : uniquement une fois la course terminée,
  en XAF (Gabon, Cameroun, Congo). Le prix payé est reversé au portefeuille du
  chauffeur. Chaque dépôt est enregistré dans `ride_payments` : pas de seconde
  demande ni d'encaissement espèces tant qu'un dépôt est en attente ; un débit
  reçu pour une course déjà réglée est marqué `duplicate` (à rembourser).
- **Rapprochement** : toutes les 60 s, les dépôts PawaPay en attente (courses et
  recharges) sont vérifiés auprès de PawaPay, même si le webhook ne peut pas
  joindre le serveur.
- **Attribution** : un chauffeur ne peut ni proposer ni être accepté s'il a déjà
  une course, si son portefeuille est bloqué, si son dossier n'est pas validé ou
  si son véhicule ne correspond pas à la catégorie. Les nouvelles courses ne
  sont diffusées qu'aux chauffeurs de la bonne catégorie, sans le téléphone du
  passager ; un chauffeur ne voit jamais les offres de ses concurrents.
- **Confidentialité** : la salle temps réel d'une course (chat, position,
  paiement) est réservée au passager et au chauffeur attribué. La carte passager
  ne reçoit des chauffeurs que position, véhicule et note (rayon ≤ 20 km).
- **Connexion** : codes OTP plafonnés par numéro (5 envois et 10 erreurs par
  heure), numéro rattaché à un compte uniquement après preuve OTP (inscription
  e-mail et changement de numéro compris), jeton de rafraîchissement révoqué et
  sockets fermés à la déconnexion.
- **Configuration** : `SECRET_KEY`/`JWT_SECRET_KEY` (≥ 32 caractères)
  obligatoires hors tests ; `PAWAPAY_SIMULATE=true` refusé en production ;
  `TRUST_PROXY=true` derrière un proxy ; `PUBLIC_BASE_URL` pour les URL de
  fichiers (jamais déduites de l'en-tête Host stocké).

## Documentation Swagger / OpenAPI

Démarrer l’API puis ouvrir **`http://localhost:5000/api/docs/`** pour explorer
et tester les endpoints REST. Le schéma OpenAPI JSON est disponible à
**`http://localhost:5000/api/openapi.json`**. Dans Swagger UI, cliquer sur
**Authorize** et fournir le JWT d’accès (sans préfixer `Bearer`); les routes
publiques, les webhooks et les routes protégées sont distingués dans le schéma.
Les événements Socket.IO restent décrits dans la section ci-dessous.

`init-db` crée également les tables `vehicles`, `promo_codes`, `ride_benefits`,
`referral_codes`, `referrals` et `user_credit_transactions`. Les tâches de fond
sont activées par défaut hors tests. Elles expirent les recherches après
`RIDE_SEARCH_TIMEOUT_SECONDS` (300 s) et retirent les chauffeurs sans position/
heartbeat depuis `DRIVER_DISCONNECT_GRACE_SECONDS` (30 s). En déploiement
multi-worker, les verrous MySQL protègent les transitions; configurez également
un stockage de rate limit partagé.

## Routes métier ajoutées

- `GET /api/drivers/me/rides` : historique paginé et revenus payés du jour, de
  la semaine et du mois (heure locale Libreville; tarif brut, montant encaissé,
  commission et revenu net).
- `GET|POST /api/drivers/me/vehicles` et
  `PUT /api/drivers/me/vehicles/<vehicleId>/activate` : gérer plusieurs véhicules.
  L'ancien endpoint `/api/drivers/register` et les champs historiques restent
  disponibles; un administrateur valide chaque nouveau véhicule avec
  `POST /api/admin/drivers/<driverId>/vehicles/<vehicleId>/review`.
- `DELETE /api/users/me` : désactive et anonymise le compte sans effacer les
  historiques financiers; la suppression est refusée pendant une course active.
- `GET /api/users/me/referral` expose le code et les crédits. Un code peut être
  transmis avec `referralCode` lors de l'inscription OTP ou email. Les deux
  comptes reçoivent chacun 500 XAF après la première course payée et terminée.
- La première course payée bénéficie d'une réduction Moovi de 500 XAF. Les
  crédits de parrainage s'appliquent ensuite; le chauffeur reçoit une écriture
  `promo_subsidy` pour compenser les réductions financées par Moovi.
- Les codes promotionnels additionnels sont gérés par
  `POST|GET /api/admin/promo-codes` et `PATCH /api/admin/promo-codes/<id>`.
- La réinitialisation de mot de passe répond explicitement
  `503 PASSWORD_RESET_UNAVAILABLE` tant qu'aucun fournisseur email n'est configuré.

## Événements temps réel (Socket.IO)

Connexion avec JWT : `auth: { token: "<accessToken>" }` (ou `?token=...`).

- **Client → Serveur** : `join_ride`, `leave_ride`, `driver:go_online`, `driver:go_offline`, `driver:location_update`, `driver:heartbeat` (ou `ping`), `ride:send_message`
- **Serveur → Client** : `connected` (inclut les courses actives réabonnées), `driver:availability_changed`, `driver:location_updated`, `driver:offline`, `ride:new`, `ride:offer_received`, `ride:accepted`, `ride:taken`, `ride:expired`, `ride:status_changed`, `ride:driver_location`, `ride:message`, `ride:paid`, `ride:cancelled`, `wallet:updated`, `driver:verification_updated`, `notification:new`

Le client chauffeur doit émettre `driver:heartbeat` périodiquement (par exemple
toutes les 10 secondes) lorsqu'il est en ligne. Une reconnexion réabonne
automatiquement l'utilisateur à ses courses actives.
