# t3 — Mobile Feature and API Capability Inventory

**Role:** PM  
**Phase:** Analysis  
**Date:** 2026-11-25  
**Scope:** Existing Flutter user journeys, Firebase references/platform setup, direct provider requests, and all registered Flask API capabilities. This is an evidence inventory, not a claim that the routes have been runtime-verified.

## Summary

- The active Flutter client still uses Firebase for authentication, profile/ride/driver/wallet data, and file storage. A source search found Firebase references in 22 Dart files and four direct Firebase packages in `pubspec.yaml`.
- No Flutter call to the Flask API was found. Existing HTTP calls are direct Google Places/Routes, PawaPay, or PayCentral requests.
- The Flask API already exposes routes for the active product areas: phone OTP/JWT, users and avatars, rides/offers/lifecycle, driver profiles/documents/availability, wallet/PawaPay, PayCentral, maps, chat, notifications, and files. Socket.IO supports ride/driver/user realtime operations.
- No missing backend capability is evident for the active core journey from the route inventory. The implementation must still verify request/response semantics and runtime behavior; endpoint names alone do not prove feature parity.
- Several current UI behaviors are fake, inert, or unreachable rather than API gaps (notably demo offers, resend OTP, chat/call placeholders, settings, and disconnected payment/document/profile pages). These are itemized below so they are not silently represented as successful migrated functionality.
- The reported local WAHA `401` is an operational configuration failure: `WAHA_API_KEY` is not configured. Existing OTP routes and the server-side sender establish API capability, not delivery readiness. This inventory does not claim that a WhatsApp message was sent.

## Scope Baseline

- **Discovery method:** Read the Flutter `fonctionnalites.md`, API `README.md`, Flutter Dart sources, dependency/platform configuration, Flask route decorators and Socket.IO handlers; searched the Flutter source for Firebase SDK types/imports and direct HTTP/provider calls.
- **Items discovered:** 22 Dart files with Firebase references; four Firebase packages declared directly; four direct-provider REST client services; 12 Flask route modules plus the generated OpenAPI/Swagger documentation routes; 14 functional flow groups below.
- **Items in scope:** All reachable passenger/driver operations and visible or source-present dormant flows that require an explicit disposition; every registered API route and realtime event relevant to the mobile boundary.
- **Scope exclusions:** Admin-only operations are catalogued as API capabilities but are not represented as current mobile screens. OS GPS and Google Maps map rendering are device/presentation capabilities, not Firebase data operations.

## User Scenarios and Existing Behaviors

### Passenger journeys

1. **Phone sign-in and OTP (P1).** On launch, a signed-out passenger enters an international phone number, requests a six-digit OTP, and submits it. The resend control currently only clears the input/restarts its timer; it does not request another code. The current verification screen can navigate into the app even when verification returns false. The underlying AuthService also has email/password methods, but they are not connected to a user-facing sign-in screen.
2. **Restore and end a session (P1).** The app currently waits on Firebase Auth state and enters the passenger shell when authenticated. There is a logout method but no active sign-out entry point. Migration acceptance requires restoration of a valid API session, an explicit expired/unauthorized transition, and a reachable sign-out that returns to the signed-out screen.
3. **Request a ride (P1).** The passenger grants location permission, sees a map/current location, searches for an origin/destination, selects a suggestion, views a route, chooses car/comfort/moto and a fare (current presets are 1,000/2,000/3,500 XAF; custom fare changes by 250 XAF within 500–50,000 XAF), then requests a driver. The current Flutter client calls Google Places and Routes directly. A custom map style is loaded but not applied; recent destinations and recenter controls are commented out.
4. **Review and accept driver offers (P1).** While a ride is searching, the passenger sees offers, can sort by price/rating/arrival, and accepts one. Current UI also layers fake demo offers; they are not backed by persistent rides and accepting them can fail. The real flow watches ride/offer state through Firestore.
5. **Follow and finish a ride (P1).** The passenger sees the accepted driver/vehicle and a completed-ride cash-settlement prompt. Current client ride tracking is Firestore-based; the accepted driver's moving location is not displayed as a live marker. Cash settlement is confirmed by the driver.
6. **View history and edit profile (P2).** The passenger sees past rides and profile/rating/counts, can edit name/phone and choose/upload/delete an avatar. History and profile data use Firestore; avatar files use Firebase Storage. Profile settings tiles currently have no actions.

### Driver journeys

7. **Register as a car or motorcycle driver (P1).** The passenger chooses a vehicle type, enters brand/model/color/plate, selects required photos/documents, uploads them, and sees a pending-verification screen. Car onboarding requests eight items (license, registration, front/left/right/back/interior, plate); motorcycle onboarding requests seven (no interior). Car and motorcycle documents use different current Firestore nesting; the motorcycle data does not match the verification screen's root-document lookup.
8. **Review verification and driver profile (P2).** The verification page reads document status but its re-upload actions are disabled. The separate document-status and driver-profile pages are present in source but are not linked into the active navigation.
9. **Go online and respond to rides (P1).** A driver checks wallet balance/block status, goes online, views searching rides, opens ride details, and accepts or negotiates a fare. The active UI reads Firestore and can show fake rides when no real ride exists. It does not continuously update driver location after going online.
10. **Progress and settle a ride (P1).** A driver marks arrival, starts and completes the ride, confirms cash, and incurs a platform commission. The current ride state, cash settlement, and commission are client-side Firestore operations. “Call” and “Message” currently display a SnackBar rather than invoking a phone or chat feature.
11. **View and recharge the driver wallet (P1).** The driver sees balance/block state and transaction history, selects among 16 countries and their operators/currency-specific suggested amounts, enters a phone number, initiates a PawaPay deposit, polls the provider, and expects the wallet to be credited. Current client calls PawaPay directly and credits Firestore from the client after polling; its no-token simulation path can also return a submitted result without a real provider payment.

### Present but disconnected, placeholder, or non-user-facing flows

12. **PayCentral passenger payment (P2, dormant).** A complete-looking payment service and sheet exist for Airtel/Moov/cash, but no active screen opens the sheet. API payment initiation/status routes exist.
13. **Chat and notifications (P2, placeholder).** Active ride controls display a message placeholder; notification settings are inert. API chat, notification list/read, device-token registration, and realtime notification events exist, but the Flutter UI does not currently use them.
14. **Other dormant actions.** Rating, ride cancellation, recent destinations, driver document/profile pages, and email authentication are implemented in API routes or source components but are not exposed as active flows. There is no actual call action, security/language preference behavior, or push-notification user flow in the current app. Do not treat these as existing working features or invent silent fallbacks.

### Observable edge cases to preserve or correct explicitly

- **Location:** GPS disabled/permission denied shows a retry/error state; unavailable coordinates leave the map loading. The origin defaults to “My location.” Device location is a local capability, while driver coordinates are sent to the server.
- **Search/route:** Places autocomplete is debounced and country-biased to Gabon; zero results are empty, provider/network errors are shown, and route failure produces a visible message. The phone entry currently defaults to Morocco despite the Gabon-focused ride flow.
- **Ride search:** An empty real-offer list currently mixes with fake offers; the server-backed target must show a truthful searching/empty state. A ride in progress must survive reconnect/session restoration or show a recoverable error.
- **Driver onboarding:** Car/moto registration requires vehicle fields and required documents; incomplete forms block submission. Motorcycle document nesting currently differs from the verification screen's lookup.
- **Wallet/payment:** A blocked/insufficient driver wallet prevents going online and prompts recharge. Pending, rejected, timeout, provider/network, and API authorization failures must not be presented as completed payment/recharge.
- **Profile and optional actions:** The profile falls back to the phone number when profile phone data is absent. Settings, recent destinations, call, and message actions that are currently inert/placeholders should not acquire silent success behavior.

## Requirements for Migration Traceability

- **REQ-001 — OTP (two independent gates):**
  - **Client behavior gate:** The passenger can request, resend, and verify an OTP through the existing API. A wrong/expired code, rate limit, network error, or delivery failure remains an error and never enters the authenticated app. Resend must make a real API request, not only restart a timer.
  - **Operational delivery gate:** A permitted end-to-end send/receipt/verify check passes after an operator configures `WAHA_API_KEY` in the API's local, untracked environment. This gate is currently **BLOCKED / NOT VERIFIED** by the disclosed WAHA `401`; it is not a missing API capability and must not be worked around or represented as a successful send. The secret is never required in the Flutter app or committed artifacts.
- **REQ-002 — Session:** A valid authenticated session survives an app restart; an expired/rejected session transitions once to the signed-out state; sign-out clears credentials and protected UI state.
- **REQ-003 — Passenger profile:** The authenticated passenger can read/update profile fields and upload/delete an avatar; a failed update is visible and does not display a false success.
- **REQ-004 — Map search:** The passenger can search and select place suggestions and obtain origin/destination coordinates without a direct Google Places REST request from Flutter.
- **REQ-005 — Route and ride estimate:** Route geometry/distance/duration and price estimate are available through the API boundary while retaining the current map and fare-selection experience.
- **REQ-006 — Ride request:** A selected car/comfort/moto and fare create one API-backed ride; no fake/demo ride is treated as a real request.
- **REQ-007 — Offers:** The passenger can list/receive genuine ride offers, compare them, and accept a valid offer; stale or invalid offers produce a visible error.
- **REQ-008 — Ride tracking:** Passenger and driver see authoritative ride status transitions and supported live driver-location updates; reconnecting does not silently lose the active ride.
- **REQ-009 — Ride history:** The passenger can load their paginated ride history from API-managed data and sees an explicit empty/error state.
- **REQ-010 — Driver onboarding:** A driver can register/update a car or motorcycle and upload the required documents; status shown by the app corresponds to the server's document state.
- **REQ-011 — Driver operations:** A driver can read profile/vehicles, manage availability/location, view available rides, submit/accept offers, and progress an accepted ride using server-authoritative results.
- **REQ-012 — Settlement and wallet:** Cash settlement/commission and wallet state/transactions are API-authoritative. Wallet recharge confirmation comes from server-verified payment state, not a mobile-side credit.
- **REQ-013 — Provider requests:** PawaPay, PayCentral, Places, and route-provider REST operations are not called directly by Flutter; provider errors are surfaced without success-shaped fallbacks.
- **REQ-014 — Chat and notifications:** Where retained or activated, message and notification list/read/device-token operations use the existing API/realtime capabilities; no empty no-op is reported as success.
- **REQ-015 — Firebase removal:** After migration and verification, the app has zero Firebase runtime imports/initialization/dependencies for product behavior. Firebase platform setup is removed only after analysis/build verification; user-owned Firebase project/data is not deleted.

## Existing Flask API Capability Catalog

Paths below are the current source route registrations grouped by blueprint prefix. The API's OpenAPI describes authenticated operations with JWT Bearer authorization and JSON success/error envelopes; file uploads use multipart requests. This is a route inventory, not a contract sign-off.

| Area | Existing routes |
|---|---|
| Health | `GET /`; `GET /api/health` |
| Auth (`/api/auth`) | `POST /otp/send`; `POST /otp/resend`; `POST /otp/verify`; `POST /register`; `POST /login`; `POST /password/forgot`; `POST /password/reset`; `POST /refresh`; `POST /logout`; `GET /me` |
| Users (`/api/users`) | `GET /me`; `PUT|PATCH /me`; `POST /me/avatar`; `DELETE /me/avatar`; `DELETE /me`; `GET /me/rides`; `GET /me/referral`; `GET /me/recent-destinations`; `POST /me/device-token` |
| Drivers (`/api/drivers`) | `POST /register`; `GET /me`; `GET /me/rides`; `GET|POST /me/vehicles`; `PUT /me/vehicles/{vehicle_id}/activate`; `GET /me/documents`; `POST /me/documents/{doc_type}`; `PUT /me/availability`; `PUT /me/location`; `GET /nearby` |
| Rides (`/api/rides`) | `POST /estimate`; `POST /`; `GET /active`; `GET /available`; `GET /{ride_id}`; `GET /{ride_id}/offers`; `POST /{ride_id}/offers`; `POST /{ride_id}/offers/{offer_or_driver_id}/accept`; `POST /{ride_id}/arrived`; `POST /{ride_id}/start`; `POST /{ride_id}/complete`; `POST /{ride_id}/cancel`; `POST /{ride_id}/rate` |
| Payments (`/api`) | `POST /rides/{ride_id}/pay/cash`; `POST /rides/{ride_id}/pay/paycentral`; `GET /payments/paycentral/{transaction_id}/status`; `POST /webhooks/pawapay`; `POST /webhooks/paycentral` |
| Wallet (`/api/wallet`) | `GET /countries`; `GET /`; `POST /recharge`; `GET /recharge/{deposit_id}/status` |
| Maps (`/api/maps`) | `GET /places/autocomplete`; `GET /places/details`; `POST /routes/compute` |
| Chat (`/api/rides`) | `GET /{ride_id}/messages`; `POST /{ride_id}/messages` |
| Notifications (`/api/notifications`) | `GET /`; `POST /{notification_id}/read`; `POST /read-all` |
| Admin (`/api/admin`, not a current passenger/driver screen) | `GET|POST /promo-codes`; `PATCH /promo-codes/{promo_id}`; `GET /drivers`; `GET /drivers/{driver_id}`; `POST /drivers/{driver_id}/documents/{doc_type}/review`; `POST /drivers/{driver_id}/verify`; `POST /drivers/{driver_id}/vehicles/{vehicle_id}/review`; `GET /stats`; `POST /seed-test-drivers` |
| Files (`/api/files`) | `GET /drivers/{driver_id}/{subpath}`; `GET /{subpath}` |
| API docs | Swagger UI at `/api/docs/`; `GET /api/openapi.json` |

### Realtime contract already advertised by the API

- **Client → server:** authenticated Socket.IO connection using an access JWT; `join_ride`, `leave_ride`, `driver:go_online`, `driver:go_offline`, `driver:location_update`, `driver:heartbeat` (or `ping`), and `ride:send_message`.
- **Server → client:** `connected` (including active ride IDs), `driver:availability_changed`, `driver:location_updated`, `driver:offline`, `ride:new`, `ride:offer_received`, `ride:accepted`, `ride:taken`, `ride:expired`, `ride:status_changed`, `ride:driver_location`, `ride:message`, `ride:paid`, `ride:cancelled`, `wallet:updated`, `driver:verification_updated`, and `notification:new`.
- The API README specifies JWT authentication for Socket.IO and a periodic heartbeat while a driver is online.

## Firebase Runtime and Platform Inventory

| Flutter source/config | Current use to replace or disposition |
|---|---|
| `lib/main.dart`, `lib/firebase_options.dart`, `lib/auth_wrapper.dart` | Firebase initialization/options and Firebase Auth state stream currently determine app startup/authenticated navigation. |
| `lib/services/Auth.dart` | Firebase Auth email/phone operations, Firestore user creation, current-user lookup, and sign-out. OTP and email methods exist; the app currently calls the phone flow. |
| `lib/functions.dart` | Firestore ride creation and passenger ride-history copy; also contains an unused GeoFire nearby-driver helper. |
| `lib/services/driver_service.dart` | Firestore reads/writes/streams for driver registration, ride/offer state, wallet and transactions, availability, cash settlement, and commission. |
| `lib/userScreens/dataService.dart` | Firestore test-driver import/list service; the import button is commented out. |
| `lib/userScreens/mapPage.dart` | Firestore listeners for test drivers, active ride, and offers. |
| `lib/userScreens/history/history.dart`; `lib/userScreens/profil/profile_page.dart` | Firebase Auth identity plus Firestore passenger history/profile reads. |
| `lib/userScreens/profil/edit_profile_page.dart` | Firebase Auth identity/profile update, Firestore profile write, Firebase Storage avatar upload/delete, and Firebase Auth display-name/photo URL synchronization. |
| `lib/driversScreens/CarInfos.dart`; `lib/driversScreens/MotoInfos.dart` | Firebase Auth identity, Firebase Storage document uploads, and Firestore driver registration/document metadata. |
| `lib/driversScreens/DriverDocsVerificationPage.dart` | Firebase Auth identity and Firestore driver-document status stream. |
| `lib/driversScreens/test/document_status_page.dart` | Firebase-backed document repository in a page that is not linked into current navigation. |
| `lib/driversScreens/test/offers_page.dart`; `lib/driversScreens/test/ride_details_page.dart`; `lib/driversScreens/test/active_ride_page.dart`; `lib/driversScreens/test/ride_offer.dart` | Firebase Auth identity and/or Firestore-backed offers, ride records, and snapshot parsing. |
| `lib/driversScreens/wallet/driver_wallet_page.dart`; `lib/driversScreens/wallet/recharge_wallet_sheet.dart` | Firebase Auth identity and Firestore wallet/transaction reads; recharge sheet obtains phone data from Firebase Auth. |
| `lib/widgets/paycentral_payment_sheet.dart` | Dormant PayCentral sheet uses Firebase Auth phone as a default value. |
| `pubspec.yaml` / `pubspec.lock` | Direct declarations/resolved graph include `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`; `geoflutterfire_plus` is also declared for the unused Firestore/GeoFire helper. |
| `firebase.json`, `lib/firebase_options.dart`, `android/app/google-services.json`, Android Google Services Gradle plugin declarations, and generated platform plugin registrants | Firebase initialization/platform setup and generated plugin wiring. Generated build/cache files are not treated as source-of-truth changes. |

No Firebase Messaging dependency was found in the direct Flutter dependency inventory. Firebase project configuration is not the same as user data: do not delete remote project data or user files as part of this migration.

## Direct Provider Requests from Flutter

| Provider/client behavior | Current Flutter location | Existing API replacement capability |
|---|---|---|
| Google Places autocomplete/details REST | `lib/userScreens/places_service.dart` (invoked from `mapPage.dart`/`place_search_controller.dart`) | `GET /api/maps/places/autocomplete`, `GET /api/maps/places/details` |
| Google Routes computeRoutes REST | `lib/services/itinéraire/DirectionsService.dart` | `POST /api/maps/routes/compute` |
| PawaPay deposit initiation and status polling | `lib/services/pawapay_service.dart`, invoked by `driversScreens/wallet/recharge_wallet_sheet.dart`; currently initiated with a client-configured provider token | `GET /api/wallet/countries`, `POST /api/wallet/recharge`, `GET /api/wallet/recharge/{deposit_id}/status`, plus `POST /api/webhooks/pawapay` |
| PayCentral initiation and status polling | `lib/services/paycentral_service.dart`, `lib/widgets/paycentral_payment_sheet.dart`; sheet currently has no active caller and client code contains provider credential configuration | `POST /api/rides/{ride_id}/pay/paycentral`, `GET /api/payments/paycentral/{transaction_id}/status`, plus `POST /api/webhooks/paycentral` |
| Google Maps map rendering | `google_maps_flutter` map widgets and native Android map configuration | This is presentation SDK usage, distinct from Places/Routes REST. Keep or change only through an explicit architecture decision; provider REST calls should use the existing API proxy. |

The client contains hard-coded provider credential/configuration material in the above provider/map code and related configuration. Secret values are intentionally omitted from this artifact. The implementation should remove client-held payment/map provider secrets and configure any required map-rendering key with platform restrictions. WAHA settings, including `WAHA_API_KEY`, belong only in the API's untracked local environment.

## Capability Crosswalk and Known Dispositions

| Existing behavior | API capability evidence | Current-state issue / disposition |
|---|---|---|
| Phone OTP send, resend, verify | `/api/auth/otp/send`, `/resend`, `/verify` | API capability exists. Replace Firebase flow; make resend a real API request and keep delivery/verification failures visible. The API documents `502 OTP_DELIVERY_FAILED` for delivery failure; the disclosed underlying WAHA `401` is caused by missing local `WAHA_API_KEY`. Client behavior can be implemented against the API, but operational send/receipt/verify remains **BLOCKED / NOT VERIFIED** until an operator configures the key and validates delivery. Do not treat route availability or the WAHA error as delivery, add a parallel OTP route, or expose the key to Flutter. |
| Session identity, refresh, logout | `/api/auth/me`, `/refresh`, `/logout` | API capability exists. Current app has no visible logout action and listens to Firebase Auth state. |
| Passenger profile/avatar | `/api/users/me`, `/api/users/me/avatar` (upload/delete) | API capability exists; replace Firestore/Storage and preserve edit behavior. |
| Search, route, fare, ride creation | `/api/maps/*`, `/api/rides/estimate`, `POST /api/rides` | API capability exists; move Places/Routes REST and ride data behind API. Device GPS/map display remain presentation/device concerns. |
| Ride offers/acceptance/status/location | `/api/rides/*` and Socket.IO events listed above | API capability exists. Remove fake passenger/driver demo offers; they must never be shown as successful server-backed rides. |
| Passenger history/recent destinations/rating/cancel | `/api/users/me/rides`, `/api/users/me/recent-destinations`, `/api/rides/{id}/rate`, `/api/rides/{id}/cancel` | API capability exists; some UI is read-only, commented, or lacks controls. |
| Driver profile, vehicle, documents, verification | `/api/drivers/*`, `/api/admin/drivers/*`, `/api/files/*` | API capability exists. Map both car and moto uploads/status to the API's actual contract; preserve admin review as server-side capability. |
| Driver online/nearby/ride offers | `/api/drivers/me/availability`, `/api/drivers/me/location`, `/api/drivers/nearby`, `/api/rides/available` and realtime events | API capability exists. Current UI lacks ongoing location updates and uses demo rides as fallback; don't convert fake data into success. |
| Cash and PayCentral ride payment | `/api/rides/{id}/pay/cash`, `/pay/paycentral`, status route | API capability exists. Cash is the current active path; PayCentral sheet is dormant. |
| PawaPay wallet recharge | `/api/wallet/*` and PawaPay webhook | API capability exists. Server must own provider request and verify completion before wallet credit; the current client-side direct request/credit is not a parity target. |
| Chat/notifications | `/api/rides/{id}/messages`, `/api/notifications/*`, device-token route, realtime events | API capability exists; current mobile controls are placeholders or absent. No live chat/push behavior should be claimed until wired and tested. |
| Phone call action | None needed for current implementation | The existing action only displays a SnackBar; it does not initiate a call. No API gap for a currently working feature. |
| Security/language settings | No corresponding current API operation identified | Current tiles have no behavior. Do not invent persisted settings without product/API design. |

## Acceptance Scenarios and Measurable Success Criteria

1. **Given** a signed-out user, **when** they request/resend an OTP and submit a valid code, **then** the app reaches its authenticated shell only after API verification succeeds; for invalid/expired codes, rate limits, delivery failures, or network errors it remains signed out and shows the failure. The client behavior gate is independently testable using the API contract.
2. **Given** an authenticated user, **when** they restart the app, **then** a still-valid session is restored; **when** the API rejects the token or the user signs out, **then** protected content is cleared and the signed-out state is shown without a retry loop.
3. **Given** a passenger selecting locations and a ride, **when** they search, estimate, request, receive, and accept an offer, **then** each visible result corresponds to API-backed data; no demo ride/offer is accepted as if real.
4. **Given** a driver uploading vehicle documents or progressing a ride, **when** the server accepts/rejects the operation, **then** the UI reflects that server result and exposes API errors rather than silently updating local success state.
5. **Given** a provider-backed recharge or payment, **when** the provider/server reports failure or pending status, **then** the wallet/payment UI does not claim completion or credit the wallet early.
6. **Given** the migrated source tree, **when** a complete source/dependency/platform search is run after cleanup, **then** zero runtime Firebase imports, initialization, or app-functionality dependencies remain; Firebase remote project/user data is untouched.
7. **Given** the API operator has configured `WAHA_API_KEY` privately in the API's local environment, **when** a permitted OTP send/receipt/verify check is run, **then** the API confirms delivery and verifies the received code. Until that evidence exists, record the operational delivery gate as **BLOCKED / NOT VERIFIED**; never put the key in Flutter or claim delivery based on a route response alone.

Measurable outcomes:

- **SC-001:** 100% of reachable backend-dependent passenger and driver operations above map to an existing API endpoint or supported Socket.IO event, or are explicitly documented as a real capability gap.
- **SC-002:** 0 Firebase runtime references/dependencies remain after the approved removal gate.
- **SC-003:** 100% of auth/payment/provider error paths tested as failures remain failures in the UI (no false success).
- **SC-004:** Every active journey in this inventory has at least one independently verifiable acceptance scenario; no demo data path is counted as a passing journey.
- **SC-005:** API tests, Flutter analyze/tests/build, and runtime endpoint/device checks are reported separately; unavailable tests or device setup are identified rather than counted as passing.
- **SC-006:** The OTP client behavior gate and operational delivery gate have separate recorded verdicts; operational delivery is PASS only with observed receipt and successful API verification, otherwise explicitly BLOCKED / NOT VERIFIED.

## Evidence and Readiness

### Upstream Artifacts Consumed

- `.github/modernize/rearchitecture/artifacts/t1-teamlead.md` — migration constitution and mandatory API-boundary, traceability, error/session, secret-handling, and behavior-preservation constraints.
- `.github/modernize/rearchitecture/artifacts/project-profile.yaml` — confirmed two-repository migration boundary and preservation of the existing Flutter UI.
- `.github/modernize/rearchitecture/learnings/teamlead/api-boundary-migration-governance.md` — reinforces that this artifact inventories observed capability while exact wire contracts belong in the architecture design.
- `.github/modernize/rearchitecture/artifacts/t3.1-pm.md` — re-review disposition separating OTP API/client capability from operational WAHA readiness, including the user-visible outcomes and the disclosed local-key blocker.

### Evidence Mapping

- `t1-teamlead.md#Core Principle I` and `#Migration Boundary & Cross-Cutting Constraints` → Firebase/provider inventory, endpoint crosswalk, and REQ-004/005/012/013/015.
- `t1-teamlead.md#Core Principle II` → behavior-to-endpoint catalog and explicit placeholder/gap dispositions.
- `t1-teamlead.md#Core Principle III` → REQ-001/002 and auth/session acceptance scenarios.
- `t1-teamlead.md#Core Principle IV` → secret redaction, API-side WAHA/provider requirements, and direct-provider inventory.
- `t3.1-pm.md#Finding Resolution` and `#Inventory Change to Carry Forward` → REQ-001's independent client-behavior and operational-delivery gates; the OTP crosswalk, acceptance criteria, and measurable readiness rule explicitly preserve `WAHA_API_KEY` as a local configuration blocker rather than a missing API capability.
- `project-profile.yaml#assessment.transformations` → scope includes Flutter runtime, platform configuration, provider requests, and the sibling Flask API.
- `moovi_mobile-master/fonctionnalites.md` plus `moovi_mobile-master/lib/**` → observed user flows and call sites summarized above.
- `../api/README.md`, `../api/app/views/**`, `../api/app/openapi.py`, and `../api/app/views/realtime.py` → existing REST routes, API auth/error conventions, provider proxies, and realtime events.

### Verification

- Source searches found 167 Firebase-related matches across 22 Flutter Dart files and direct external HTTP calls only in the Places, Routes, PawaPay, and PayCentral client services.
- Flask route decorators were reviewed across all 12 view modules; API docs/OpenAPI registration and Socket.IO event handlers were also reviewed.
- API test source exists at `../api/tests/test_api_and_realtime.py`; no Flutter `test/` directory was present.
- No API or Flutter test suite was run for this documentation-only inventory. The WAHA 401 is reported in the supplied task context, not re-tested here.
- Re-reviewed the OTP inventory against t3.1: existing routes are capability evidence only; live WhatsApp delivery remains unverified. No secret was requested, recorded, or used, and no send was claimed.
- `context.md`, `decisions.md`, clarification, research summaries, knowledge graph, topology fanout, and prior PM log/inbox were absent at discovery time. The available constitution/project profile and repository evidence were used instead.

## Next-Phase Notes

- Architecture should turn the listed route families into exact request/response/error contracts and resolve the remaining distinction between native Google Maps rendering and API-proxied map-provider REST calls.
- Implementation planning should prioritize active passenger and driver vertical journeys, session/error behavior, and server-verified wallet settlement before removing Firebase dependencies/platform configuration.
- Any real-time behavior should use only the event names supported above; the app's current fake offers and direct provider credentials are not valid fallback behavior.
