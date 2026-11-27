2026-11-25T16:13:47Z — Broadcast from t2 [architect]: Architecture analysis reports the existing Flask API as the mobile data/auth/payment boundary; demo offers and disconnected UI must not be treated as live flows. No core API capability gap was confirmed. WAHA delivery still requires local WAHA_API_KEY configuration; no live WhatsApp send was verified.

2026-11-25T16:20:32Z — Broadcast from t2.1 [architect]: Architecture scope confirmed: replace all Flutter Firebase runtime paths and direct provider REST calls with Flask API contracts. Keep only device geolocation and restricted native map rendering client-side; remove Firebase dependencies/config after source cleanup and build verification.

2026-11-25T16:34:31Z — Broadcast from t2.1.1 [architect]: Architecture decision: provider REST stays behind Flask; Firebase runtime removal is required for final acceptance. The two architecture questions are closed, but implementation and security-operation evidence remain pending.
