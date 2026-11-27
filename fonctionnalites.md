# Moovi — Analyse fonctionnelle de l'application Flutter

> Application de VTC (Voiture / Moto) ciblant principalement le **Gabon** (Libreville), avec une architecture **Flutter + Firebase** et des intégrations **Google Maps / Places / Routes**, **PawaPay** (Mobile Money) et **PayCentral**.
>
> Ce document décrit **tout ce qui est réellement implémenté**, **comment chaque fonctionnalité fonctionne**, puis liste **ce qui est partiel, non branché ou buggé**.

---

## 1. Résumé exécutif

L'application est un prototype avancé de plateforme VTC avec deux rôles :

| Rôle | Accès | Fonctionnalités principales |
|---|---|---|
| **Passager** | Connexion par téléphone + OTP | Carte, recherche de lieux, itinéraire, choix du véhicule, prix libre, création de course, réception des offres chauffeurs, acceptation, suivi, historique, profil |
| **Chauffeur** | Depuis le profil passager → « Passer en mode chauffeur » | Inscription véhicule (voiture/moto), upload des documents, vérification, mise en ligne, consultation des courses, négociation, offre, course active, encaissement cash, commission 15 %, portefeuille Mobile Money |

**Points forts déjà fonctionnels :** authentification OTP Firebase, carte temps réel, autocomplétion Google Places, tracé d'itinéraire Google Routes, création de courses Firestore, système d'offres chauffeur → passager en temps réel, machine à états de course, profil avec photo Firebase Storage, inscription chauffeur avec upload de documents, portefeuille chauffeur et rechargement PawaPay.

**Limites majeures :** plusieurs écrans/services sont **non branchés** (paiement PayCentral côté passager, page de statut des documents, profil chauffeur), la recherche de chauffeur réelle (`searchDriver`) est un **stub**, les chauffeurs réels n'apparaissent pas sur la carte passager (seuls les `test_drivers`), et plusieurs clés/API sont **en dur dans le code**.

---

## 2. Stack technique

### 2.1 Dépendances (`pubspec.yaml`)

| Dépendance | Usage réel |
|---|---|
| `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage` | Backend : auth, base NoSQL, stockage fichiers |
| `google_maps_flutter` | Cartes |
| `geolocator` | GPS / permissions |
| `http` | Appels REST (Places, Routes, PawaPay, PayCentral) |
| `flutter_polyline_points` | Décodage des polylines Google |
| `flutter_intl_phone_field` | Saisie du numéro international |
| `image_picker` | Photos profil et documents chauffeur |
| `dotted_line` | Ligne pointillée départ → destination |
| `geoflutterfire_plus` | Recherche de chauffeurs dans un rayon (service non utilisé) |
| `google_fonts`, `iconsax`, `google_places_flutter`, `flutter_launcher_icons` | Déclarés mais **non utilisés** dans `lib/` (hors génération d'icône) |

- SDK Dart : `>=3.0.0 <4.0.0`
- Version app : `1.0.0+1`
- Plateformes configurées : **Android** et **iOS** (pas de web/desktop, `firebase_options.dart` lève une erreur sur ces plateformes).

### 2.2 Configuration Firebase

- Projet : `yesiknow-febf2`
- Fichier `firebase.json` + `lib/firebase_options.dart`
- Bucket Storage : `yesiknow-febf2.firebasestorage.app`
- Aucun fichier `firestore.rules` / `storage.rules` / `firebase.json` de règles n'est présent dans le dépôt.

### 2.3 Point d'entrée (`lib/main.dart`)

```dart
main()
 ├─ WidgetsFlutterBinding.ensureInitialized()
 ├─ Firebase.initializeApp(DefaultFirebaseOptions.currentPlatform)
 ├─ PawaPayService.instance.configure(apiToken: <token en dur>, production: true)
 └─ runApp(MyApp)
      └─ MaterialApp(theme: AppTheme.lightTheme, home: AuthWrapper())
```

---

## 3. Navigation & authentification

### 3.1 `AuthWrapper` (`lib/auth_wrapper.dart`)

Écoute `FirebaseAuth.instance.authStateChanges()` :

- En attente → `CircularProgressIndicator`
- Utilisateur connecté → `Pagesmanager` (espace passager)
- Non connecté → `Signorlogin`

C'est le seul mécanisme de garde d'accès global.

### 3.2 Connexion par téléphone (`authScreens/SignOrLogin.dart`)

1. Écran avec logo, champ `IntlPhoneField` (indicatif pays, validation `isValidNumber`).
2. Pays initial : **MA (Maroc)** — incohérent avec le ciblage Gabon.
3. Bouton « Continuer » :
   - si numéro valide → `AuthService.instance.sendOTP(pays + numéro)`
   - puis navigation immédiate vers `Otpverification`.
4. Un booléen `isPhoneValid` empêche l'envoi si le numéro est invalide.

### 3.3 Vérification OTP (`authScreens/otpVerification.dart`)

- 6 cases de saisie (`TextEditingController` + `FocusNode` par case).
- Navigation automatique entre cases, retour arrière intelligent, collage d'un code complet.
- `AutofillHints.oneTimeCode` pour l'auto-remplissage.
- Compte à rebours de **30 secondes** avant renvoi.
- ⚠️ Le bouton « Renvoyer le code » **ne renvoie pas réellement de SMS** : il vide les cases, relance le timer et affiche un SnackBar (`// TODO`).
- Bouton « Envoyer » → `AuthService.verifyOTP(code)` puis navigation vers `Pagesmanager`, **sans vérifier le booléen retourné** (on peut arriver sur l'app même si le code est faux).

### 3.4 `AuthService` (`lib/services/Auth.dart`)

| Méthode | État | Détail |
|---|---|---|
| `register(fullname, email, password, role)` | **Non utilisée** | Crée un compte email/mot de passe + doc `users/{uid}` avec `fullname`, `email`, `role` |
| `login(email, password)` | **Non utilisée** | Connexion email/mot de passe |
| `sendOTP(phoneNumber)` | **Utilisée** | `FirebaseAuth.verifyPhoneNumber` ; stocke `verificationId` |
| `verifyOTP(smsCode)` | **Utilisée** | `PhoneAuthProvider.credential` + `signInWithCredential`, puis `createOrGetUser` |
| `createOrGetUser(user)` | **Utilisée** | Transaction Firestore : crée `users/{uid}` avec `phoneNumber`, `name: ''`, `email: ''`, `createdAt` si absent |
| `logout()` | **Non branchée** | `signOut()` existe mais aucun bouton ne l'appelle |

Conséquences :
- Un utilisateur OTP a un profil `firstName`/`lastName` vides → l'interface affiche « Utilisateur » jusqu'à modification manuelle.
- Aucune déconnexion possible depuis l'UI.

---

## 4. Espace passager

### 4.1 Navigation principale (`userScreens/PagesManager.dart`)

- `Scaffold` avec un `Stack`.
- 3 onglets dans `CustomNavbar` :
  - **ACCUEIL** → `MapPage`
  - **COURSE** → `HistoryPage`
  - **PROFIL** → `ProfilePage`
- La navbar flottante est positionnée au-dessus de la zone safe.
- `resizeToAvoidBottomInset: false`.

### 4.2 Carte & géolocalisation (`userScreens/mapPage.dart`)

**Initialisation (`initState`) :**
1. Abonnement au contrôleur de recherche (`_search.addListener`).
2. Chargement de l'icône voiture `assets/icon/car4.png` en `BitmapDescriptor`.
3. `_initLocation()` : vérifie service GPS + permissions (`Geolocator`), récupère la position haute précision.
4. `chargerStyle()` : lit `assets/map_style.json`… **mais le style n'est jamais appliqué** à `GoogleMap` (paramètre `style` absent).
5. `_listenToDrivers()` : écoute Firestore `test_drivers` où `isAvailable == true`.

**Affichage :**
- `GoogleMap` centrée sur la position, zoom 15.5.
- `myLocationEnabled: true`, boutons zoom/compas/trafic désactivés, gestes rotation/inclinaison désactivés.
- Marqueurs :
  - chauffeurs de `test_drivers` avec l'icône voiture,
  - départ (`origin`) si différent de la position courante,
  - destination.
- Tap sur la carte → ferme le clavier et les suggestions.

**Repli / erreurs :**
- Si GPS désactivé ou permission refusée → message + bouton « Réessayer ».
- Si position inconnue → loader.

**Bouton recentrer :** présent dans le code mais **commenté**.

**Import de chauffeurs de test :** bouton « Importer les 50 chauffeurs » **commenté** ; le service existe pourtant (`ImportDriversService`).

### 4.3 Recherche de lieux (Google Places)

Fichiers : `places_service.dart`, `place_search_controller.dart`.

**`PlacesService`** (API Google Places legacy) :
- `autocomplete(input, language: 'fr', country, bias, sessionToken)` → suggestions (`place_id`, texte principal/secondaire).
- `details(placeId)` → coordonnées `LatLng`.
- Gestion des erreurs HTTP et du champ `status` Google (`OK`, `ZERO_RESULTS`, etc.).
- Timeout de 8 s.

**`PlaceSearchController`** (logique indépendante de l'UI) :
- Deux champs : `origin` et `destination`, chacun avec `TextEditingController` + `FocusNode`.
- Suit le champ actif (`SearchField.origin` / `destination`).
- Debounce **350 ms**, minimum **3 caractères**.
- Jeton de session Google (facturation) régénéré après chaque `details`.
- `_requestId` pour ignorer les réponses obsolètes.
- `biasLocation` = position utilisateur pour favoriser les résultats proches.
- Sélection d'une suggestion → remplit le champ, ferme le clavier, récupère les coordonnées.
- Modification manuelle du texte → invalide le lieu précédemment choisi.
- `clear`, `setPlace`, `dismissSuggestions`.

**Intégration dans `MapPage` :**
- Pays forcé : `country: 'ga'` (Gabon).
- Le départ est initialisé à « Ma position ».
- Focus sur le champ départ → tout le texte est sélectionné ; champ vidé → retour à la position actuelle.
- Liste des suggestions affichée sous les champs (max 260 px), loader pendant la requête.
- Les « 3 dernières destinations » sont **commentées**.

### 4.4 Tracé d'itinéraire (`services/itinéraire/DirectionsService.dart`)

- Appel `POST https://routes.googleapis.com/directions/v2:computeRoutes`.
- Mode `DRIVE`, `polylineQuality: HIGH_QUALITY`.
- Champs demandés : `routes.polyline.encodedPolyline`, `routes.distanceMeters`, `routes.duration`.
- Décodage de la polyline via `PolylinePoints.decodePolyline`.
- `RouteInfo` expose `distanceKm`, `distanceText` (« 850 m » / « 12,4 km »), `durationText` (« 8 min » / « 1 h 05 min »).
- Dans la carte : **deux polylines superposées** (bordure foncée 11 px + trajet orange 7 px).
- En cas d'erreur → SnackBar « Impossible de tracer le trajet ».

### 4.5 Sélection du véhicule et du prix (`userScreens/widgets/rideSheetColors.dart`)

Bottom sheet ouvert **automatiquement 1,5 s après** que départ + destination sont définis.

**Options proposées (`kRideOptions`) :**

| ID | Titre | Sous-titre | Prix par défaut |
|---|---|---|---|
| `voiture` | Voiture | 4 places • Course standard | 2 000 FCFA |
| `confort` | Comfort | Berline premium climatisée | 3 500 FCFA |
| `moto` | Moto | Le plus rapide en circulation | 1 000 FCFA |

- Cartes animées, sélection orange.
- Sélecteur de prix avec boutons **− / +** par pas de **250 FCFA**, borné entre **500 et 50 000 FCFA**.
- Bouton « TROUVER UN CHAUFFEUR ».
- ⚠️ La distance et la durée calculées sont passées au sheet mais **ne sont pas affichées** et **n'influencent pas le prix** : le prix est choisi librement par le passager.

### 4.6 Création de la course (`lib/functions.dart`)

À la confirmation :

```dart
addRide(
  departureLat/Lng, destinationLat/Lng,
  price, departureAddress, destinationAddress,
  rideType, distanceText, durationText
)
```

Deux écritures Firestore :

1. `rides/{rideId}` :
```json
{
  "clientId": "<uid>",
  "departure": "GeoPoint",
  "destination": "GeoPoint",
  "departureAddress": "...",
  "destinationAddress": "...",
  "rideType": "voiture|confort|moto",
  "price": 2000,
  "currency": "XAF",
  "distance": "8.5 km",
  "duration": "12 min",
  "status": "searching",
  "driverId": null,
  "isPaid": false,
  "paymentMethod": null,
  "createdAt": "<serverTimestamp>"
}
```

2. `users/{uid}/rides/{rideId}` (copie pour l'historique, sans distance/durée).

Retourne l'ID de course, stocké dans `_currentRideId`.

**Cycle de vie des statuts :**
```
searching → accepted → driver_arrived → in_progress → completed
                                        (cancelled prévu mais non implémenté)
```

**Fonctions annexes non utilisées :**
- `calculDePrix(distanceKm, prixDuKm)`
- `prixMinimum(...)`
- `findNearbyDrivers(...)` via `geoflutterfire_plus` (rayon 6 km sur `drivers`)

### 4.7 Offres des chauffeurs & acceptation

Une fois la course créée, `_showOffers = true` et l'écran affiche :

1. **Un overlay de démonstration** (`demoOffers`) — affiché dès que `_showOffers` est vrai. Prix fictifs 30/20/18 FCFA, chauffeurs marocains, doublons d'ID.
2. **Un overlay réel** (au-dessus) quand `_currentRideId != null` et aucune offre acceptée :
   - `StreamBuilder` sur `rides/{rideId}/offers` trié par `timestamp` décroissant.
   - Conversion en `DriverOffer`.
   - `DriverOffersSheet` avec :
     - tri par **Meilleur prix / Meilleure note / Plus rapide**,
     - carte « RECOMMANDÉE » (première du tri),
     - avatar, note, niveau (Diamant / Or / Platine), prix, temps d'arrivée, véhicule, plaque,
     - bouton « Accepter ».
   - Si aucune offre → bandeau « Recherche de chauffeurs à proximité au Gabon… » avec spinner.

**Acceptation (`_acceptDriver`)** :
- `DriverService.acceptDriverOffer(...)` exécute un **batch** :
  - `rides/{rideId}` → `status: accepted`, `driverId`, `agreedPrice`, infos chauffeur, `acceptedAt`
  - `rides/{rideId}/offers/{driverId}` → `status: accepted`
- Puis `_listenToCurrentRide()` écoute le document de course.

**Affichage « chauffeur en route » :**
- Carte blanche en bas avec avatar, nom, véhicule + plaque, prix convenu, badge « Chauffeur en route vers vous… ».

**Fin de course :**
- Quand `status == completed` → modal non fermable :
  - « Vous êtes arrivé à destination ! »
  - « Veuillez remettre le règlement en espèces au chauffeur. »
  - montant = `agreedPrice` sinon `price` sinon 2000
  - bouton « J'ai réglé le chauffeur • Terminer » → réinitialise l'état local + SnackBar.

⚠️ Aucun paiement n'est déclenché côté passager dans ce flux : le paiement est confirmé **par le chauffeur** dans son app.

### 4.8 Historique (`userScreens/history/history.dart`)

- Vérifie l'utilisateur connecté.
- `StreamBuilder` sur `users/{uid}/rides` trié par `createdAt` décroissant.
- Loader, état vide (« Aucune course effectuée »), sinon liste de cartes :
  - prix en FCFA,
  - badge **RÉGLÉ (Espèces Cash)** ou **EN ATTENTE** selon `isPaid`,
  - adresse de départ et de destination.
- Pas de détail de course, pas d'annulation, pas de notation, pas de reçu.

### 4.9 Profil passager (`userScreens/profil/`)

**`profile_page.dart` :**
- `StreamBuilder` sur `users/{uid}`.
- Repli sur `user.phoneNumber` si `phone` absent de Firestore.
- Avatar avec badge crayon, nom complet, téléphone.
- Bouton « Modifier profil ».
- Deux cartes de stats : **RATING** et **COURSES** (`rating`, `ridesCount`).
- Bandeau orange « Passer en mode chauffeur » :
  - `DriverService.isDriverRegistered(uid)` vérifie l'existence de `car` ou `moto` dans `drivers/{uid}`.
  - Si chauffeur → `OffersPage`.
  - Sinon → `ChooseVehiclePage`.
- Trois réglages : Notifications, Sécurité, Langue.
  - ⚠️ Les callbacks sont `null` depuis `PagesManager` → **aucun effet**.
- ⚠️ Pas de bouton de déconnexion.

**`edit_profile_page.dart` :**
- Photo : caméra ou galerie (`image_picker`, qualité 80, max 800×800), suppression possible.
- Upload dans Firebase Storage : `users/{uid}/avatar_<timestamp>.jpg`.
- Écriture Firestore `users/{uid}` en `merge` : `firstName`, `lastName`, `phone`, `photoUrl`, `photoPath`, `updatedAt`.
- Suppression de l'ancienne photo Storage (non bloquant).
- Synchronisation Firebase Auth : `updateDisplayName`, `updatePhotoURL` (non bloquant).
- Validation : prénom et nom obligatoires, téléphone ≥ 8 chiffres.
- Bouton avec état de chargement.

**`user_profile.dart` :** modèle `UserProfile` (`uid`, `firstName`, `lastName`, `phone`, `photoUrl`, `photoPath`, `rating`, `ridesCount`).

**`profile_avatar.dart` :** avatar rond avec anneau orange, badge, priorité fichier local > URL réseau > placeholder.

---

## 5. Espace chauffeur

### 5.1 Accès et choix du véhicule

Depuis le profil passager → `ChooseVehiclePage` :
- Deux cartes : **Voiture** et **Moto**.
- « CONTINUER » redirige vers `Carinfos` ou `Motoinfos`.

### 5.2 Inscription voiture (`driversScreens/CarInfos.dart`)

**Champs texte obligatoires :** marque, modèle, couleur, plaque (majuscules).

**Documents et photos obligatoires (8) :**

| Clé Firestore | Libellé | Type |
|---|---|---|
| `license` | Permis de conduire | Document |
| `registration` | Carte grise | Document |
| `front` | Face | Photo véhicule |
| `left` | Profil gauche | Photo véhicule |
| `right` | Profil droit | Photo véhicule |
| `back` | Arrière | Photo véhicule |
| `interior` | Intérieur | Photo véhicule |
| `plate` | Plaque | Photo véhicule |

**Fonctionnement :**
- Chaque élément ouvre un bottom sheet : caméra / galerie / supprimer.
- Aperçu local, compteur « X à fournir » / « Complet ».
- « CONTINUER » vérifie que **tous** les champs et **tous** les fichiers sont présents.
- Upload **en parallèle** (`Future.wait`) vers :
  `drivers/{uid}/{clé}.jpg`
- Progression affichée : « ENVOI xx % ».
- Écriture Firestore `drivers/{uid}` en `merge` :
```json
{
  "car": { "brand": "...", "model": "...", "color": "...", "plate": "..." },
  "documents": {
    "license": { "url": "...", "path": "...", "status": "pending" },
    "...": { "url": "...", "path": "...", "status": "pending" }
  },
  "verificationStatus": "pending",
  "updatedAt": "<serverTimestamp>"
}
```
- Puis `DriverVerificationPage`.

### 5.3 Inscription moto (`driversScreens/MotoInfos.dart`)

Même principe, avec 7 fichiers : `license`, `registration`, `front`, `left`, `right`, `back`, `plate`.

Différences :
- Stockage : `drivers/{uid}/moto/{clé}.jpg`
- Firestore :
```json
{
  "moto": {
    "brand": "...", "model": "...", "color": "...", "plate": "...",
    "documents": { "license": { "url": "...", "path": "..." }, "...": {} }
  },
  "verificationStatus": "pending",
  "updatedAt": "..."
}
```
- ⚠️ Les documents moto sont **imbriqués dans `moto.documents`**, sans champ `status`, alors que la page de vérification lit `documents` à la racine → **la moto apparaît comme « non téléchargée »**.

### 5.4 Vérification des documents (`driversScreens/DriverDocsVerificationPage.dart`)

- `StreamBuilder` sur `drivers/{uid}`.
- Regroupe les fichiers en 4 cartes :
  - Photo du véhicule (`front`, `left`, `right`, `back`, `interior`)
  - Plaque (`plate`)
  - Carte grise (`registration`)
  - Permis (`license`)
- Statut calculé à partir du champ `status` de chaque fichier :
  - `verified` → **VÉRIFIÉ**
  - `rejected` → **REFUSÉ**
  - tout autre / absent → **EN ATTENTE**
  - fichier manquant → **NON TÉLÉCHARGÉ**
- Carte de progression : `done/total documents complétés`, pourcentage, barre, « Validation sous 24h ».
- Bouton bas « Vérification Chauffeur » → `OffersPage`.
- ⚠️ `onImport` n'est jamais fourni → les boutons « Ajouter une photo / Importer document » sont **désactivés**. Impossible de re-uploader depuis cet écran.
- ⚠️ Aucun back-office de validation n'est présent : les statuts doivent être modifiés manuellement dans Firestore.

### 5.5 Mise en ligne et réception des courses (`driversScreens/test/offers_page.dart`)

**Écran principal chauffeur :**
- Carte Google Maps centrée sur Libreville (`0.4162, 9.4673`) par défaut, puis sur la position réelle.
- Pastille **EN LIGNE / HORS LIGNE** cliquable.
- Solde du portefeuille affiché en haut à droite ; clic → `DriverWalletPage`.
- Bandeau d'alerte rouge si solde insuffisant / bloqué, avec bouton « Recharger ».
- Bottom sheet glissant (`DraggableScrollableSheet`, 25 % → 92 %).

**Passage en ligne (`_toggleOnline`) :**
1. Si on passe de hors-ligne à en ligne, lit `drivers/{uid}`.
2. `walletBalance` (défaut 5000) et `isWalletBlocked`.
3. Si bloqué ou solde < 0 → SnackBar + ouverture du sheet de recharge, **sans passer en ligne**.
4. Sinon met à jour `isAvailable` et `location` via `DriverService.updateDriverAvailability`.
5. SnackBar « Vous êtes maintenant EN LIGNE / HORS LIGNE ».

**Liste des courses :**
- Si hors ligne → écran « Vous êtes actuellement hors ligne » + bouton « Passer en ligne ».
- Si en ligne → `StreamBuilder` sur `rides` où `status == 'searching'`.
- ⚠️ **Aucun filtrage par distance** : toutes les courses en recherche remontent.
- ⚠️ Si aucune course réelle → affichage de **3 offres de démonstration** (`demoOffersGabon` : Aéroport, Mont-Bouët, Batterie IV). Ces IDs n'existent pas dans Firestore : accepter une course démo échouera.
- Carte d'offre : type (VOITURE/MOTO), prix, trajet, temps, distance, bouton « Voir & Négocier ».
- Tap → `RideDetailsPage`.

### 5.6 Détail et négociation (`ride_details_page.dart`, `negotiate_price_page.dart`)

**`RideDetailsPage` :**
- Carte de prix (prix proposé par le passager).
- Mini-carte Google (`liteModeEnabled`).
- Ligne départ/destination.
- Statistiques : prise en charge, total parcours, durée totale.
- Trois actions :
  - **Refuser** → retour
  - **Négocier** → `NegotiatePriceSheet`
  - **Accepter** → envoie une offre au prix affiché
- `_submitOffer(price)` :
  - lit `drivers/{uid}` pour récupérer `car.brand`, `car.model`, `car.plate`
  - `DriverService.sendDriverOffer(...)` écrit `rides/{rideId}/offers/{driverId}` :
```json
{
  "driverId": "...",
  "driverName": "<displayName ou 'Chauffeur Moovi'>",
  "rating": 4.8,
  "level": "Or",
  "car": "Toyota Corolla",
  "plate": "1234-GA-01",
  "price": 2500,
  "arrivalMinutes": 5,
  "photoUrl": "...",
  "status": "pending",
  "timestamp": "<serverTimestamp>"
}
```
  - Affiche « Proposition envoyée au client… En attente de validation… ».
- Écoute `rides/{rideId}` : si `status == accepted` et `driverId == uid` → navigation automatique vers `ActiveRidePage` avec `agreedPrice`.

**`NegotiatePriceSheet` :**
- Affiche l'offre client et l'estimation Moovi.
- Champ numérique éditable.
- Boutons rapides **+500 / +1 000 / +2 000 FCFA**.
- « Envoyer la contre-proposition » → retourne le prix au `RideDetailsPage`.

⚠️ Pour un chauffeur **moto**, `RideDetailsPage` lit uniquement `driverData['car']` → véhicule « Véhicule » et plaque vide.

### 5.7 Course active (`driversScreens/test/active_ride_page.dart`)

**Machine à états locale :**

| Étape | Statut Firestore écrit | Bouton |
|---|---|---|
| `goingToClient` | `driver_arrived` | « Je suis arrivé au point de départ » |
| `arrivedAtClient` | `in_progress` | « Client à bord - Démarrer la course » |
| `inProgress` | `completed` | « Terminer la course » |
| `completed` | — | « Confirmer encaissement Espèces » puis « Retour à l'accueil » |

- Carte avec marqueurs départ/destination et **simple ligne droite** (pas d'itinéraire routier réel).
- Badge de statut, estimation temps/distance.
- Carte passager : avatar, trajet, prix, badge RÉGLÉ / À PAYER.
- Boutons « Appeler » et « Message » → **SnackBar uniquement** (pas d'appel ni de chat réels).
- À `completed`, ouverture d'un bottom sheet de règlement cash :
  - montant à percevoir,
  - commission 15 %,
  - bouton « Confirmer l'encaissement en Espèces » :
    1. `markRideAsPaid(paymentMethod: 'cash', amount, provider: 'cash')`
    2. `deductRideCommission(driverId, rideId, ridePrice, 0.15)`
    3. SnackBar de confirmation.
- Écoute `rides/{rideId}` pour détecter `isPaid == true`.

### 5.8 Portefeuille chauffeur (`driversScreens/wallet/driver_wallet_page.dart`)

- `StreamBuilder` sur `drivers/{uid}`.
- Solde (`walletBalance`, défaut 5000) et état :
  - **COMPTE ACTIF** (vert) si solde ≥ 0 et non bloqué
  - **SOLDE INSUFFISANT** (rouge) sinon
- Carte dégradée noire ou rouge.
- Texte explicatif : les passagers paient 100 % en cash, la commission Moovi de **15 %** est prélevée du portefeuille ; solde < 0 → compte hors ligne jusqu'à recharge.
- Bouton « Recharger mon compte » → `RechargeWalletSheet`.
- Historique temps réel `drivers/{uid}/wallet_transactions` trié par date :
  - dépôt → montant vert `+X FCFA`
  - commission → montant rouge
  - description, date formatée.
- État vide dédié.

### 5.9 Rechargement Mobile Money PawaPay (`driversScreens/wallet/recharge_wallet_sheet.dart`)

**Formulaire :**
1. Détection du pays à partir du numéro Firebase Auth (ou Gabon par défaut).
2. Sélecteur de **16 pays** : Togo, Gabon, Cameroun, Côte d'Ivoire, Sénégal, Bénin, RD Congo, Congo-Brazzaville, Ghana, Kenya, Rwanda, Ouganda, Zambie, Tanzanie, Mozambique, Malawi.
3. Montants suggérés selon le pays et la devise (XOF, XAF, CDF, GHS, KES, RWF, UGX, ZMW, TZS, MZN, MWK).
4. Montant libre possible.
5. Sélection de l'opérateur Mobile Money du pays (Airtel, Moov, MTN, Orange, Wave, M-Pesa, etc.).
6. Numéro Mobile Money avec indicatif.
7. En mode non-production : numéro de test PawaPay pré-rempli pour simuler un succès.

**Traitement :**
1. `PawaPayService.initiateDeposit(...)` → `POST /deposits` avec :
   - `depositId` UUID v4,
   - `amount`, `currency`, `country`, `correspondent`,
   - `payer` MSISDN,
   - `customerTimestamp`, `statementDescription`.
2. Si aucun token → **mode simulation** (1,5 s puis `SUBMITTED`).
3. Affichage « Confirmation sur votre mobile » + polling.
4. `pollDepositStatus` interroge `GET /deposits/{id}` toutes les 4 s (30 tentatives max).
5. Si `COMPLETED` → `DriverService.rechargeDriverWallet(...)` :
   - transaction `wallet_transactions/{depositId}` (`type: deposit`, montant, opérateur, téléphone, gateway `pawapay`, statut `completed`)
   - `walletBalance += amount`
   - `isWalletBlocked = false`
   - `isAvailable = true`
   - `lastRechargeAt`, `updatedAt`
6. Écran de succès puis fermeture.
7. Si échec/refus → message d'erreur.

**`PawaPayService` (`lib/services/pawapay_service.dart`) :**
- Registre pays/opérateurs/devises.
- Détection pays depuis un numéro international.
- Normalisation MSISDN.
- Génération UUID v4.
- `initiateDeposit`, `checkDepositStatus`, `pollDepositStatus`.
- URLs sandbox/production.
- ⚠️ **Aucun webhook serveur** : le crédit du portefeuille est décidé côté client après polling. Un client modifié pourrait se créditer sans paiement réel.

---

## 6. Services transverses

### 6.1 `DriverService` (`lib/services/driver_service.dart`)

| Méthode | Rôle |
|---|---|
| `isDriverRegistered(uid)` | Vérifie `car` ou `moto` dans `drivers/{uid}` |
| `getDriverData(uid)` | Lit le document chauffeur |
| `updateDriverAvailability(...)` | Met à jour `isAvailable`, `location`, `updatedAt` |
| `getAvailableRidesStream()` | Stream `rides` où `status == 'searching'` |
| `streamRide(rideId)` | Stream d'une course |
| `streamRideOffers(rideId)` | Stream `rides/{rideId}/offers` trié |
| `sendDriverOffer(...)` | Écrit/met à jour l'offre du chauffeur |
| `acceptDriverOffer(...)` | Batch : course `accepted` + offre `accepted` |
| `updateRideStatus(...)` | Écrit `status` et `<status>At` |
| `markRideAsPaid(...)` | Batch : course payée + historique client + stats chauffeur (`ridesCount`, `totalRevenue`) |
| `streamDriverWallet(driverId)` | Stream du doc chauffeur (solde) |
| `streamWalletTransactions(driverId)` | Stream des transactions |
| `rechargeDriverWallet(...)` | Crédit + transaction + déblocage |
| `deductRideCommission(...)` | Déduit 15 %, bloque si négatif, note la commission sur la course |

### 6.2 `functions.dart`

- `addRide(...)` (utilisé).
- `calculDePrix`, `prixMinimum` (non utilisés).
- `findNearbyDrivers(...)` via GeoFire (non utilisé).

### 6.3 `dataService.dart`

- `ImportDriversService.importDrivers()` : lit `assets/data/moovi_chauffeurs_gabon_50.json` et écrit 50 chauffeurs dans `test_drivers` (`isTest: true`, `location` GeoPoint). **Bouton d'import commenté**.
- `DriverService.getDrivers()` (classe homonyme, non utilisée) : stream `test_drivers` disponibles.

### 6.4 `LocationService` (`lib/services/Location.dart`)

- `requestPermission()` et `getCurrentLocation()`.
- **Non utilisé** : `MapPage` appelle directement `Geolocator`.

### 6.5 Paiement PayCentral (`lib/services/paycentral_service.dart` + `lib/widgets/paycentral_payment_sheet.dart`)

- Service complet : initiation `POST /payment/initiate`, vérification `GET /payment/{id}/status`, polling.
- Sheet de paiement : **Airtel Money**, **Moov Money**, **Espèces**.
- Normalisation des numéros gabonais `+241`, détection Airtel (`07`) / Moov (`06`).
- Sur succès → `markRideAsPaid(paymentMethod: 'paycentral', transactionId, provider)`.
- ⚠️ **Aucun écran n'importe ni n'ouvre `showPayCentralPaymentSheet`** : fonctionnalité **totalement non branchée**. Le passager ne peut donc pas payer par Mobile Money dans le flux actuel.

### 6.6 Autres écrans non branchés

| Fichier | Contenu | Statut |
|---|---|---|
| `driversScreens/test/document_status_page.dart` | Page « Mes documents » avec résumé, filtres, aperçu plein écran | **Non importée** ; lit en plus `drivers/{uid}/documents` (sous-collection) alors que l'inscription écrit un **champ map** `documents` → incompatible |
| `driversScreens/test/driver_profile_page.dart` | Profil chauffeur (nom, véhicule, note, menu, déconnexion) | **Non importée** ; boutons sans action, déconnexion vide |
| `lib/widgets/paycentral_payment_sheet.dart` | Paiement Mobile Money passager | **Non branché** |
| `lib/services/Location.dart` | Service GPS | **Non utilisé** |
| `lib/functions.dart` (helpers prix, GeoFire) | Calculs et recherche à proximité | **Non utilisés** |
| `AuthService.register/login/logout` | Auth email + déconnexion | **Non utilisés** |

---

## 7. Modèle de données Firestore

### `users/{uid}`
```json
{
  "uid": "...",
  "fullname": "...",          // écrit par register() (non utilisé)
  "phoneNumber": "+241...",
  "name": "",                 // créé par createOrGetUser
  "email": "",
  "firstName": "...",         // écrit par l'édition de profil
  "lastName": "...",
  "phone": "...",
  "photoUrl": "https://...",
  "photoPath": "users/{uid}/avatar_....jpg",
  "rating": 0,
  "ridesCount": 0,
  "createdAt": "<serverTimestamp>",
  "updatedAt": "<serverTimestamp>"
}
```

### `users/{uid}/rides/{rideId}`
Copie de la course pour l'historique :
```json
{
  "rideId": "...",
  "departure": "GeoPoint",
  "destination": "GeoPoint",
  "departureAddress": "...",
  "destinationAddress": "...",
  "rideType": "voiture|confort|moto",
  "price": 2000,
  "currency": "XAF",
  "status": "searching|accepted|driver_arrived|in_progress|completed",
  "createdAt": "...",
  "isPaid": true,
  "paymentMethod": "cash|paycentral",
  "paymentTransactionId": "...",
  "paymentProvider": "...",
  "paidAmount": 2000,
  "paidAt": "..."
}
```

### `rides/{rideId}`
```json
{
  "clientId": "...",
  "departure": "GeoPoint",
  "destination": "GeoPoint",
  "departureAddress": "...",
  "destinationAddress": "...",
  "rideType": "voiture|confort|moto",
  "price": 2000,
  "currency": "XAF",
  "distance": "8.5 km",
  "duration": "12 min",
  "status": "searching|accepted|driver_arrived|in_progress|completed",
  "driverId": null,
  "isPaid": false,
  "paymentMethod": null,
  "createdAt": "...",
  "agreedPrice": 2500,
  "driverName": "...",
  "driverCar": "...",
  "driverPlate": "...",
  "driverPhotoUrl": "...",
  "acceptedAt": "...",
  "paymentTransactionId": "...",
  "paymentProvider": "...",
  "paidAmount": 2500,
  "paidAt": "...",
  "platformCommission": 375,
  "commissionRate": 0.15,
  "commissionDeducted": true
}
```

### `rides/{rideId}/offers/{driverId}`
```json
{
  "driverId": "...",
  "driverName": "...",
  "rating": 4.8,
  "level": "Or|Diamant|Platine",
  "car": "Toyota Corolla",
  "plate": "1234-GA-01",
  "price": 2500,
  "arrivalMinutes": 5,
  "photoUrl": "...",
  "status": "pending|accepted",
  "timestamp": "<serverTimestamp>"
}
```

### `drivers/{uid}`
```json
{
  "car": { "brand": "...", "model": "...", "color": "...", "plate": "..." },
  "moto": { "brand": "...", "model": "...", "color": "...", "plate": "...", "documents": {} },
  "documents": {
    "license":      { "url": "...", "path": "...", "status": "pending|verified|rejected" },
    "registration": { "url": "...", "path": "...", "status": "pending" },
    "front":        { "url": "...", "path": "...", "status": "pending" },
    "left":         { "url": "...", "path": "...", "status": "pending" },
    "right":        { "url": "...", "path": "...", "status": "pending" },
    "back":         { "url": "...", "path": "...", "status": "pending" },
    "interior":     { "url": "...", "path": "...", "status": "pending" },
    "plate":        { "url": "...", "path": "...", "status": "pending" }
  },
  "verificationStatus": "pending|approved|rejected",
  "isAvailable": true,
  "location": "GeoPoint",
  "walletBalance": 5000,
  "isWalletBlocked": false,
  "ridesCount": 0,
  "totalRevenue": 0,
  "lastRechargeAt": "...",
  "updatedAt": "..."
}
```

### `drivers/{uid}/wallet_transactions/{transactionId}`
```json
{
  "id": "...",
  "type": "deposit|commission",
  "amount": 10000,            // négatif pour une commission
  "operatorCode": "AIRTEL_GAB",
  "operatorName": "Airtel Money Gabon (🇬🇦 Gabon)",
  "phoneNumber": "...",
  "gateway": "pawapay",
  "status": "completed",
  "description": "Rechargement Mobile Money (...) | Commission Moovi (15%) - Course Cash",
  "rideId": "...",            // commissions uniquement
  "ridePrice": 2500,
  "commissionRate": 0.15,
  "createdAt": "..."
}
```

### `test_drivers/{driverId}`
```json
{
  "driverId": "driver_001",
  "city": "Libreville",
  "latitude": 0.410525,
  "longitude": 9.391851,
  "isAvailable": true,
  "location": "GeoPoint",
  "isTest": true
}
```

---

## 8. Comment fonctionnent les parcours de bout en bout

### 8.1 Parcours passager

```
Lancement
  → AuthWrapper
  → non connecté : SignOrLogin (téléphone)
  → sendOTP (Firebase)
  → Otpverification (6 chiffres)
  → verifyOTP + createOrGetUser
  → Pagesmanager (onglet Carte)

Carte
  → GPS + position courante = départ « Ma position »
  → saisie destination (Google Places, pays GA)
  → sélection suggestion → coordonnées
  → Google Routes → tracé + distance + durée
  → après 1,5 s : RideSelectionSheet
  → choix Voiture / Comfort / Moto + prix (pas de 250 FCFA)
  → « TROUVER UN CHAUFFEUR »
  → addRide : rides/{id} + users/{uid}/rides/{id} (status searching)
  → écoute rides/{id}/offers
  → offres chauffeurs triées (prix / note / rapidité)
  → « Accepter » → course accepted + offre accepted
  → carte « chauffeur en route »
  → écoute status
  → completed → modal « payez en espèces »
  → « J'ai réglé » → nettoyage local
```

### 8.2 Parcours chauffeur

```
Profil passager
  → « Passer en mode chauffeur »
  → isDriverRegistered ?
      non → ChooseVehiclePage
             → Voiture : Carinfos (4 champs + 8 fichiers)
             → Moto    : Motoinfos (4 champs + 7 fichiers)
             → upload Storage + Firestore drivers/{uid}
             → DriverVerificationPage
             → « Vérification Chauffeur » → OffersPage
      oui → OffersPage

OffersPage
  → GPS (Libreville par défaut)
  → passage EN LIGNE
      → vérifie walletBalance / isWalletBlocked
      → bloqué : recharge obligatoire
      → sinon drivers/{uid}.isAvailable = true + location
  → stream rides status = searching
  → sélection d'une course → RideDetailsPage

RideDetailsPage
  → Accepter (prix passager) ou Négocier (contre-proposition)
  → sendDriverOffer → rides/{rideId}/offers/{driverId}
  → attente validation client
  → si accepted + driverId == uid → ActiveRidePage

ActiveRidePage
  → « arrivé »      → status driver_arrived
  → « client à bord » → status in_progress
  → « terminer »    → status completed
  → sheet cash : montant + commission 15 %
  → « Confirmer l'encaissement »
      → markRideAsPaid(cash)
      → deductRideCommission(15 %)
      → walletBalance -= commission
      → si négatif : isWalletBlocked = true, isAvailable = false
```

### 8.3 Parcours portefeuille

```
DriverWalletPage
  → stream drivers/{uid} (solde, blocage)
  → stream wallet_transactions
  → « Recharger »
  → RechargeWalletSheet
      → pays + opérateur + montant + numéro
      → POST PawaPay /deposits
      → polling GET /deposits/{id}
      → COMPLETED
      → rechargeDriverWallet :
          + transaction deposit
          + walletBalance += montant
          + isWalletBlocked = false
          + isAvailable = true
```

---

## 9. UI, thème et composants

### 9.1 Couleurs (`lib/theme/app_colors.dart`)

| Nom | Valeur | Usage |
|---|---|---|
| `primary` | `#FF6B00` | Orange Moovi |
| `primaryDark` | `#8C4A00` | Bordure de trajet |
| `darkBrown` | `#452800` | Textes |
| `background` | `#111111` | Titres |
| `darkBlue` | `#0E1824` | Cartes d'offres |
| `cream` | `#FFE4C9` | Fonds doux |
| `grey` | `#6E6E6E` | Textes secondaires |
| `error` / `success` | `#FF4444` / `#4CAF50` | États |

### 9.2 Thème (`app_theme.dart`)

- Material 3, fond blanc, boutons `ElevatedButton` orange arrondis 16 px.
- `InputDecorationTheme` avec fond orange (!) et label blanc — potentiellement problématique sur certains formulaires.
- `CardTheme` arrondi 25 px.
- `BottomNavigationBarTheme` (non utilisée, la navbar est custom).

### 9.3 Composants réutilisables

| Fichier | Rôle |
|---|---|
| `widgets/cButton.dart` | Bouton orange avec animation d'échelle à l'appui |
| `widgets/cTextfield.dart` | Champ texte (non utilisé ?) |
| `widgets/UserbottomNavBar.dart` | Navbar flottante 3 onglets |
| `widgets/animations/fadeSlideIn.dart` | Animation d'apparition (login) |
| `userScreens/widgets/driverOffersSheet.dart` | Bottom sheet des offres + tri + cartes |
| `userScreens/widgets/rideSheetColors.dart` | Sheet de sélection véhicule/prix |
| `driversScreens/test/driver_theme.dart` | Palette et composants de l'espace chauffeur (`MooviColors`, `OnlineChip`, `OrangeButton`, `RouteLine`, `IdTag`) |

---

## 10. Fonctionnalités partiellement implémentées / TODO

| Fonctionnalité | État réel |
|---|---|
| Recherche de chauffeur (`searchDriver`) | **Stub** : uniquement des `debugPrint`, aucun algorithme |
| Renvoi d'OTP | **Faux renvoi** : vide les cases + SnackBar, pas de SMS |
| Paiement Mobile Money passager | Service + sheet **prêts mais non branchés** |
| Paiement de la course | **Cash uniquement**, confirmé par le chauffeur |
| Déconnexion | Méthode existe, **aucun bouton** |
| Notifications / Sécurité / Langue | Tuiles **sans action** |
| Appel / message chauffeur | **SnackBar** seulement |
| Annulation de course | Statut `cancelled` prévu mais **aucun flux** |
| Notation / avis | **Absent** (rating figé à 0 ou 4.8) |
| Back-office validation documents | **Absent** (statuts à modifier à la main) |
| Import des chauffeurs de test | Service prêt, **bouton commenté** |
| Style de carte personnalisé | Fichier chargé, **non appliqué** |
| Dernières destinations | UI **commentée** |
| Bouton recentrer | **Commenté** |
| Profil chauffeur dédié | Écran **non branché** |
| Page statut documents | Écran **non branché** + schéma incompatible |
| Filtrage des courses par proximité | **Absent** |
| Mise à jour continue de la position chauffeur | **Absente** (uniquement au passage en ligne) |
| Suivi temps réel du chauffeur sur la carte passager | **Absent** (pas de marqueur mobile du chauffeur accepté) |
| Itinéraire réel dans `ActiveRidePage` | Ligne droite, pas de Google Routes |
| Tests automatisés | **Aucun** (`test/` absent) |
| Règles de sécurité Firestore/Storage | **Absentes du dépôt** |

---

## 11. Bugs et incohérences identifiés

### 11.1 Bugs fonctionnels

1. **Double bottom sheet d'offres** : `MapPage` affiche `DriverOffersSheet(offers: demoOffers)` dès `_showOffers == true`, **puis** l'overlay réel par-dessus. Les fausses offres restent visibles/actives en dessous.
2. **Offres de démo non fonctionnelles** : accepter une offre `demoOffers` (IDs `'1'`, `'2'`, `'3'`) tente de mettre à jour une offre inexistante → le batch `acceptDriverOffer` échoue.
3. **Courses de démo chauffeur non fonctionnelles** : `demoOffersGabon` (`GA-401`, etc.) n'existe pas dans `rides` → acceptation impossible.
4. **Chauffeurs réels invisibles côté passager** : la carte écoute `test_drivers`, alors que les vrais chauffeurs sont écrits dans `drivers`.
5. **Documents moto non reconnus** : écrits dans `moto.documents`, lus dans `documents` racine.
6. **Chauffeur moto mal affiché** : `RideDetailsPage` ne lit que `car`.
7. **Vérification OTP non contrôlée** : navigation vers l'app même si `verifyOTP` retourne `false`.
8. **Profil vide après OTP** : `createOrGetUser` crée `name: ''` mais l'UI lit `firstName`/`lastName` → « Utilisateur ».
9. **Pays incohérents** : téléphone initialisé sur **MA (Maroc)** alors que la carte, les prix et les données ciblent le **Gabon** ; un fichier de chauffeurs Rabat/Salé existe mais n'est pas importé.
10. **Style de carte ignoré** : `mapStyle` chargé mais jamais passé à `GoogleMap`.
11. **`distanceText`/`durationText` inutilisés** dans le sheet de sélection → pas d'affichage distance/durée avant confirmation.
12. **Pas de mise à jour de position chauffeur** après le passage en ligne → les futures recherches de proximité seraient obsolètes.
13. **Rechargement en production avec token sandbox** : `production: true` + token sandbox en dur → risque d'appels réels avec des identifiants de test (ou l'inverse).
14. **Double définition `DriverService`** : `services/driver_service.dart` et `userScreens/dataService.dart` ; `mapPage.dart` doit faire `hide DriverService`.
15. **`_showOffers` reste vrai** après acceptation (l'overlay démo est masqué par l'overlay réel, mais l'état n'est pas nettoyé).
16. **Aucune gestion d'annulation** si l'utilisateur quitte le sheet ou change de destination pendant la recherche.
17. **Pas de timeout** côté passager si aucun chauffeur ne répond.
18. **Commission prélevée même si `markRideAsPaid` échoue partiellement** (deux appels séparés, pas de transaction commune).
19. **`deductRideCommission`** utilise un solde par défaut de 5000 si le champ est absent, ce qui peut masquer un problème de données.
20. **`DriverVerificationPage`** : boutons d'import désactivés car `onImport` toujours `null`.

### 11.2 Incohérences de schéma

- `users` : `fullname` (register) vs `firstName`/`lastName` (profil) vs `name` (createOrGetUser).
- `drivers.documents` : **champ map** (CarInfos) vs **sous-collection** (document_status_page).
- Documents moto : `status` absent, chemin `moto.documents` différent.
- `verificationStatus` écrit mais **jamais lu** pour bloquer l'accès aux courses (seul `isDriverRegistered` compte).
- `rides.distance`/`duration` : texte, pas de valeurs numériques exploitables pour un calcul de prix.

---

## 12. Sécurité et configuration

### 12.1 Clés et secrets en dur

| Emplacement | Secret |
|---|---|
| `lib/userScreens/mapPage.dart` | Clé Google Places `AIzaSyBs6...` |
| `lib/services/itinéraire/DirectionsService.dart` | Clé Google Routes `AIzaSyBs6...` |
| `android/app/src/main/AndroidManifest.xml` | Clé Google Maps `AIzaSyBs6...` |
| `lib/main.dart` | Token PawaPay sandbox complet |
| `lib/services/paycentral_service.dart` | Clé API PayCentral sandbox `sk_sandbox_...` |
| `maps.txt` | Autre clé Google `AIzaSyDY8...` |
| `lib/firebase_options.dart` | Clés Firebase Android/iOS (normal, mais à restreindre) |

**Recommandations :**
- Restreindre les clés Google par package Android / bundle iOS et par API.
- Déplacer les secrets PawaPay/PayCentral côté serveur (Cloud Functions) et ne jamais embarquer un token de paiement dans l'app.
- Activer **Firebase App Check**.
- Utiliser `--dart-define` pour les clés (déjà prévu pour `PAWAPAY_TOKEN` mais une valeur par défaut est présente).

### 12.2 Risques fonctionnels de sécurité

- **Crédit du portefeuille côté client** après polling PawaPay : contournable.
- **Commission calculée côté client** : un client modifié peut ne pas la déduire.
- **Prix de course fixé par le passager** sans validation serveur.
- **Statuts de course modifiables** par le chauffeur sans contrôle.
- **Aucune règle Firestore** dans le dépôt : si les règles par défaut sont ouvertes, tout utilisateur peut lire/écrire les courses, portefeuilles et documents.
- **OTP** : pas de vérification du résultat avant navigation.
- **Documents sensibles** (permis, carte grise) stockés dans Storage : nécessitent des règles strictes et des URLs signées.

### 12.3 Permissions plateformes

- Android : `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`.
- iOS : `NSLocationWhenInUseUsageDescription` présent.
- ⚠️ **iOS** : pas de `NSCameraUsageDescription` ni `NSPhotoLibraryUsageDescription` → `image_picker` risque de **crasher** à l'usage.
- ⚠️ Android : pas de permission `CAMERA` déclarée (l'intent caméra peut fonctionner sans, mais à vérifier selon les versions).

---

## 13. Synthèse par domaine

| Domaine | Niveau d'implémentation |
|---|---|
| Authentification téléphone + OTP | ✅ Fonctionnel (renvoi OTP factice, contrôle du code manquant) |
| Auth email | 🟡 Code présent, non branché |
| Carte & GPS | ✅ Fonctionnel |
| Recherche de lieux | ✅ Fonctionnel (Google Places legacy) |
| Itinéraire | ✅ Fonctionnel (Google Routes v2) |
| Sélection véhicule & prix | ✅ Fonctionnel (prix libre, pas de calcul distance) |
| Création de course | ✅ Fonctionnel (Firestore) |
| Offres chauffeur → passager | ✅ Fonctionnel (temps réel) |
| Acceptation & suivi | ✅ Fonctionnel (statuts Firestore) |
| Paiement passager | 🔴 Cash uniquement ; PayCentral non branché |
| Historique | ✅ Fonctionnel (lecture seule) |
| Profil passager | ✅ Fonctionnel (photo, édition, stats) |
| Inscription chauffeur | ✅ Fonctionnel (voiture + moto) |
| Upload documents | ✅ Fonctionnel (Storage) |
| Validation documents | 🟡 Affichage seulement, back-office absent |
| Mode en ligne / courses | ✅ Fonctionnel (sans filtrage distance) |
| Négociation | ✅ Fonctionnel |
| Course active | ✅ Fonctionnel (statuts, cash, commission) |
| Portefeuille | ✅ Fonctionnel |
| Recharge PawaPay | ✅ Fonctionnel (16 pays, polling) |
| Notifications / chat / appel | 🔴 Non implémenté (placeholders) |
| Déconnexion | 🔴 Non branchée |
| Paramètres (langue, sécurité) | 🔴 Non implémentés |
| Tests | 🔴 Aucun |
| Règles de sécurité | 🔴 Absentes du dépôt |

---

## 14. Conclusion

Moovi est une **base solide de prototype VTC** : le cœur du parcours (recherche de destination → itinéraire → choix du véhicule → création de course → offres chauffeurs → acceptation → suivi → encaissement cash) est réellement codé et connecté à Firebase. L'espace chauffeur va plus loin avec l'inscription véhicule, l'upload de documents, la négociation, la machine à états de course et un portefeuille Mobile Money PawaPay.

Pour passer en production, les priorités sont :
1. **Brancher ou supprimer** les écrans/services morts (PayCentral, document status, driver profile).
2. **Sécuriser** les paiements et commissions côté serveur (Cloud Functions + webhooks PawaPay).
3. **Corriger les incohérences de données** (chauffeurs `drivers` vs `test_drivers`, documents moto, profils).
4. **Ajouter les règles Firestore/Storage** et App Check.
5. **Finaliser** la recherche de chauffeur réelle (proximité, position continue, timeout, annulation).
6. **Compléter l'UX** : déconnexion, notifications, chat/appel, notation, annulation.
7. **Nettoyer les secrets** et restreindre les clés API.
