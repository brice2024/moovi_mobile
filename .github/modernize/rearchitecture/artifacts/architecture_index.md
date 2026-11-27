# Architecture implementation guide

This index is not the full contract. Do not implement from this file alone; follow the artifact paths below.

## Global artifacts

- `unit_graph.yaml` — all workers: filter units for exact page triggers, source evidence, dependencies, and shared references. Source anchors are not rewrite targets.
- `migration_boundary.yaml` — all workers: use `must_rewrite`, `copy_as_is`, `legacy_allowed_to_remain`, and `defer_cleanup` to bound changes.
- `wire_contracts.yaml` — workers touching auth/data/files/payments/maps/ride/realtime: select route-family entries by unit; map to existing Flask contracts and preserve documented status/error behavior.
- `shared_modules.yaml` — workers using authentication or legacy Firestore service code: filter by `used_by_units`; listed fields are the whitelist, and `driver_service` is a split candidate, not an already-decided target structure.
- `cross_unit_state.yaml` — workers changing auth/navigation/ride selection: filter flows where writer or reader unit matches; preserve session and selected-ride handoffs.
- `seams.yaml` — all mobile/API workers: declared Flutter→Flask cut is authoritative; preserve existing Flask contracts, use the explicit SDK-to-REST/Socket.IO mapping, and only add backend behavior for evidenced gaps.
- `project-structure.md`, `tech-stack.md`, `data-model.md` — global context; existing API schema is documented as-is.

## Implementation Guide

### Unit: `auth-session`
- external trigger: app launch, phone sign-in/OTP request or verification.
- must read: `units/auth-session/behavior.yaml` (OTP, restoration, errors, logout); `units/auth-session/bindings.yaml` (entry/session wiring and runtime config); `units/auth-session/unit_decomposition.yaml` (advisory split candidates only).
- relevant global rows: auth routes in `wire_contracts.yaml`; `AuthService` in `shared_modules.yaml`; authentication flow in `cross_unit_state.yaml`; declared mobile/API cut in `seams.yaml`.
- before DONE report: artifact paths read, every OTP/session/error/logout behavior preserved, unresolved API/config items, endpoint and app test/build/runtime evidence.

### Unit: `passenger-tabs`
- external trigger: passenger tab selection from map/history/profile shell.
- must read: `units/passenger-tabs/behavior.yaml`, `units/passenger-tabs/bindings.yaml`, `units/passenger-tabs/unit_decomposition.yaml`.
- relevant global rows: auth-state gating in `cross_unit_state.yaml`; shared UI tab contract in `unit_graph.yaml`.
- before DONE report: tab mapping retained and evidence for navigation/session restoration.

### Unit: `passenger-booking`
- external trigger: map page; origin/destination lookup, route/price preview, ride request, driver offers and selection.
- must read: `units/passenger-booking/behavior.yaml`, `units/passenger-booking/bindings.yaml`, `units/passenger-booking/unit_decomposition.yaml`.
- relevant global rows: maps, driver, ride, and realtime rows in `wire_contracts.yaml`; `DriverService` in `shared_modules.yaml`; declared mobile/API seam; test-fixture note in `migration_boundary.yaml`.
- before DONE report: every search/create/offer/accept branch and API error path implemented, provider HTTP no longer called by the app, realtime subscription evidence, demo-fixture disposition, tests/build/runtime evidence.

### Unit: `passenger-history`
- external trigger: History tab.
- must read: `units/passenger-history/behavior.yaml`, `units/passenger-history/bindings.yaml`, `units/passenger-history/unit_decomposition.yaml`.
- relevant global rows: `GET /api/users/me/rides` and `GET /api/rides/active` in `wire_contracts.yaml`; auth session flow.
- before DONE report: loading/empty/error states, ordering/pagination behavior, API evidence.

### Unit: `passenger-profile`
- external trigger: Profile tab.
- must read: `units/passenger-profile/behavior.yaml`, `units/passenger-profile/bindings.yaml`, `units/passenger-profile/unit_decomposition.yaml`.
- relevant global rows: user profile, driver profile, account/logout API contracts; `AuthService` and `DriverService`; profile-edit navigation flow.
- before DONE report: profile source, driver-mode decision, logout/session handling, and any placeholder notification action.

### Unit: `profile-edit`
- external trigger: Edit profile action from passenger profile.
- must read: `units/profile-edit/behavior.yaml`, `units/profile-edit/bindings.yaml`, `units/profile-edit/unit_decomposition.yaml`.
- relevant global rows: user profile/avatar routes, file contracts, auth state and edit-result flow.
- before DONE report: field validation, avatar upload/replace/delete and API error evidence; do not leave Firebase Storage cleanup.

### Unit: `driver-onboarding`
- external trigger: select car/moto and submit vehicle details/documents.
- must read: `units/driver-onboarding/behavior.yaml`, `units/driver-onboarding/bindings.yaml`, `units/driver-onboarding/unit_decomposition.yaml`.
- relevant global rows: driver register/document upload routes and file serving; `DriverService`; auth state; declared seam.
- before DONE report: car/moto required-field/document branches, multipart contract, registration result, and upload/error evidence.

### Unit: `driver-documents`
- external trigger: verification status or document-status screen.
- must read: `units/driver-documents/behavior.yaml`, `units/driver-documents/bindings.yaml`, `units/driver-documents/unit_decomposition.yaml`.
- relevant global rows: `/api/drivers/me/documents`, `/api/drivers/me`, upload routes and protected file route; auth state.
- before DONE report: mapping of API document summary to UI status states, re-upload behavior, and error evidence.

### Unit: `driver-offers`
- external trigger: driver offers/online page.
- must read: `units/driver-offers/behavior.yaml`, `units/driver-offers/bindings.yaml`, `units/driver-offers/unit_decomposition.yaml`.
- relevant global rows: driver availability/location, available rides, wallet, ride-offer and Socket.IO contracts; `DriverService`.
- before DONE report: online/offline gates, wallet/verification errors, request stream/realtime behavior, heartbeat/location evidence.

### Unit: `driver-ride-details`
- external trigger: inspect an available ride and submit/negotiate offer.
- must read: `units/driver-ride-details/behavior.yaml`, `units/driver-ride-details/bindings.yaml`, `units/driver-ride-details/unit_decomposition.yaml`.
- relevant global rows: ride detail/offer/accept contracts, Socket.IO events and `DriverService`.
- before DONE report: status change handling, offer payload, duplicate/closed ride errors, and API evidence.

### Unit: `driver-active-ride`
- external trigger: active ride screen after offer acceptance.
- must read: `units/driver-active-ride/behavior.yaml`, `units/driver-active-ride/bindings.yaml`, `units/driver-active-ride/unit_decomposition.yaml`.
- relevant global rows: active ride/status transitions, cash confirmation/payment status, driver location, realtime, `DriverService`.
- before DONE report: arrival/start/complete/cancel and payment semantics, concurrency/error results, and endpoint/realtime evidence.

### Unit: `driver-profile`
- external trigger: driver profile/settings page.
- must read: `units/driver-profile/behavior.yaml`, `units/driver-profile/bindings.yaml`, `units/driver-profile/unit_decomposition.yaml`.
- relevant global rows: user/driver identity, logout, wallet navigation, authentication cross-unit state.
- before DONE report: navigation and sign-out/session-expiry behavior, plus any currently unwired settings actions.

### Unit: `driver-wallet`
- external trigger: driver wallet or recharge sheet.
- must read: `units/driver-wallet/behavior.yaml`, `units/driver-wallet/bindings.yaml`, `units/driver-wallet/unit_decomposition.yaml`.
- relevant global rows: wallet PawaPay API routes, payment webhook/service ownership, `DriverService`, JWT/session and wallet realtime events.
- before DONE report: pending/success/failure states and polling/realtime behavior; no provider request or credit may be fabricated client-side.

### Unit: `passenger-payment`
- external trigger: PayCentral payment sheet function (currently no call site found).
- must read: `units/passenger-payment/behavior.yaml`, `units/passenger-payment/bindings.yaml`, `units/passenger-payment/unit_decomposition.yaml`.
- relevant global rows: `/api/rides/{rideId}/pay/paycentral`, transaction status and payment settlement contracts; `DriverService`; current unreferenced status note.
- before DONE report: whether the UI is made reachable, preserved but disconnected, or removed; if wired, verify only through API and record actual provider outcome.
