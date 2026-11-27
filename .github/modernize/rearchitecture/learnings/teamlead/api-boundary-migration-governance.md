# API Boundary Migration Governance

For cross-system migrations, treat the existing API as the authoritative boundary and require source-anchored behavior-to-contract mapping before client rewrites.

## What Happened

For Moovi task t1, the assessed project profile described replacing Firebase and direct provider paths while retaining the Flutter UI. The API documentation describes JWT-protected REST, Socket.IO, API-side OTP delivery, and explicit failure responses. The constitution therefore requires API-mediated provider REST operations, secure JWT/session handling, explicit gaps instead of silent fallbacks, and delayed removal of Firebase configuration until references and builds are verified.

## Takeaway

Keep migration-wide invariants in the constitution, but leave exact endpoint/request/response choices to the architecture design after inventory. Distinguish client presentation SDK usage from provider REST access, and do not claim remote delivery when the server reports failure.

## History
- 2026-11-25 (Moovi/t1): initial
