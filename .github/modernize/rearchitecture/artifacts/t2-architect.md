# t2 — Source-anchored architecture analysis

## Summary

The migration boundary is the Flutter mobile runtime and its integration layer, not a Flutter UI rewrite: 45 Dart files currently use Firebase SDKs, direct provider calls, or related state paths. The sibling Flask API already provides JWT-authenticated auth, profile, ride, driver, file, payment, maps, wallet, chat, notification, and Socket.IO contracts. No backend capability gap was confirmed for the core journeys; the bundled demo-driver importer and currently unconnected notification/payment UI require design-time disposition.

## Deliverables

- [architecture_index.md](./architecture_index.md) — implementation guide and exact per-unit reading/filter rules.
- [project-structure.md](./project-structure.md) — combined Flutter/API module and entrypoint map.
- [tech-stack.md](./tech-stack.md) — observed frameworks, versions, dependencies, and integration/config facts.
- [data-model.md](./data-model.md) — existing API-owned SQL entities and relationships.
- [unit_graph.yaml](./unit_graph.yaml) — 14 externally triggerable Flutter units and source anchors.
- [migration_boundary.yaml](./migration_boundary.yaml) — phased provider/runtime rewrite scope.
- [wire_contracts.yaml](./wire_contracts.yaml) — API route-family inventory, mobile contract mappings, provider and protocol facts.
- [shared_modules.yaml](./shared_modules.yaml) — cross-unit authentication and legacy data-service seams.
- [cross_unit_state.yaml](./cross_unit_state.yaml) — auth, navigation, and ride state handoffs.
- [seams.yaml](./seams.yaml) — declared Flutter-to-Flask boundary and protocol bridge rules.
- `units/<unit>/behavior.yaml`, `bindings.yaml`, and `unit_decomposition.yaml` — complete source-anchored contracts for all 14 units.

## Upstream Artifacts Consumed

- `.github/modernize/rearchitecture/artifacts/t1-teamlead.md` — migration constitution and cross-cutting constraints.
- `.github/modernize/rearchitecture/artifacts/project-profile.yaml` — measured scope, language/module boundaries, and migration rationale.
- `../api/README.md` — documented Flask REST, JWT, Socket.IO, OTP/WAHA, and error contracts.
- `pubspec.yaml` and the Flutter/API source files cited by the artifacts — declared dependencies and observed behavior.

## Evidence Mapping

- `t1-teamlead.md#Core Principles I–V` → `migration_boundary.yaml`, `seams.yaml`, and API/UI wire rows: Flask is the mobile backend boundary, credentials remain server-side, behavior/errors/session state are preserved.
- `project-profile.yaml#assessment.transformations` → `migration_boundary.yaml::must_rewrite`: Firebase, direct provider, and old session paths are in scope; screen presentation is retained.
- `../api/README.md#Événements temps réel (Socket.IO)` and `../api/app/views/realtime.py:20-335` → `wire_contracts.yaml` and `seams.yaml`: JWT socket auth, ride/driver events, and current event payloads.
- `../api/app/views/auth.py:100-352` and `../api/app/tools/waha.py` → `wire_contracts.yaml`: OTP send/resend/verify and JWT issuance are server-side; WAHA delivery failure is a failure, not success.
- `lib/userScreens/mapPage.dart:449-452`, `lib/services/driver_service.dart:61-80`, and API ride/driver routes → `units/passenger-booking/behavior.yaml` and relevant wire rows: Firestore streams map to API reads plus supported Socket.IO events.

## Findings

- HIGH: Flutter source contains embedded provider credentials (PawaPay/PayCentral/Google Maps). Values are intentionally omitted from this artifact; remove them from client code and rotate/restrict any credential exposed in distributed history as appropriate.
- HIGH: Firebase Auth/Firestore/Storage initialization and calls span app startup, identity, profiles, map/ride dispatch, driver onboarding/documents, wallet, and ride/payment screens.
- INFO: Existing Flask API has first-party OTP routes and the WAHA sender. The documented API returns `502 OTP_DELIVERY_FAILED` on delivery failure; the environment’s missing WAHA key is operational setup, not an architecture gap or verified send.
- INFO: Google Maps SDK is used to render the existing map UI. Keep it limited to presentation; autocomplete/place details/routes must cross the Flask API boundary. The native map renderer's platform key is distinct from exposing Places/Routes provider calls to the mobile app.
- WARNING: `userScreens/dataService.dart` imports bundled test-driver fixtures into the Firestore `test_drivers` collection. The Flask API has an admin-only generated test-driver seed route, but no matching mobile fixture-import route. Decide whether this debug affordance is removed or replaced; do not silently write mock/demo records to a user-facing endpoint.
- WARNING: `userScreens/mapPage.dart:799` opens a second placeholder offers sheet backed by `demoOffers`; its selection callback only prints values. Do not treat it as a live booking/acceptance path; the migrated flow should use API offers and explicit API acceptance.
- WARNING: `driversScreens/test/document_status_page.dart` defines `DocumentStatusPage`, but no constructor call site was found in the scanned Dart library. Its Firebase repository is not evidence of a currently reachable user journey; keep it explicitly disconnected unless design chooses to wire it.
- WARNING: Profile/driver-profile notification callbacks and the PayCentral payment sheet have no caller in the scanned Flutter library. API endpoints exist, but do not claim these UI flows are wired or exercised.

## Verification

- Parsed all 49 YAML artifacts; confirmed all 14 units have behavior/bindings/decomposition files and `commit: false`.
- Confirmed 31 unique unit source-anchor files, 157 in-range `source_loc` references, zero blank/comment-only source anchors, shared-field references valid, and seam checks valid.
- No application build or tests were run: this task produces analysis artifacts only; build/runtime validation belongs to the assigned smoke-test/runtime-validation phase.
