# Existing data model

The API is the authoritative persistent model. It uses SQLAlchemy models under `../api/app/models/` and MySQL database `moovi_bd` per `../api/README.md`; no relational schema is present in Flutter. Fields below are the API model attributes, with serialized camelCase keys where relevant.

## Entities and relationships

- `users` (`User`, `user.py`): UUID id; phone/email unique; password hash; first/last name; photo path/URL; role; rating/count; rides count; language; notification preference; active flag; created/updated timestamps. One-to-one `Driver`; one-to-many `DeviceToken`.
- `otp_codes` (`OtpCode`): integer id, phone, hashed OTP, attempts, used flag, expiration/created timestamps. Associated by phone rather than a declared user FK.
- `token_blocklist` (`TokenBlocklist`): revoked JWT identifier, token type, optional user id, created timestamp.
- `device_tokens` (`DeviceToken`): token, platform, user FK and timestamps; one user owns multiple tokens.
- `drivers` (`Driver`): UUID id and unique user FK; current vehicle type/brand/model/color/plate; verification/availability/test status; location/heading/city/last-location time; wallet balance/block/recharge time; rating, level, rides/revenue metrics and timestamps. One user, multiple documents, vehicles, and wallet transactions.
- `driver_documents` (`DriverDocument`): integer id, driver FK, unique document type per driver, stored path/public URL, pending/verified/rejected status, rejection/reviewer/time and timestamps.
- `vehicles` (`Vehicle`): UUID id, driver FK, type/brand/model/color/plate, active/verification status and timestamps; driver+plate unique.
- `rides` (`Ride`): UUID id; passenger/user FK, optional driver FK; pickup/dropoff coordinates and addresses; ride type, price/agreed price/currency; distance/duration/polyline; status/cancel information; driver snapshot fields; payment/commission fields; lifecycle timestamps. Related offers, messages, ratings and one benefit.
- `ride_offers` (`RideOffer`): ride and driver FKs; driver snapshot/name/rating/level/car/plate; price/arrival ETA/photo/message/status/timestamps; unique ride+driver.
- `ride_ratings` (`RideRating`): ride/rater/target user FKs, target role, score/comment/time; unique ride+rater.
- `wallet_transactions` (`WalletTransaction`): id, driver FK, type/amount/currency, country/operator/phone/gateway/reference/status/description, optional ride FK/price/commission, timestamps.
- `ride_messages` (`RideMessage`): ride/sender user FKs, sender role, content/read flag/time.
- `notifications` (`Notification`): user FK, title/body/type/JSON payload/read flag/time.
- Benefits in `benefits.py`: `promo_codes`; `ride_benefits` joins ride/user/optional promo code and tracks promo/credit discount/status; `referral_codes` has a unique user and unique code; `referrals` relates referrer/referred users and reward lifecycle; `user_credit_transactions` records user credits and unique reference keys.

## Key entities

1. User — API identity/profile and owner of passenger actions.
2. Driver — driver operational state, vehicle snapshot, location, verification and wallet.
3. Ride — core lifecycle, fare, participants, route data and payment settlement.
4. RideOffer — driver's proposal and passenger selection.
5. Vehicle / DriverDocument — multiple vehicle data and verification evidence.
6. WalletTransaction — auditable deposit, commission and subsidy ledger.
7. RideMessage / Notification — persisted communication and user alerts.
8. PromoCode / RideBenefit / Referral / UserCreditTransaction — promotions, referral credits and their redemption records.

## Important persistence and transaction behavior

- Ride offer acceptance locks the ride and changes the ride and competing offer statuses within a single database transaction.
- Driver ride transitions, cash settlement and wallet credit use row locks/atomic updates; settlement prevents duplicate commissions.
- OTP records are stored hashed, expiration-limited, attempt-limited, single-use; session token revocation is stored in `token_blocklist`.
- Uploaded avatar/driver document binaries use API filesystem storage under `UPLOAD_FOLDER`; metadata/path is persisted in SQL.
- Socket.IO carries state-change notifications; database rows remain authoritative. Do not reproduce Firestore collection structure or assume Firestore timestamps/GeoPoint serialization in target client models.
