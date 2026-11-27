# Complete Client Integration Boundary

When a migration explicitly requires all mobile functionality to use an existing API and forbids old runtime SDKs, staged removal is a cutover sequence—not permission to retain the old integration in the final app.

## What Happened

For moovi_mobile t2.1, the declared Firebase-to-Flask scope resolved analysis ambiguity: all active Firebase auth/data/file/session paths and direct provider REST calls are to be replaced, with dependency/platform cleanup after references and builds verify. Native map rendering and device location remain presentation/device concerns. Exposed provider credentials still require owner-led rotation/restriction; documentation alone does not close that operational action.

## Takeaway

Separate final acceptance from safe sequencing. Record source/config cleanup as a post-cutover gate, preserve external project data, and keep credential rotation as an explicit non-disclosing operator verification. Do not confuse an existing API endpoint with successful runtime delivery (for example, WAHA still needs a local key). For architecture closure, distinguish a resolved scope/boundary question from unverified code cleanup, credential rotation, and runtime acceptance; do not call those operational gates complete.

## History
- 2026-11-25 (moovi_mobile/t2.1): initial
- 2026-11-25 (moovi_mobile/t2.1.1): clarified zero-open-architecture-question closure versus pending implementation/security evidence
