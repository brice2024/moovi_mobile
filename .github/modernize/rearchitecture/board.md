## User Input

> Perform the requested end-to-end migration of the Flutter app at `C:\Users\Brice\Downloads\moovi_mobile-master\moovi_mobile-master` from Firebase to the existing Flask API at `C:\Users\Brice\Downloads\moovi_mobile-master\api`. User explicitly wants all mobile app functionality to use this API instead of Firebase, not only OTP. Existing API already includes OTP routes; the WAHA sender was just added under `api/app/tools/waha.py`, with `SMS_PROVIDER=waha` and WAHA settings in `api/.env.example`. The actual WAHA local server returned 401 because `WAHA_API_KEY` is not configured; do not expose or invent secrets and do not claim a live WhatsApp send.
>
> This is a broad migration. Follow the loaded architecture-analysis skill workflow first (required references, global artifacts and per-unit completeness, migration boundary, wire contracts, seams, implementation index); then execute the migration as far as the repository evidence allows. Use the existing API routes as the source of truth and preserve current UI behavior. Inventory every Firebase SDK/import/use in Flutter (Auth, Firestore, Storage, initialization/platform setup), every direct provider request (PawaPay/PayCentral/Maps), and every existing API endpoint. Route mobile data/auth/payment/map/file/ride/driver/chat/notification operations through the Flask API; use its JWT for API authorization and secure persistent token storage; keep session restoration and logout working; use Socket.IO/realtime where the API supports it. Configure API base URL safely for Android emulator/device and make it overridable without committing credentials. Add/adjust backend endpoints only where the current API genuinely lacks behavior needed for an existing feature; never leave fake/silent fallbacks or Firebase data paths. Remove Firebase dependencies/config only after all runtime references have migrated and builds verify. Do not delete user data/config files unnecessarily.
>
> Acceptance: (1) no runtime Flutter Firebase SDK use or Firebase initialization/dependencies remain for app functionality; (2) all existing user-facing screens/features use the API or are explicitly documented as blocked by a missing API capability, with missing capabilities implemented where feasible; (3) OTP send/verify uses the existing API+WAHA path; (4) JWT persistence, API errors, unauthorized/session-expired flow, and sign-out are correct; (5) API tests and Flutter analyze/build/tests pass as available. Preserve existing unrelated changes. Do not commit. At completion report files/artifacts changed, exact API configuration required (including WAHA key kept local), tests and any unresolved runtime/device setup blockers. If a substantial design choice is genuinely blocked by missing user input, ask rather than guess.

**Project started**: 2026-11-25T15:24:30Z

## Tasks

### Phase: Foundation
- ✅ t1 [teamlead] Establish migration constitution and cross-cutting constraints (15:29:07Z→15:31:51Z, 2m 44s)

### Phase: Analysis
- ❌ t2 [architect] Produce complete source-anchored architecture analysis artifacts — 2 HIGH findings; clean re-review required
- ✅ t3 [pm] Re-review inventory after classifying the disclosed WAHA blocker (16:24:45Z→16:30:23Z, 5m 38s)
- 🔄 t2.1 [architect] Resolve and document all HIGH architecture-analysis findings using declared user scope (re-dispatched after remediation) [deps: t2]
- ✅ t2.1.1 [architect] Clear unresolved HIGH architecture findings and provide zero-HIGH closure evidence (16:24:47Z→16:34:31Z, 9m 44s)
- ✅ t3.1 [pm] Resolve the HIGH inventory finding while preserving the disclosed WAHA blocker (16:16:50Z→16:20:32Z, 3m 42s)

### Phase: Design
- ⏳ t4 [architect] Design API migration architecture and exact wire contracts [deps: t2, t3]
- ⏳ t5 [teamlead] Define end-to-end test strategy and runtime validation plan [deps: t2, t3]

### Phase: Implementation Planning
- ⏳ t6 [teamlead] Create traceable implementation plan and execution task breakdown [deps: t4, t5]

### Phase: Plan Validation
- ⏳ t7 [teamlead] Validate implementation plan coverage, dependencies, and feasibility [deps: t6]
⏳ [Execute + Validate phases — pending deep planning completion]

## Known blockers
- WAHA delivery is not runtime-verified: the local WAHA server returned 401 because `WAHA_API_KEY` is not configured. Keep the key local/untracked; do not claim a live WhatsApp send.
- Credential rotation/restriction is not verified; no credential value is recorded here.
