# Reachability and demo state

When documenting app migrations, separate route-reachable behavior from unreferenced screens and demo/no-op UI paths using exact constructor and callback searches.

## What Happened
During moovi_mobile t2, a Firestore-backed `DocumentStatusPage` and a `demoOffers` sheet appeared to be live journeys in broad source searches. Checking constructor call sites showed the test-folder status page is not routed from the scanned Dart library; checking the callback showed the map placeholder only prints offer fields. The actual driver verification page is separately routed from vehicle onboarding.

## Takeaway
Use exact widget-constructor and route searches to establish reachability. In behavior artifacts, record fake/demo effects as `must_preserve: false`, and specify the desired API-backed/empty/error behavior without representing placeholders as backend capability gaps or live flows.

## History
- 2026-11-25 (moovi_mobile/t2): initial
