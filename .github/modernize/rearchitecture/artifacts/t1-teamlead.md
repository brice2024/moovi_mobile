<!--
Sync Impact Report
- Version change: none → 1.0.0 (initial constitution)
- Modified principles: none → API as sole mobile backend boundary; source-anchored contracts;
  JWT/session correctness; secret and environment safety; behavior-preserving verification.
- Added sections: Migration Mode, Target Technology Stack, Migration Boundary & Cross-Cutting
  Constraints, Delivery Workflow & Quality Gates.
- Removed sections: none; the rewrite-only target stack section is retained and populated.
- Templates: ✅ creating-implementation-plan/templates/plan-template.md reviewed; its
  Constitution Check and mandatory brownfield Testing Strategy align.
  ✅ feature-inventory/templates/spec-template.md reviewed; its scope baseline, scenarios,
  requirements, and measurable outcomes support the constitution. Generated specs must cite
  the canonical artifact path rather than the template's generic ./constitution.md example.
  ⚠ breaking-down-tasks/templates/tasks-template.md not found in the installed skills path;
  verify its task categorization when that workflow is available.
- Follow-up: confirm the original ratification date; no historical constitution was present.
- Canonical artifact path for this run: artifacts/t1-teamlead.md.
-->

# Moovi Migration Constitution

## Migration Mode

**Mode**: REWRITE

**Justification**: Rewrite the mobile app's authentication, data, file, realtime, and provider
integration boundary to use the existing Flask API. This is a cross-system provider and data
boundary migration, not a Flutter UI rewrite or a greenfield backend. Preserve existing
user-visible behavior and retain the existing API as the target wherever its capability is
adequate.

## Core Principles

### I. The Flask API Is the Mobile Backend Boundary

Every mobile authentication, profile, ride, driver, chat, notification, wallet, payment,
location-search, route, and file operation MUST use the existing Flask REST or Socket.IO
contract where that capability exists. Flask API records and responses are authoritative.
Flutter MUST NOT retain Firebase Auth, Firestore, Storage, or other Firebase runtime paths,
nor make direct REST calls to payment, maps, OTP, or other backend providers. Provider REST
integrations belong behind the API. Any proposed client-side SDK exception must be documented
in the architecture design with its purpose and restricted credential treatment. This
boundary avoids split-brain data and prevents provider secrets from being distributed in the
mobile application.

### II. Trace Behavior to Evidence and Contracts

Before implementation, inventory the app's existing user-facing flows, Firebase and provider
call sites, and the API's actual routes and realtime events. Architecture and implementation
artifacts MUST map each existing behavior to an API contract or explicitly record it as
blocked by a missing API capability. Contracts MUST specify relevant request/response shapes,
authorization, error behavior, and realtime events. Add backend behavior only when evidence
shows the API lacks a capability required by an existing feature; preserve existing API
behavior and do not invent client-side fallback behavior.

### III. Preserve Session and Error Semantics

The API's access JWT MUST authorize protected API and Socket.IO operations. The mobile app
MUST store tokens using platform-secure persistent storage, restore valid sessions after
restart, and clear local credentials on sign-out. A rejected or expired session MUST enter
one explicit signed-out/session-expired flow rather than retrying indefinitely or displaying
stale protected data. API failures, including OTP delivery failure, MUST be surfaced as
failures; the app MUST NOT report success for a failed or unconfirmed operation.

### IV. Keep Secrets Server-Side and Configuration External

No API, WAHA, payment-provider, or other private credential may be committed or embedded in
Flutter source, assets, build configuration, or distributed app binaries. API base URL
configuration MUST be overridable per build/runtime without credentials. Android emulator
configuration may use the host-loopback alias `10.0.2.2`; physical devices MUST use an address
reachable from the device, and production traffic MUST use HTTPS. WAHA credentials remain in
the API's local, untracked environment; a WAHA 401 or other delivery error is an operational
failure, not evidence of a WhatsApp send.

### V. Preserve User Experience and Verify the Migration

The existing screens and observable user journeys MUST remain functional unless a documented
API capability gap blocks them. No feature may be replaced by a fake success, silent no-op, or
Firebase fallback. Retain Firebase dependencies and platform configuration only until all
runtime references are removed; remove obsolete Firebase configuration only after source
search and Flutter analysis/build verification demonstrate that the app no longer depends on
it. Verification MUST include API tests, Flutter static analysis and applicable tests/builds,
critical auth/ride/payment/file journeys, and API error/session-expiry behavior. A build alone
does not prove an endpoint or user journey works.

## Target Technology Stack

| Component | Target Version | Notes |
|-----------|---------------|-------|
| Mobile | Existing Flutter project; Dart SDK constraint `>=3.0.0 <4.0.0` | Preserve current UI and supported platform behavior; do not infer a new Flutter target version. |
| Backend | Existing Flask API as declared by its project manifests | Keep current API as the source of truth; add only evidence-backed missing behavior. |
| Persistence | Existing API-managed MySQL database (`moovi_bd`, per API documentation) | Do not introduce mobile-side Firebase persistence or a second source of truth. |
| Realtime | Existing Flask-SocketIO contract | Use JWT-authenticated events only where the API supports the relevant flow. |

## Migration Boundary & Cross-Cutting Constraints

- Replace mobile Firebase authentication/data/file/realtime uses and direct provider REST
  requests with API operations; keep platform UI capabilities such as map rendering only
  where required to present the existing experience and document any client SDK exception.
- Use the existing OTP send/verify routes. WAHA configuration is API-side; keep `WAHA_API_KEY`
  local and untracked. Do not claim successful delivery unless the API reports success.
- Route payment and map-provider requests through API capabilities. Do not move provider
  credentials into the mobile app. Where an existing feature has no API capability, record
  the exact gap and impact before deciding whether backend work can safely implement it.
- Configure the API host per target: host-reachable emulator address for Android emulator,
  device-reachable address for physical-device development, and HTTPS endpoint for production.
  Configuration must be replaceable without editing source or committing secrets.
- Preserve existing user data and unrelated project configuration. Do not delete Firebase
  project data or user-owned files as part of removing runtime dependencies.
- API authentication failures, validation failures, network outages, and provider delivery
  failures must remain distinguishable in the client experience; never swallow them or mask
  them with mock data.

## Delivery Workflow & Quality Gates

1. Architecture analysis and feature inventory establish source-anchored coverage before
   migration design. The architecture design records the mobile/API boundary, endpoint and
   Socket.IO contracts, client/server seams, and any documented capability gaps.
2. The implementation plan maps every in-scope behavior to a requirement and design contract,
   sequences dependent work, and defines test evidence before implementation starts.
3. Implement vertical user journeys while preserving existing screens. Change the API only
   for demonstrated gaps; do not perform unrelated backend, UI, or dependency upgrades.
4. Validate API tests and runtime endpoint behavior, Flutter analysis/tests/build, and critical
   mobile flows as available. Record exact commands, outcomes, device/environment prerequisites,
   and unresolved blockers. No phase may claim complete coverage for missing evidence.
5. Remove obsolete Firebase dependencies/platform configuration only after runtime references
   are absent and verification passes. A dedicated quality-gate task, not the artifact producer,
   determines conformance to this constitution.

## Governance

This constitution governs analysis, design, implementation, and validation artifacts for the
Moovi Firebase-to-Flask migration. A task that conflicts with a MUST-level rule is blocked
until the conflict is resolved. Amendments require a documented rationale, an incremented
semantic version, updated downstream guidance where affected, and notification to the
coordinator and roles that consume the changed rule. Version increments use MAJOR for
backward-incompatible changes to principles, MINOR for added or materially expanded rules,
and PATCH for clarifications that do not change obligations. Each role records evidence of
compliance in its task artifact; missing evidence is not presumed to pass. Constitution
production and conformance auditing are separate tasks.

**Version**: 1.0.0 | **Ratified**: TODO(RATIFICATION_DATE): original adoption date not provided | **Last Amended**: 2026-11-25

## Upstream Artifacts Consumed

- `.github/modernize/rearchitecture/artifacts/project-profile.yaml` — used for the assessed
  rewrite boundary, existing Flask target, and preservation of the current UI.
- `../api/README.md` — used for documented API ownership of auth, persistence, file, provider,
  and Socket.IO behavior, and the explicit WAHA error behavior.
- `pubspec.yaml` and `fonctionnalites.md` — used for the declared Flutter/Dart constraint and
  existing feature-preservation scope.

## Evidence Mapping

- `project-profile.yaml#assessment.rationale` → Migration Mode and Core Principle V; the
  integration boundary is rewritten while existing presentation behavior is preserved.
- `project-profile.yaml#assessment.transformations` → Core Principle I and Migration Boundary;
  Firebase and direct-provider paths move to the existing Flask API where supported.
- `../api/README.md#Envoi des codes OTP avec WAHA` → Core Principles III–IV; credentials stay on
  the server and delivery errors cannot be represented as success.
- `../api/README.md#Événements temps réel (Socket.IO)` → Core Principles I and III; supported
  realtime flows use the existing JWT-authenticated API event contract.

## Validation

- Reviewed constitution template and replaced all standard placeholders.
- Checked the implementation-plan Constitution Check and feature-spec structure for alignment.
- The task-template file was not present at the installed `breaking-down-tasks/templates/`
  path; downstream task breakdown must verify its own template when available.
- No application tests run; this deliverable changes governance documentation only.
