# OTP Readiness vs Route Availability

An existing OTP endpoint is a product capability, not proof that its external delivery provider is configured or working.

## What Happened

For Moovi task t3.1, the Flask OTP routes and WAHA sender existed, but the supplied local WAHA server returned `401` because `WAHA_API_KEY` was absent. The inventory update separated API capability from runtime delivery readiness and retained the blocker without exposing credentials or claiming a send.

## Takeaway

Inventory API availability and operational readiness independently. When delivery configuration is missing, specify the user-visible failure behavior and the runtime evidence needed to clear the blocker; never infer successful delivery from route existence.

## History
- 2026-11-25 (Moovi/t3.1): initial
