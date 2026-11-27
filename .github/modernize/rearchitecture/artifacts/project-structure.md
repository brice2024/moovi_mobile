# Project structure

## Project classification

Combined product scope is a client/server full-stack mobile application: a Flutter Android/iOS client in `moovi_mobile-master/moovi_mobile-master` and a sibling Flask API in `api`. The folders are not a single package/build; the API is the server runtime and the Flutter project is the mobile client.

## Modules and layers

### Flutter client (`lib/`, 45 Dart files)

- App/bootstrap: `main.dart`, `auth_wrapper.dart`, `firebase_options.dart`.
- Auth UI/service: `authScreens/` (2 files), `services/Auth.dart`.
- Passenger features: `userScreens/` (12 files) — map/booking, place search, history, profile/edit.
- Driver features: `driversScreens/` (14 files) — vehicle registration, document verification, offers, ride lifecycle, profile, wallet.
- Integration/service: `services/` (6 files) — driver service, directions, geolocation, PawaPay, PayCentral.
- Shared UI: `widgets/` (5 files), `theme/` (2 files), plus root `functions.dart`.
- Assets include images, maps styling, fonts, and bundled driver demo JSON. Build output and `.dart_tool` are generated and excluded from source anchors.

### Flask API (`../api/app/`, 43 Python files)

- HTTP entry point/application factory: `../api/app.py`, `../api/app/__init__.py`.
- REST blueprints: `app/views/` — health, auth, users, drivers, rides, payments, wallet, maps, chat, notifications, admin, and files.
- Persistence: `app/models/` SQLAlchemy entities.
- Service/integration layer: `app/tools/` — JWT helpers, geo/pricing, benefits, storage, OTP/WAHA, Google Maps, payment providers, realtime and background jobs.
- Runtime configuration: `app/configs/config.py`, loaded from API-local `.env`.
- API tests: `../api/tests/`; root commands are documented in `../api/README.md`.

## Entry points and navigation

- Flutter `main()` in `lib/main.dart` currently initializes Firebase, configures the direct PawaPay client, then starts `MyApp`.
- `MyApp` selects `AuthWrapper`; the wrapper listens to Firebase Auth state and chooses the phone sign-in screen or passenger tab shell.
- `Pagesmanager` presents Map, History, and Profile tabs; driver flows are pushed through passenger profile/vehicle choice and Offers → Ride Details → Active Ride. Wallet and document/status pages are also pushed.
- API `create_app()` registers the blueprints; `../api/app.py` runs Flask-SocketIO. REST prefix is `/api`; realtime handlers are registered in `app/views/realtime.py`.
- Socket.IO authenticates the access JWT from `auth.token`, query token, or Bearer header and re-joins user/active-ride rooms.

## Functional areas / externally triggerable units

The graph has 14 Flutter units: auth/session, passenger tabs, passenger booking, passenger history, passenger profile, profile editing, driver onboarding, driver documents, driver offers, driver ride details, driver active ride, driver profile, driver wallet, and passenger payment sheet. The sheet is source-defined but no invocation was found. The API also contains admin, notification, and health surfaces; current Flutter has no admin/notification screens or push-token registration flow.

## Key configuration files

- `pubspec.yaml` / `pubspec.lock`: Flutter dependencies and Dart SDK constraint.
- `android/app/build.gradle.kts` and `android/settings.gradle.kts`: Android/Flutter plugins, Java/Kotlin settings and Google Maps manifest placeholder; Firebase Google Services plugin is applied.
- `android/app/google-services.json`, `lib/firebase_options.dart`, `firebase.json`, and iOS generated plugin registration: Firebase runtime/platform configuration. Do not remove until the migration and builds are verified.
- `ios/Runner/Info.plist`: location permission rationale and app metadata.
- `../api/.env.example`: server-side API/database/OTP/WAHA/maps/payment configuration keys (key values remain local).
- `../api/app/configs/config.py`: API runtime env parsing, JWT expiration, DB, upload, OTP, provider simulation, maps and business-rule settings.
