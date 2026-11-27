## [t3] Inventory mobile features and API capabilities
- Codebase/domain discoveries: The Flutter client has no Flask API calls yet; active Firestore/Auth/Storage paths coexist with four direct provider REST clients. The API already exposes route families for nearly every active passenger/driver data and payment journey.
- Non-obvious behavior: `fonctionnalites.md` documents the current UI comprehensively, but several interactions are intentionally fake, commented, or unreachable; classify those separately from functioning user journeys. Firebase references also remain in platform plugin/setup files.
- Wrong assumptions/corrections: Route existence alone is not proof of runtime contract parity; API wire shapes and behavior must still be verified in architecture and runtime validation.
- Techniques/patterns worth reusing: Use `rg` for exhaustive Firebase imports/provider HTTP calls, route decorators for API inventory, then cross-check the feature catalog against active source and route handlers.
- Learnings consumed: [teamlead/api-boundary-migration-governance]

## [t3.1] Clarified OTP readiness and WAHA blocker
- Codebase/domain discoveries: Existing OTP API routes and a server-side WAHA sender establish API capability, but do not establish that WhatsApp delivery is operational; the supplied local WAHA `401` is due to the unconfigured local `WAHA_API_KEY`.
- Wrong assumptions and corrections: Keep delivery readiness distinct from endpoint availability; do not call the WAHA sender live or turn the disclosed configuration blocker into a claimed API gap.
- Techniques/patterns worth reusing: State user-visible failure outcomes and a separate operational proof gate; keep credentials local and out of mobile code/artifacts.
- Learnings consumed: [teamlead/api-boundary-migration-governance]

## [t3] Re-reviewed OTP inventory after WAHA blocker classification
- Codebase/domain discoveries: The parent inventory already recorded the local WAHA `401`; it needed explicit independent OTP client-behavior and operational-delivery gates to match the t3.1 clarification.
- Wrong assumptions and corrections: API route availability supports implementation against the contract, but neither proves delivery nor clears the disclosed local-key blocker.
- Techniques/patterns worth reusing: Preserve existing requirement IDs and add clear gate distinctions, user-visible outcomes, and verification criteria rather than splitting the traceability baseline unnecessarily.
- Learnings consumed: [pm/otp-readiness-vs-route-availability]
