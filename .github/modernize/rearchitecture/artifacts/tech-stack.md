# Existing technology stack

## Language, runtimes, and build

- Flutter/Dart application; `pubspec.yaml` declares Dart `>=3.0.0 <4.0.0`. Flutter SDK version is not pinned in the manifest.
- Android Gradle Kotlin DSL; application module targets Java 17 and Kotlin JVM target 17; Android Gradle Plugin `8.11.1`, Kotlin Gradle plugin `2.2.20`. Gradle wrapper version is defined in `android/gradle/wrapper/gradle-wrapper.properties`.
- iOS Flutter runner with platform plugin registration and CocoaPods-managed Flutter plugins.
- Flask/Python API; `requirements.txt` uses minimum-version constraints, not exact pins. Requirements include Flask `>=3.1.0`, Flask-SQLAlchemy `>=3.1.1`, Flask-JWT-Extended `>=4.6.0`, Flask-SocketIO `>=5.3.6`, SQLAlchemy `>=2.0.36`, PyMySQL `>=1.1.1`, requests `>=2.32.0`, and pytest `>=8.3.0`.

## Flutter dependencies (direct manifest constraints)

- Flutter SDK, `http ^1.6.0`, `geolocator ^14.0.0`, `google_maps_flutter ^2.17.1`, `google_places_flutter ^2.1.1`, `flutter_polyline_points ^3.1.0`, `geoflutterfire_plus ^0.0.34`, `flutter_intl_phone_field ^0.0.7`, `image_picker ^1.2.4`, `google_fonts ^6.1.0`, `iconsax ^0.0.8`, `dotted_line ^3.3.0`.
- Firebase runtime plugins: `firebase_core ^4.0.0`, `firebase_auth ^6.0.0`, `cloud_firestore ^6.0.0`, `firebase_storage ^13.6.0`.
- Dev dependencies: Flutter test SDK and `flutter_lints ^3.0.0`; launcher icon tool is listed as a direct dependency/manifest configuration.
- No secure token-storage or Socket.IO client dependency is currently declared. No Firebase Messaging dependency was found.

## Current integration behavior and blockers

- Auth/profile/ride/driver/document/wallet paths use Firebase Auth, Firestore, and Storage from `lib/`; Firebase initialization lives in `main.dart`.
- PawaPay and PayCentral service code make direct mobile HTTP requests and embed provider credentials/defaults. Google Places autocomplete/details and Routes v2 are called directly from the client with an embedded Maps key. These provider calls are incompatible with the server-only credential boundary.
- `google_maps_flutter` renders the map and Geolocator obtains device location; these are client presentation/device capabilities. The map renderer needs its native platform SDK configuration even after place lookup and route computation move to the API.
- The target API already wraps maps, OTP/WAHA, PawaPay and PayCentral and supports JWT-secured Socket.IO. Its `.env.example` contains server-side settings for these integrations; actual secrets are intentionally not reproduced here.
- API database is SQLAlchemy over MySQL (`moovi_bd` documented); test configuration defaults to SQLite in-memory. API config defines access JWT expiry (24 h default), refresh JWT expiry (30 days default), upload size/paths, rate limits, and provider simulation.
- Android source applies Firebase Google Services Gradle plugin and includes `google-services.json`; iOS generated plugin registration includes Firebase plugins. Generated/build caches are not authoritative source.

## Runtime configuration observed

- API `APP_ENV`, secrets, MySQL/DATABASE_URL, upload, OTP, WAHA, maps, PawaPay, PayCentral, CORS, pricing/radius and background task settings are loaded by `../api/app/configs/config.py`.
- Flutter has no API base-URL setting. Android Maps uses a Gradle property/manifest placeholder. Flutter Maps Places/Routes and PawaPay/PayCentral code also has in-source configuration. No secure persistent JWT/session configuration exists yet.
- Required migration runtime configuration is an external, overridable API base URL (emulator host loopback alias vs. device-reachable address; HTTPS in production). Keep backend secrets only in API-local environment and do not infer/share values from `.env`.
