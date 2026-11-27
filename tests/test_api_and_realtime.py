"""Suite de tests automatisés REST + WebSocket (Socket.IO) pour Moovi API."""

import hashlib
import hmac
import io
from datetime import timedelta
from types import SimpleNamespace

import pytest
import requests
from app import create_app
from app.extensions import db, socketio
from app.models import (
    Driver,
    Referral,
    Ride,
    RidePayment,
    User,
    UserCreditTransaction,
)
from app.models.user import utcnow
from app.tools.waha import OtpDeliveryError, send_whatsapp_text


@pytest.fixture()
def app(tmp_path):
    app = create_app("testing")
    app.config["UPLOAD_FOLDER"] = str(tmp_path / "uploads")
    with app.app_context():
        db.create_all()
        yield app
        db.session.remove()
        db.drop_all()


@pytest.fixture()
def client(app):
    return app.test_client()


def _auth_via_otp(client, phone: str, first_name: str = "", last_name: str = ""):
    res_send = client.post("/api/auth/otp/send", json={"phoneNumber": phone})
    assert res_send.status_code == 200
    code = res_send.get_json()["data"]["debugOtp"]

    res_verify = client.post(
        "/api/auth/otp/verify",
        json={
            "phoneNumber": phone,
            "code": code,
            "firstName": first_name,
            "lastName": last_name,
        },
    )
    assert res_verify.status_code == 200
    data = res_verify.get_json()["data"]
    return data["accessToken"], data["user"]


def test_health_and_auth_otp_lifecycle(client):
    health = client.get("/api/health")
    assert health.status_code == 200
    assert health.get_json()["data"]["database"] == "up"

    # Envoi OTP + blocage cooldown sur renvoi immédiat
    send1 = client.post("/api/auth/otp/send", json={"phoneNumber": "+24107111111"})
    assert send1.status_code == 200
    otp = send1.get_json()["data"]["debugOtp"]

    resend_too_fast = client.post(
        "/api/auth/otp/resend", json={"phoneNumber": "+24107111111"}
    )
    assert resend_too_fast.status_code == 429

    # Mauvais code OTP -> rejeté (corrige le bug Flutter)
    bad_verify = client.post(
        "/api/auth/otp/verify",
        json={"phoneNumber": "+24107111111", "code": "000000"},
    )
    assert bad_verify.status_code == 401

    # Bon code OTP -> JWT valide
    good_verify = client.post(
        "/api/auth/otp/verify",
        json={"phoneNumber": "+24107111111", "code": otp, "firstName": "Brice"},
    )
    assert good_verify.status_code == 200
    token = good_verify.get_json()["data"]["accessToken"]
    headers = {"Authorization": f"Bearer {token}"}

    # Logout révoque le token
    logout = client.post("/api/auth/logout", headers=headers)
    assert logout.status_code == 200

    after_logout = client.get("/api/users/me", headers=headers)
    assert after_logout.status_code == 401


def test_waha_otp_message_uses_documented_endpoint_and_test_number(app, monkeypatch):
    captured = {}

    def fake_post(url, *, headers, json, timeout):
        captured.update(url=url, headers=headers, json=json, timeout=timeout)
        return SimpleNamespace(status_code=201, text="", raise_for_status=lambda: None)

    monkeypatch.setattr(requests, "post", fake_post)
    with app.app_context():
        app.config.update(
            WAHA_BASE_URL="http://localhost:3000/",
            WAHA_API_KEY="test-api-key",
            WAHA_SESSION="default",
            WAHA_TIMEOUT_SECONDS=4,
        )
        result = send_whatsapp_text(
            "+22891596443", "Votre code de vérification Moovi est : 123456."
        )

    assert result == {"delivered": True, "provider": "waha"}
    assert captured == {
        "url": "http://localhost:3000/api/sendText",
        "headers": {"X-Api-Key": "test-api-key"},
        "json": {
            "chatId": "22891596443@c.us",
            "text": "Votre code de vérification Moovi est : 123456.",
            "session": "default",
        },
        "timeout": 4,
    }


def test_waha_otp_delivery_failure_is_reported_without_fallback(client, app, monkeypatch):
    app.config.update(SMS_PROVIDER="waha", WAHA_API_KEY="test-api-key")

    def failed_post(*_args, **_kwargs):
        response = SimpleNamespace(status_code=401)
        raise requests.HTTPError("Unauthorized", response=response)

    monkeypatch.setattr(requests, "post", failed_post)
    response = client.post(
        "/api/auth/otp/send", json={"phoneNumber": "+22891596443"}
    )

    assert response.status_code == 502
    assert response.get_json()["error"]["code"] == "OTP_DELIVERY_FAILED"
    assert "debugOtp" not in response.get_json().get("data", {})


def test_swagger_ui_and_openapi_spec_cover_api_routes(client):
    docs = client.get("/api/docs/")
    assert docs.status_code == 200
    assert b"SwaggerUIBundle" in docs.data
    assert client.get("/api/docs/swagger-ui-bundle.js").status_code == 200

    response = client.get("/api/openapi.json")
    assert response.status_code == 200
    spec = response.get_json()
    assert spec["openapi"] == "3.0.3"
    assert "/api/rides" in spec["paths"]
    assert "/api/drivers/me/rides" in spec["paths"]
    assert "/api/users/me/referral" in spec["paths"]
    assert spec["paths"]["/api/rides"]["post"]["security"] == [
        {"BearerAuth": []}
    ]
    assert "security" not in spec["paths"]["/api/webhooks/pawapay"]["post"]
    assert not any(path.startswith("/api/docs") for path in spec["paths"])
    assert len(spec["paths"]) >= 50


def test_demo_seed_is_repeatable_and_additive(app):
    from app.tools.demo_data import seed_demo_data

    with app.app_context():
        db.create_all()
        first_run = seed_demo_data()
        second_run = seed_demo_data()
        assert first_run == {
            "passengersCreated": 1,
            "driversCreated": 5,
            "ridesCreated": 4,
        }
        assert second_run == {
            "passengersCreated": 0,
            "driversCreated": 0,
            "ridesCreated": 0,
        }
        assert User.query.count() == 6
        assert Driver.query.count() == 5
        assert Ride.query.count() == 4


def test_profile_avatar_and_driver_documents_moto_car(app, client):
    token, _ = _auth_via_otp(client, "+24107222222", "Jean", "Mba")
    headers = {"Authorization": f"Bearer {token}"}

    # Upload avatar
    avatar_res = client.post(
        "/api/users/me/avatar",
        headers=headers,
        data={"avatar": (io.BytesIO(b"fakejpegdata"), "avatar.jpg")},
        content_type="multipart/form-data",
    )
    assert avatar_res.status_code == 200
    photo_path = avatar_res.get_json()["data"]["photoPath"]
    file_res = client.get(f"/api/files/{photo_path}")
    assert file_res.status_code == 200

    # Inscription chauffeur moto + upload documents (corrige le bug moto.documents)
    reg_res = client.post(
        "/api/drivers/register",
        headers=headers,
        data={
            "vehicleType": "moto",
            "brand": "Bajaj",
            "model": "Boxer",
            "color": "Noir",
            "plate": "GA-999-AA",
            "license": (io.BytesIO(b"img1"), "license.jpg"),
            "registration": (io.BytesIO(b"img2"), "reg.jpg"),
            "front": (io.BytesIO(b"img3"), "front.jpg"),
            "left": (io.BytesIO(b"img4"), "left.jpg"),
            "right": (io.BytesIO(b"img5"), "right.jpg"),
            "back": (io.BytesIO(b"img6"), "back.jpg"),
            "platePhoto": (io.BytesIO(b"img7"), "plate.jpg"),
        },
        content_type="multipart/form-data",
    )
    assert reg_res.status_code == 201
    drv_data = reg_res.get_json()["data"]
    assert drv_data["vehicleType"] == "moto"
    assert drv_data["documents"]["total"] == 7
    assert drv_data["documents"]["uploaded"] == 7
    assert drv_data["documents"]["progressPercent"] == 100
    license_path = drv_data["documents"]["items"]["license"]["path"]
    assert client.get(f"/api/files/{license_path}").status_code == 401
    assert (
        client.get(f"/api/files/{license_path}", headers=headers).status_code == 200
    )
    other_token, _ = _auth_via_otp(client, "+24107222223", "Autre", "Usager")
    assert (
        client.get(
            f"/api/files/{license_path}",
            headers={"Authorization": f"Bearer {other_token}"},
        ).status_code
        == 403
    )

    # Ré-upload individuel d'un document depuis la page de vérification
    reup = client.post(
        "/api/drivers/me/documents/license",
        headers=headers,
        data={"file": (io.BytesIO(b"new_license"), "license2.png")},
        content_type="multipart/form-data",
    )
    assert reup.status_code == 200
    license_path = reup.get_json()["data"]["document"]["path"]

    # Admin approuve le dossier
    admin_reg = client.post(
        "/api/auth/register",
        json={"email": "admin@moovi.ga", "password": "password123", "fullname": "Admin"},
    )
    assert admin_reg.status_code == 201
    with app.app_context():
        admin_user = User.query.filter_by(email="admin@moovi.ga").first()
        admin_user.role = "admin"
        db.session.commit()
    admin_login = client.post(
        "/api/auth/login", json={"email": "admin@moovi.ga", "password": "password123"}
    )
    admin_token = admin_login.get_json()["data"]["accessToken"]
    verify_res = client.post(
        f"/api/admin/drivers/{drv_data['id']}/verify",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"verificationStatus": "approved"},
    )
    assert verify_res.status_code == 200
    assert verify_res.get_json()["data"]["verificationStatus"] == "approved"
    assert (
        client.get(
            f"/api/files/{license_path}",
            headers={"Authorization": f"Bearer {admin_token}"},
        ).status_code
        == 200
    )


def test_otp_send_is_rate_limited_per_ip(client):
    for index in range(5):
        response = client.post(
            "/api/auth/otp/send",
            json={"phoneNumber": f"+2410712345{index}"},
        )
        assert response.status_code == 200

    limited = client.post(
        "/api/auth/otp/send", json={"phoneNumber": "+24107123459"}
    )
    assert limited.status_code == 429


def test_rides_share_rate_limit_across_endpoints(client):
    token, _ = _auth_via_otp(client, "+24107123450")
    headers = {"Authorization": f"Bearer {token}"}

    for index in range(30):
        if index % 2:
            response = client.get("/api/rides/active", headers=headers)
        else:
            response = client.post(
                "/api/rides/estimate", headers=headers, json={"distanceKm": 2}
            )
        assert response.status_code == 200

    limited = client.get("/api/rides/active", headers=headers)
    assert limited.status_code == 429


def test_live_pawapay_ride_webhook_requires_verification(client, app, monkeypatch):
    with app.app_context():
        passenger = User(phone_number="+24107999999", first_name="Test")
        db.session.add(passenger)
        db.session.flush()
        ride = Ride(
            client_id=passenger.id,
            departure_lat=0.4,
            departure_lng=9.4,
            departure_address="Départ",
            destination_lat=0.5,
            destination_lng=9.5,
            destination_address="Arrivée",
            price=1000,
            status="completed",
            payment_transaction_id="dep_live_unverified",
            payment_provider="AIRTEL_GAB",
        )
        db.session.add(ride)
        db.session.flush()
        db.session.add(RidePayment(
            id="dep_live_unverified", ride_id=ride.id, payer_user_id=passenger.id,
            amount=1000, operator_code="AIRTEL_GAB",
        ))
        db.session.commit()
        ride_id = ride.id

    app.config.update(PAWAPAY_SIMULATE=False, PAWAPAY_TOKEN="", PAWAPAY_WEBHOOK_SECRET="")
    body = {"depositId": "dep_live_unverified", "status": "COMPLETED"}
    unconfigured = client.post("/api/webhooks/pawapay", json=body)
    assert unconfigured.status_code == 503

    # Sans secret : l'API revérifie le statut auprès de PawaPay.
    app.config["PAWAPAY_TOKEN"] = "test-token"
    monkeypatch.setattr(
        "app.views.payments.check_deposit_status",
        lambda _deposit_id: {"status": "SUBMITTED", "simulated": False},
    )
    response = client.post("/api/webhooks/pawapay", json=body)
    assert response.status_code == 200
    with app.app_context():
        assert db.session.get(Ride, ride_id).is_paid is False

    app.config["PAWAPAY_WEBHOOK_SECRET"] = "test-webhook-secret"
    invalid_signature = client.post(
        "/api/webhooks/pawapay", json=body, headers={"X-PawaPay-Signature": "invalid"}
    )
    assert invalid_signature.status_code == 401

    payload = b'{"depositId":"dep_live_unverified","status":"COMPLETED"}'
    signature = hmac.new(b"test-webhook-secret", payload, hashlib.sha256).hexdigest()
    signed = client.post(
        "/api/webhooks/pawapay",
        data=payload,
        content_type="application/json",
        headers={"X-PawaPay-Signature": f"sha256={signature}"},
    )
    assert signed.status_code == 200
    with app.app_context():
        paid = db.session.get(Ride, ride_id)
        assert paid.is_paid is True and paid.payment_method == "mobile_money"


def test_live_payment_clients_do_not_simulate_without_credentials(app):
    from app.tools.pawapay import check_deposit_status, initiate_deposit

    with app.app_context():
        app.config.update(
            PAWAPAY_SIMULATE=False,
            PAWAPAY_TOKEN="",
        )
        with pytest.raises(RuntimeError, match="PAWAPAY_TOKEN"):
            check_deposit_status("deposit-missing-token")
        with pytest.raises(RuntimeError, match="PAWAPAY_TOKEN"):
            initiate_deposit(
                amount=1000,
                currency="XAF",
                country_code="GAB",
                correspondent="AIRTEL_GAB",
                phone_number="07123456",
            )


def test_search_timeout_notifies_and_releases_benefit(app, client):
    token, _ = _auth_via_otp(client, "+24107770001", "Search", "Owner")
    headers = {"Authorization": f"Bearer {token}"}
    response = client.post(
        "/api/rides",
        headers=headers,
        json={
            "departureLat": 0.4,
            "departureLng": 9.4,
            "departureAddress": "Départ",
            "destinationLat": 0.5,
            "destinationLng": 9.5,
            "destinationAddress": "Arrivée",
            "price": 1500,
        },
    )
    ride_id = response.get_json()["data"]["id"]
    sio_client = socketio.test_client(app, auth={"token": token})
    connected = sio_client.get_received()
    connected_event = next(event for event in connected if event["name"] == "connected")
    assert ride_id in connected_event["args"][0]["activeRideIds"]

    with app.app_context():
        ride = db.session.get(Ride, ride_id)
        ride.created_at = utcnow() - timedelta(seconds=301)
        db.session.commit()

    from app.tools.background_jobs import expire_searching_rides

    assert expire_searching_rides(app) == 1
    with app.app_context():
        ride = db.session.get(Ride, ride_id)
        assert ride.status == "expired"
        assert ride.benefit.promo_discount == 500
        assert ride.benefit.status == "released"
    assert any(event["name"] == "ride:expired" for event in sio_client.get_received())
    sio_client.disconnect()


def test_driver_vehicle_management_and_history(client, app):
    token, user_data = _auth_via_otp(client, "+24107770002", "Driver", "Test")
    headers = {"Authorization": f"Bearer {token}"}
    registered = client.post(
        "/api/drivers/register",
        headers=headers,
        json={
            "vehicleType": "voiture",
            "brand": "Toyota",
            "model": "Corolla",
            "color": "Blanc",
            "plate": "TEST-001",
        },
    )
    assert registered.status_code == 201
    added = client.post(
        "/api/drivers/me/vehicles",
        headers=headers,
        json={
            "vehicleType": "moto",
            "brand": "Yamaha",
            "model": "X",
            "color": "Noir",
            "plate": "TEST-002",
        },
    )
    assert added.status_code == 201
    vehicle_id = added.get_json()["data"]["id"]
    assert added.get_json()["data"]["isActive"] is False
    activated = client.put(
        f"/api/drivers/me/vehicles/{vehicle_id}/activate", headers=headers
    )
    assert activated.status_code == 200
    assert activated.get_json()["data"]["activeVehicle"]["isActive"] is True
    assert client.get("/api/drivers/me", headers=headers).get_json()["data"]["vehicleType"] == "moto"

    with app.app_context():
        driver = Driver.query.filter_by(user_id=user_data["id"]).one()
        passenger = User(phone_number="+24107770003", first_name="Client")
        db.session.add(passenger)
        db.session.flush()
        ride = Ride(
            client_id=passenger.id,
            driver_id=driver.id,
            departure_lat=0.4,
            departure_lng=9.4,
            departure_address="Départ",
            destination_lat=0.5,
            destination_lng=9.5,
            destination_address="Arrivée",
            price=2000,
            agreed_price=2500,
            status="completed",
            is_paid=True,
            paid_amount=2000,
            platform_commission=375,
            paid_at=utcnow(),
        )
        db.session.add(ride)
        db.session.commit()

    history = client.get("/api/drivers/me/rides", headers=headers)
    assert history.status_code == 200
    assert history.get_json()["data"]["pagination"]["total"] == 1
    today = history.get_json()["data"]["statistics"]["today"]
    assert today["grossRevenue"] == 2500
    assert today["amountCollected"] == 2000
    assert today["netRevenue"] == 2125


def test_account_deletion_anonymizes_and_preserves_credit_history(client, app):
    token, user_data = _auth_via_otp(client, "+24107770004", "Delete", "Me")
    headers = {"Authorization": f"Bearer {token}"}
    sio_client = socketio.test_client(app, auth={"token": token})
    assert sio_client.is_connected()
    with app.app_context():
        db.session.add(
            UserCreditTransaction(
                user_id=user_data["id"],
                amount=500,
                source="referral_reward",
                reference_key="referral:test:referred",
            )
        )
        db.session.commit()

    deleted = client.delete("/api/users/me", headers=headers)
    assert deleted.status_code == 200
    assert not sio_client.is_connected()
    assert client.get("/api/users/me", headers=headers).status_code == 401
    with app.app_context():
        user = db.session.get(User, user_data["id"])
        assert user.is_active is False
        assert user.phone_number is None
        assert user.first_name == "Compte"
        assert UserCreditTransaction.query.filter_by(user_id=user.id).count() == 1


def test_referral_award_requires_paid_completed_ride_once(app, client):
    from app.tools.benefits import reward_completed_referral

    referrer_token, referrer_data = _auth_via_otp(
        client, "+24107770005", "Referrer", "Test"
    )
    summary = client.get(
        "/api/users/me/referral",
        headers={"Authorization": f"Bearer {referrer_token}"},
    )
    referral_code = summary.get_json()["data"]["referralCode"]
    sent = client.post("/api/auth/otp/send", json={"phoneNumber": "+24107770006"})
    assert sent.status_code == 200
    verified = client.post(
        "/api/auth/otp/verify",
        json={
            "phoneNumber": "+24107770006",
            "code": sent.get_json()["data"]["debugOtp"],
            "referralCode": referral_code,
        },
    )
    assert verified.status_code == 200

    with app.app_context():
        referred = User.query.filter_by(phone_number="+24107770006").one()
        referral = Referral.query.filter_by(referred_user_id=referred.id).one()
        assert referral.referrer_id == referrer_data["id"]
        ride = Ride(
            client_id=referred.id,
            departure_lat=0.4,
            departure_lng=9.4,
            departure_address="Départ",
            destination_lat=0.5,
            destination_lng=9.5,
            destination_address="Arrivée",
            price=1000,
            status="completed",
            is_paid=True,
            paid_at=utcnow(),
        )
        db.session.add(ride)
        db.session.flush()
        assert reward_completed_referral(ride) is True
        assert reward_completed_referral(ride) is False
        db.session.commit()
        assert (
            UserCreditTransaction.query.filter_by(source="referral_reward").count()
            == 2
        )


def test_stale_driver_is_removed_from_online_map(client, app):
    token, _ = _auth_via_otp(client, "+24107770007", "Online", "Driver")
    headers = {"Authorization": f"Bearer {token}"}
    registered = client.post(
        "/api/drivers/register",
        headers=headers,
        json={
            "vehicleType": "voiture",
            "brand": "Toyota",
            "model": "Yaris",
            "color": "Bleu",
            "plate": "TEST-003",
        },
    )
    assert registered.status_code == 201
    assert client.put(
        "/api/drivers/me/availability",
        headers=headers,
        json={"isAvailable": True},
    ).status_code == 200
    with app.app_context():
        driver = Driver.query.one()
        driver.last_location_at = utcnow() - timedelta(seconds=31)
        db.session.commit()

    from app.tools.background_jobs import set_stale_drivers_offline

    assert set_stale_drivers_offline(app) == 1
    with app.app_context():
        assert Driver.query.one().is_available is False


def test_password_reset_is_explicitly_unavailable(client):
    response = client.post("/api/auth/password/forgot", json={"email": "user@example.com"})
    assert response.status_code == 503
    assert response.get_json()["error"]["code"] == "PASSWORD_RESET_UNAVAILABLE"


def test_realtime_ride_offers_chat_cash_commission_and_wallet_recharge(app, client):
    passenger_token, passenger = _auth_via_otp(
        client, "+24107333333", "Alice", "Ndong"
    )
    driver_token, _ = _auth_via_otp(client, "+24107444444", "Marc", "Obiang")

    p_headers = {"Authorization": f"Bearer {passenger_token}"}
    d_headers = {"Authorization": f"Bearer {driver_token}"}

    # Enregistrement chauffeur voiture
    reg = client.post(
        "/api/drivers/register",
        headers=d_headers,
        json={
            "vehicleType": "voiture",
            "brand": "Toyota",
            "model": "Corolla",
            "color": "Gris",
            "plate": "1234-GA-01",
        },
    )
    assert reg.status_code == 201
    driver_id = reg.get_json()["data"]["id"]

    # Connexion Socket.IO passager + chauffeur
    # Note: SocketIOTestClient.__init__ appelle manager.initialize() qui réinitialise les rooms en mémoire
    sio_passenger = socketio.test_client(app, auth={"token": passenger_token})
    orig_init = socketio.server.manager.initialize
    socketio.server.manager.initialize = lambda: None
    try:
        sio_driver = socketio.test_client(app, auth={"token": driver_token})
    finally:
        socketio.server.manager.initialize = orig_init
    assert sio_passenger.is_connected()
    assert sio_driver.is_connected()
    sio_passenger.get_received()
    sio_driver.get_received()

    # Chauffeur passe EN LIGNE via Socket.IO
    sio_driver.emit(
        "driver:go_online",
        {"latitude": 0.4162, "longitude": 9.4673, "heading": 90},
    )
    p_events = [e["name"] for e in sio_passenger.get_received()]
    assert "driver:availability_changed" in p_events

    # Recherche chauffeurs proches
    nearby = client.get(
        "/api/drivers/nearby?lat=0.4162&lng=9.4673&radiusKm=6",
        headers=p_headers,
    )
    assert nearby.status_code == 200
    assert nearby.get_json()["data"]["count"] == 1

    # Passager crée une course -> chauffeur reçoit ride:new en temps réel
    ride_res = client.post(
        "/api/rides",
        headers=p_headers,
        json={
            "departureLat": 0.4165,
            "departureLng": 9.4675,
            "departureAddress": "Louis, Libreville",
            "destinationLat": 0.4400,
            "destinationLng": 9.4500,
            "destinationAddress": "Aéroport Léon-Mba",
            "rideType": "voiture",
            "price": 2000,
        },
    )
    assert ride_res.status_code == 201
    ride_id = ride_res.get_json()["data"]["id"]

    d_received = sio_driver.get_received()
    assert any(e["name"] == "ride:new" for e in d_received)

    # Passager rejoint la room de la course
    sio_passenger.emit("join_ride", {"rideId": ride_id})
    sio_passenger.get_received()

    # Chauffeur consulte courses disponibles à proximité et fait une contre-offre
    avail = client.get("/api/rides/available", headers=d_headers)
    assert avail.status_code == 200
    assert len(avail.get_json()["data"]["rides"]) == 1

    offer_res = client.post(
        f"/api/rides/{ride_id}/offers",
        headers=d_headers,
        json={"price": 2500, "arrivalMinutes": 4},
    )
    assert offer_res.status_code == 200
    offer_id = offer_res.get_json()["data"]["id"]

    p_received = sio_passenger.get_received()
    assert any(e["name"] == "ride:offer_received" for e in p_received)

    # Passager accepte l'offre
    accept_res = client.post(
        f"/api/rides/{ride_id}/offers/{offer_id}/accept",
        headers=p_headers,
    )
    assert accept_res.status_code == 200
    assert accept_res.get_json()["data"]["agreedPrice"] == 2500

    assert any(e["name"] == "ride:accepted" for e in sio_driver.get_received())

    # Suivi GPS temps réel pendant la course
    sio_driver.emit(
        "driver:location_update",
        {"latitude": 0.418, "longitude": 9.468, "rideId": ride_id},
    )
    assert any(e["name"] == "ride:driver_location" for e in sio_passenger.get_received())

    # Messagerie temps réel en course
    sio_passenger.emit(
        "ride:send_message",
        {"rideId": ride_id, "content": "Je suis devant la pharmacie"},
    )
    d_msgs = [e for e in sio_driver.get_received() if e["name"] == "ride:message"]
    assert len(d_msgs) == 1
    assert d_msgs[0]["args"][0]["content"] == "Je suis devant la pharmacie"

    # Machine à états de course : arrived -> start -> complete
    assert client.post(f"/api/rides/{ride_id}/arrived", headers=d_headers).status_code == 200
    assert client.post(f"/api/rides/{ride_id}/start", headers=d_headers).status_code == 200
    assert client.post(f"/api/rides/{ride_id}/complete", headers=d_headers).status_code == 200

    # La réduction de 500 XAF est compensée au chauffeur par Moovi.
    cash_res = client.post(f"/api/rides/{ride_id}/pay/cash", headers=d_headers)
    assert cash_res.status_code == 200
    cash_data = cash_res.get_json()["data"]
    assert cash_data["ride"]["platformCommission"] == 375.0
    assert cash_data["amountDue"] == 2000
    assert cash_data["grossAmount"] == 2500
    assert cash_data["discountAmount"] == 500
    assert cash_data["wallet"]["walletBalance"] == 5125.0

    # Notation de la course
    rate_res = client.post(
        f"/api/rides/{ride_id}/rate",
        headers=p_headers,
        json={"score": 5, "comment": "Très ponctuel !"},
    )
    assert rate_res.status_code == 201

    # Rechargement portefeuille PawaPay (simulation + polling statut)
    rech_res = client.post(
        "/api/wallet/recharge",
        headers=d_headers,
        json={
            "country": "GAB",
            "operatorCode": "AIRTEL_GAB",
            "amount": 10000,
            "phoneNumber": "077123456",
        },
    )
    assert rech_res.status_code == 201
    deposit_id = rech_res.get_json()["data"]["depositId"]

    status_res = client.get(
        f"/api/wallet/recharge/{deposit_id}/status", headers=d_headers
    )
    assert status_res.status_code == 200
    assert status_res.get_json()["data"]["walletBalance"] == 15125.0

    # Paiement Mobile Money (PawaPay) par le passager sur une 2e course
    ride2_res = client.post(
        "/api/rides",
        headers=p_headers,
        json={
            "departureLat": 0.4165,
            "departureLng": 9.4675,
            "departureAddress": "Centre-ville",
            "destinationLat": 0.4250,
            "destinationLng": 9.4750,
            "destinationAddress": "Batterie IV",
            "rideType": "voiture",
            "price": 3000,
        },
    )
    ride2_id = ride2_res.get_json()["data"]["id"]
    offer2 = client.post(
        f"/api/rides/{ride2_id}/offers", headers=d_headers, json={"price": 3000}
    ).get_json()["data"]["id"]
    client.post(f"/api/rides/{ride2_id}/offers/{offer2}/accept", headers=p_headers)

    # Le paiement Mobile Money n'est possible qu'une fois la course terminée.
    early = client.post(f"/api/rides/{ride2_id}/pay/mobile-money", headers=p_headers, json={})
    assert early.status_code == 409 and early.get_json()["error"]["code"] == "RIDE_NOT_COMPLETED"
    for step in ("arrived", "start", "complete"):
        assert client.post(f"/api/rides/{ride2_id}/{step}", headers=d_headers).status_code == 200

    countries = client.get("/api/payments/mobile-money/countries", headers=p_headers)
    assert countries.status_code == 200
    assert countries.get_json()["data"]["countries"][0]["code"] == "GAB"

    pc_init = client.post(
        f"/api/rides/{ride2_id}/pay/mobile-money",
        headers=p_headers,
        json={"phoneNumber": "066000000"},
    )
    assert pc_init.status_code == 201
    assert pc_init.get_json()["data"]["operator"]["code"] == "MOOV_GAB"
    tx_id = pc_init.get_json()["data"]["depositId"]

    pc_status = client.get(
        f"/api/payments/mobile-money/{tx_id}/status", headers=p_headers
    )
    assert pc_status.status_code == 200
    assert pc_status.get_json()["data"]["ride"]["isPaid"] is True
    # Commission (-450) prélevée à la fin de course, prix payé par Mobile Money
    # reversé au chauffeur (+3000) : 15125 - 450 + 3000.
    status_data = pc_status.get_json()["data"]
    assert status_data["status"] == "COMPLETED"
    wallet = client.get("/api/wallet", headers=d_headers).get_json()["data"]
    assert wallet["walletBalance"] == 17675.0

    sio_passenger.disconnect()
    sio_driver.disconnect()


def test_wallet_blocking_cancellation_notifications_and_webhooks(client):
    passenger_token, _ = _auth_via_otp(client, "+24107555555", "Claire", "Bongo")
    driver_token, _ = _auth_via_otp(client, "+24107666666", "Paul", "Nzamba")
    p_headers = {"Authorization": f"Bearer {passenger_token}"}
    d_headers = {"Authorization": f"Bearer {driver_token}"}

    # Estimation de prix
    est = client.post(
        "/api/rides/estimate",
        headers=p_headers,
        json={"distanceKm": 6.0},
    )
    assert est.status_code == 200
    assert len(est.get_json()["data"]["options"]) == 3

    # Inscription chauffeur
    reg = client.post(
        "/api/drivers/register",
        headers=d_headers,
        json={
            "vehicleType": "confort",
            "brand": "Toyota",
            "model": "RAV4",
            "color": "Blanc",
            "plate": "5678-GA-01",
        },
    )
    assert reg.status_code == 201

    # Course 1 annulée par le passager pendant la recherche
    r1 = client.post(
        "/api/rides",
        headers=p_headers,
        json={
            "departureLat": 0.416,
            "departureLng": 9.467,
            "departureAddress": "Mont-Bouët",
            "destinationLat": 0.430,
            "destinationLng": 9.455,
            "destinationAddress": "Glass",
            "rideType": "confort",
            "price": 3500,
        },
    )
    assert r1.status_code == 201
    r1_id = r1.get_json()["data"]["id"]
    cancel_res = client.post(
        f"/api/rides/{r1_id}/cancel",
        headers=p_headers,
        json={"reason": "Changement de plan"},
    )
    assert cancel_res.status_code == 200
    assert cancel_res.get_json()["data"]["status"] == "cancelled"

    # La commission dépasse le solde malgré la subvention promotionnelle de 500 XAF.
    r2 = client.post(
        "/api/rides",
        headers=p_headers,
        json={
            "departureLat": 0.416,
            "departureLng": 9.467,
            "departureAddress": "Mont-Bouët",
            "destinationLat": 0.490,
            "destinationLng": 9.520,
            "destinationAddress": "Ntoum",
            "rideType": "confort",
            "price": 40000,
        },
    )
    assert r2.status_code == 201
    r2_id = r2.get_json()["data"]["id"]
    off2 = client.post(
        f"/api/rides/{r2_id}/offers", headers=d_headers, json={"price": 40000}
    ).get_json()["data"]["id"]
    client.post(f"/api/rides/{r2_id}/offers/{off2}/accept", headers=p_headers)
    client.post(f"/api/rides/{r2_id}/arrived", headers=d_headers)
    client.post(f"/api/rides/{r2_id}/start", headers=d_headers)
    client.post(f"/api/rides/{r2_id}/complete", headers=d_headers)

    cash2 = client.post(f"/api/rides/{r2_id}/pay/cash", headers=d_headers)
    assert cash2.status_code == 200
    wallet = cash2.get_json()["data"]["wallet"]
    assert wallet["walletBalance"] == -500.0
    assert wallet["isWalletBlocked"] is True
    assert wallet["isAvailable"] is False

    # Impossible de repasser en ligne tant que bloqué
    avail_fail = client.put(
        "/api/drivers/me/availability",
        headers=d_headers,
        json={"isAvailable": True},
    )
    assert avail_fail.status_code == 402

    # Recharge PawaPay + Webhook serveur-à-serveur débloque le compte
    rech = client.post(
        "/api/wallet/recharge",
        headers=d_headers,
        json={
            "country": "GAB",
            "operatorCode": "MOOV_GAB",
            "amount": 5000,
            "phoneNumber": "062000000",
        },
    )
    dep_id = rech.get_json()["data"]["depositId"]
    wh = client.post(
        "/api/webhooks/pawapay",
        json={"depositId": dep_id, "status": "COMPLETED"},
    )
    assert wh.status_code == 200

    avail_ok = client.put(
        "/api/drivers/me/availability",
        headers=d_headers,
        json={"isAvailable": True, "latitude": 0.416, "longitude": 9.467},
    )
    assert avail_ok.status_code == 200
    assert avail_ok.get_json()["data"]["walletBalance"] == 4500.0
    assert avail_ok.get_json()["data"]["isWalletBlocked"] is False

    # Notifications + destinations récentes
    notifs = client.get("/api/notifications", headers=p_headers)
    assert notifs.status_code == 200
    assert notifs.get_json()["data"]["unreadCount"] >= 1
    assert client.post("/api/notifications/read-all", headers=p_headers).status_code == 200

    recent = client.get("/api/users/me/recent-destinations", headers=p_headers)
    assert recent.status_code == 200
    assert len(recent.get_json()["data"]["destinations"]) == 2


def test_rest_state_changes_sync_socket_rooms_without_duplicates(app, client):
    """Parcours de l'app mobile : socket ouvert dès la connexion, actions en REST."""
    passenger_token, _ = _auth_via_otp(client, "+24107555551", "Awa", "Nze")
    driver_token, _ = _auth_via_otp(client, "+24107555552", "Paul", "Mba")
    p_headers = {"Authorization": f"Bearer {passenger_token}"}
    d_headers = {"Authorization": f"Bearer {driver_token}"}

    # Les deux sockets sont ouverts AVANT l'inscription chauffeur.
    sio_passenger = socketio.test_client(app, auth={"token": passenger_token})
    orig_init = socketio.server.manager.initialize
    socketio.server.manager.initialize = lambda: None
    try:
        sio_driver = socketio.test_client(app, auth={"token": driver_token})
    finally:
        socketio.server.manager.initialize = orig_init
    assert sio_passenger.is_connected() and sio_driver.is_connected()

    reg = client.post(
        "/api/drivers/register",
        headers=d_headers,
        json={"vehicleType": "voiture", "brand": "Kia", "model": "Rio",
              "color": "Bleu", "plate": "GA-555-AA"},
    )
    assert reg.status_code == 201
    driver_id = reg.get_json()["data"]["id"]

    # Passage en ligne via REST -> le socket rejoint online_drivers côté serveur.
    online = client.put(
        "/api/drivers/me/availability",
        headers=d_headers,
        json={"isAvailable": True, "latitude": 0.41, "longitude": 9.46},
    )
    assert online.status_code == 200
    sio_passenger.get_received()
    sio_driver.get_received()

    ride = client.post(
        "/api/rides",
        headers=p_headers,
        json={"departureLat": 0.41, "departureLng": 9.46, "destinationLat": 0.45,
              "destinationLng": 9.43, "departureAddress": "A",
              "destinationAddress": "B", "price": 2000},
    )
    assert ride.status_code == 201
    ride_id = ride.get_json()["data"]["id"]
    new_events = [e for e in sio_driver.get_received() if e["name"] == "ride:new"]
    assert len(new_events) == 1  # une seule fois malgré deux rooms chauffeur

    offer = client.post(f"/api/rides/{ride_id}/offers", headers=d_headers, json={"price": 2200})
    assert offer.status_code == 200
    received = [e for e in sio_passenger.get_received() if e["name"] == "ride:offer_received"]
    assert len(received) == 1  # room course + room utilisateur dédoublonnées

    accept = client.post(
        f"/api/rides/{ride_id}/offers/{offer.get_json()['data']['id']}/accept",
        headers=p_headers,
    )
    assert accept.status_code == 200
    accepted = [e for e in sio_driver.get_received() if e["name"] == "ride:accepted"]
    assert len(accepted) == 1

    # Position via socket -> le passager suit le chauffeur dans la room course.
    sio_driver.emit("driver:location_update", {"latitude": 0.412, "longitude": 9.461})
    locations = [e for e in sio_passenger.get_received() if e["name"] == "ride:driver_location"]
    assert locations and locations[-1]["args"][0]["driverId"] == driver_id

    assert client.post(f"/api/rides/{ride_id}/arrived", headers=d_headers).status_code == 200
    changed = [e for e in sio_passenger.get_received() if e["name"] == "ride:status_changed"]
    assert len(changed) == 1 and changed[0]["args"][0]["status"] == "driver_arrived"

    msg = client.post(f"/api/rides/{ride_id}/messages", headers=p_headers,
                      json={"content": "J'arrive"})
    assert msg.status_code == 201
    d_events = sio_driver.get_received()
    assert len([e for e in d_events if e["name"] == "ride:message"]) == 1
    assert any(e["name"] == "notification:new" for e in d_events)

    # Hors ligne via REST -> plus de ride:new pour ce chauffeur.
    client.post(f"/api/rides/{ride_id}/cancel", headers=p_headers, json={})
    assert client.put("/api/drivers/me/availability", headers=d_headers,
                      json={"isAvailable": False}).status_code == 200
    sio_driver.get_received()
    ride2 = client.post(
        "/api/rides",
        headers=p_headers,
        json={"departureLat": 0.41, "departureLng": 9.46, "destinationLat": 0.45,
              "destinationLng": 9.43, "departureAddress": "A",
              "destinationAddress": "B", "price": 2000},
    )
    assert ride2.status_code == 201
    assert not [e for e in sio_driver.get_received() if e["name"] == "ride:new"]

    sio_driver.disconnect()
    sio_passenger.disconnect()


def test_admin_console_and_otp_code_hidden_when_debug_disabled(app, client):
    page = client.get("/admin")
    assert page.status_code == 200
    assert b"Moovi" in page.data and page.headers["X-Frame-Options"] == "DENY"

    app.config["OTP_DEBUG_RETURN_CODE"] = False
    res = client.post("/api/auth/otp/send", json={"phoneNumber": "+24107000999"})
    assert res.status_code == 200
    assert "debugOtp" not in (res.get_json()["data"] or {})


def test_unverified_driver_cannot_go_online_when_verification_required(app, client):
    app.config["REQUIRE_DRIVER_VERIFICATION"] = True
    token, _ = _auth_via_otp(client, "+24107000888", "Jean", "Test")
    headers = {"Authorization": f"Bearer {token}"}
    reg = client.post("/api/drivers/register", headers=headers, json={
        "vehicleType": "voiture", "brand": "Kia", "model": "Rio",
        "color": "Gris", "plate": "GA-888-ZZ",
    })
    assert reg.status_code in (200, 201)
    res = client.put("/api/drivers/me/availability", headers=headers,
                     json={"isAvailable": True, "latitude": 0.41, "longitude": 9.46})
    assert res.status_code >= 400


def _driver(client, phone, vehicle="voiture", plate="GA-1", lat=0.41, lng=9.46):
    token, _ = _auth_via_otp(client, phone, "Chauffeur", phone[-3:])
    headers = {"Authorization": f"Bearer {token}"}
    reg = client.post("/api/drivers/register", headers=headers, json={
        "vehicleType": vehicle, "brand": "Kia", "model": "Rio", "color": "Gris", "plate": plate,
    })
    assert reg.status_code == 201, reg.get_json()
    online = client.put("/api/drivers/me/availability", headers=headers,
                        json={"isAvailable": True, "latitude": lat, "longitude": lng})
    assert online.status_code == 200, online.get_json()
    return token, headers, reg.get_json()["data"]["id"]


def _new_ride(client, headers, price=3000, ride_type="voiture"):
    res = client.post("/api/rides", headers=headers, json={
        "departureLat": 0.41, "departureLng": 9.46, "destinationLat": 0.45,
        "destinationLng": 9.43, "departureAddress": "A", "destinationAddress": "B",
        "price": price, "rideType": ride_type,
    })
    assert res.status_code == 201, res.get_json()
    return res.get_json()["data"]["id"]


def _code(res):
    return (res.get_json().get("error") or {}).get("code")


def test_audit_ride_privacy_eligibility_and_payments(app, client):
    p_token, _ = _auth_via_otp(client, "+24107600001", "Awa", "Nze")
    p = {"Authorization": f"Bearer {p_token}"}
    p2_token, _ = _auth_via_otp(client, "+24107600002", "Lea", "Obame")
    p2 = {"Authorization": f"Bearer {p2_token}"}
    _, d1, d1_id = _driver(client, "+24107600011", plate="GA-11")
    _, d2, _ = _driver(client, "+24107600012", vehicle="moto", plate="GA-12")
    d3_token, d3, _ = _driver(client, "+24107600013", plate="GA-13")

    ride_id = _new_ride(client, p)
    # Mauvaise catégorie de véhicule
    res = client.post(f"/api/rides/{ride_id}/offers", headers=d2, json={"price": 3000})
    assert res.status_code == 403 and _code(res) == "VEHICLE_TYPE_MISMATCH"
    # Un chauffeur candidat ne voit pas le téléphone du passager
    seen = client.get(f"/api/rides/{ride_id}", headers=d1).get_json()["data"]
    assert "clientPhone" not in seen and seen["status"] == "searching"
    available = client.get("/api/rides/available", headers=d1).get_json()["data"]["rides"]
    assert available and all("clientPhone" not in r for r in available)

    o1 = client.post(f"/api/rides/{ride_id}/offers", headers=d1, json={"price": 3000.7})
    assert o1.status_code == 200 and o1.get_json()["data"]["price"] == 3001
    assert client.post(f"/api/rides/{ride_id}/offers", headers=d3, json={"price": 2900}).status_code == 200
    # Les concurrents ne voient pas les offres des autres
    d1_offers = client.get(f"/api/rides/{ride_id}/offers", headers=d1).get_json()["data"]["offers"]
    assert len(d1_offers) == 1
    assert len(client.get(f"/api/rides/{ride_id}/offers", headers=p).get_json()["data"]["offers"]) == 2

    # Un chauffeur non attribué ne peut pas rejoindre la salle de la course
    sio_d3 = socketio.test_client(app, auth={"token": d3_token})
    sio_d3.get_received()
    sio_d3.emit("join_ride", {"rideId": ride_id})
    assert any(e["name"] == "error" for e in sio_d3.get_received())
    sio_d3.disconnect()

    offer1 = o1.get_json()["data"]["id"]
    assert client.post(f"/api/rides/{ride_id}/offers/{offer1}/accept", headers=p).status_code == 200

    # Chauffeur déjà occupé : pas de nouvelle offre
    other = _new_ride(client, p2)
    res = client.post(f"/api/rides/{other}/offers", headers=d1, json={"price": 3000})
    assert res.status_code == 409 and _code(res) == "DRIVER_BUSY"

    # Paiement Mobile Money : uniquement à la fin, en XAF
    for step in ("arrived", "start"):
        assert client.post(f"/api/rides/{ride_id}/{step}", headers=d1).status_code == 200
    before = client.get("/api/wallet", headers=d1).get_json()["data"]["walletBalance"]
    assert client.post(f"/api/rides/{ride_id}/complete", headers=d1).status_code == 200
    after = client.get("/api/wallet", headers=d1).get_json()["data"]["walletBalance"]
    assert after == round(before - 3001 * 0.15, 2)  # commission prélevée dès la fin

    res = client.post(f"/api/rides/{ride_id}/pay/mobile-money", headers=p,
                      json={"country": "COD", "operatorCode": "ORANGE_COD", "phoneNumber": "0812345678"})
    assert res.status_code == 422 and _code(res) == "UNSUPPORTED_COUNTRY"

    first = client.post(f"/api/rides/{ride_id}/pay/mobile-money", headers=p, json={"phoneNumber": "077000001"})
    assert first.status_code == 201
    deposit_id = first.get_json()["data"]["depositId"]
    again = client.post(f"/api/rides/{ride_id}/pay/mobile-money", headers=p, json={"phoneNumber": "077000001"})
    assert again.status_code == 409 and _code(again) == "PAYMENT_PENDING"
    cash = client.post(f"/api/rides/{ride_id}/pay/cash", headers=d1)
    assert cash.status_code == 409 and _code(cash) == "PAYMENT_PENDING"

    status = client.get(f"/api/payments/mobile-money/{deposit_id}/status", headers=p).get_json()["data"]
    assert status["status"] == "COMPLETED" and status["ride"]["isPaid"] is True
    final = client.get("/api/wallet", headers=d1).get_json()["data"]["walletBalance"]
    assert final == round(after + 3001, 2)  # prix reversé au chauffeur

    # Un second dépôt confirmé après coup est marqué « en double », jamais recompté
    from app.views.payments import finalize_ride_payment

    with app.app_context():
        dup = RidePayment(id="dep-dup", ride_id=ride_id, payer_user_id="x", amount=3001)
        db.session.add(dup)
        db.session.commit()
        assert finalize_ride_payment(db.session.get(RidePayment, "dep-dup"), "COMPLETED") == "duplicate"
    assert client.get("/api/wallet", headers=d1).get_json()["data"]["walletBalance"] == final

    # Carte passager : aucune donnée personnelle des chauffeurs, rayon borné
    nearby = client.get("/api/drivers/nearby?lat=0.41&lng=9.46&radiusKm=100000", headers=p).get_json()["data"]
    assert nearby["radiusKm"] == 20.0
    assert nearby["drivers"] and all(
        "phoneNumber" not in d and "walletBalance" not in d for d in nearby["drivers"]
    )


def test_audit_phone_change_otp_lockout_and_reconciliation(app, client):
    token, _ = _auth_via_otp(client, "+24107600021", "Marc", "Ella")
    h = {"Authorization": f"Bearer {token}"}
    res = client.patch("/api/users/me", headers=h, json={"phoneNumber": "+24107600099"})
    assert res.status_code == 403 and _code(res) == "PHONE_REQUIRES_OTP"
    send = client.post("/api/auth/otp/send", json={"phoneNumber": "+24107600099"}).get_json()["data"]
    res = client.patch("/api/users/me", headers=h,
                       json={"phoneNumber": "+24107600099", "otpCode": send["debugOtp"]})
    assert res.status_code == 200, res.get_json()

    reg = client.post("/api/auth/register", json={
        "email": "x@test.ga", "password": "secret123", "phoneNumber": "+24107600098"})
    assert reg.status_code == 422 and _code(reg) == "PHONE_REQUIRES_OTP"

    # 10 codes faux sur un numéro : verrouillage, même avec un nouveau code
    from app.extensions import limiter

    phone = "+24107600031"
    app.config["OTP_RESEND_COOLDOWN_SECONDS"] = 0
    limiter.reset()
    for _ in range(2):
        client.post("/api/auth/otp/send", json={"phoneNumber": phone})
        for _ in range(5):
            client.post("/api/auth/otp/verify", json={"phoneNumber": phone, "code": "000000"})
    limiter.reset()  # la limite par IP ne doit pas masquer le verrou par numéro
    good = client.post("/api/auth/otp/send", json={"phoneNumber": phone}).get_json()["data"]["debugOtp"]
    locked = client.post("/api/auth/otp/verify", json={"phoneNumber": phone, "code": good})
    assert locked.status_code == 429 and _code(locked) == "OTP_LOCKED"

    # Rapprochement : un dépôt resté en attente est soldé par la tâche de fond
    p_token, _ = _auth_via_otp(client, "+24107600041", "Ines", "Mve")
    p = {"Authorization": f"Bearer {p_token}"}
    _, d, _ = _driver(client, "+24107600042", plate="GA-42")
    ride_id = _new_ride(client, p, price=2000)
    offer = client.post(f"/api/rides/{ride_id}/offers", headers=d, json={"price": 2000}).get_json()["data"]["id"]
    client.post(f"/api/rides/{ride_id}/offers/{offer}/accept", headers=p)
    for step in ("arrived", "start", "complete"):
        client.post(f"/api/rides/{ride_id}/{step}", headers=d)
    dep = client.post(f"/api/rides/{ride_id}/pay/mobile-money", headers=p, json={}).get_json()["data"]["depositId"]
    from datetime import timedelta
    from app.models.user import utcnow
    from app.tools.background_jobs import reconcile_pending_deposits

    with app.app_context():
        db.session.get(RidePayment, dep).created_at = utcnow() - timedelta(minutes=5)
        db.session.commit()
    assert reconcile_pending_deposits(app) == 1
    assert client.get(f"/api/rides/{ride_id}", headers=p).get_json()["data"]["isPaid"] is True


def _admin_headers(app, client):
    from app.tools.auth_helpers import hash_secret

    with app.app_context():
        if not User.query.filter_by(email="root@moovi.test").first():
            db.session.add(User(email="root@moovi.test", password_hash=hash_secret("Admin1234!"),
                                first_name="Root", last_name="Admin", role="admin"))
            db.session.commit()
    res = client.post("/api/auth/login", json={"email": "root@moovi.test", "password": "Admin1234!"})
    assert res.status_code == 200, res.get_json()
    return {"Authorization": f"Bearer {res.get_json()['data']['accessToken']}"}


def test_admin_platform_endpoints(app, client):
    admin = _admin_headers(app, client)
    p_token, passenger = _auth_via_otp(client, "+24107700001", "Nina", "Ondo")
    p = {"Authorization": f"Bearer {p_token}"}
    _, d, driver_id = _driver(client, "+24107700002", plate="GA-77")

    # Une course complète, réglée en espèces
    ride_id = _new_ride(client, p, price=2500)
    offer = client.post(f"/api/rides/{ride_id}/offers", headers=d, json={"price": 2500}).get_json()["data"]["id"]
    client.post(f"/api/rides/{ride_id}/offers/{offer}/accept", headers=p)
    for step in ("arrived", "start", "complete"):
        client.post(f"/api/rides/{ride_id}/{step}", headers=d)
    assert client.post(f"/api/rides/{ride_id}/pay/cash", headers=d).status_code == 200

    # Accès refusé aux non-administrateurs
    assert client.get("/api/admin/overview", headers=p).status_code == 403

    ov = client.get("/api/admin/overview?days=7", headers=admin).get_json()["data"]
    assert ov["rides"]["total"] >= 1 and len(ov["series"]) == 7
    assert ov["money"]["commission"] >= 375 and "alerts" in ov

    users = client.get("/api/admin/users?q=Nina", headers=admin).get_json()["data"]
    assert users["pagination"]["total"] == 1
    detail = client.get(f"/api/admin/users/{passenger['id']}", headers=admin).get_json()["data"]
    assert detail["rides"][0]["id"] == ride_id
    assert detail["totalSpent"] == detail["rides"][0]["paidAmount"]  # remise 1re course comprise

    drivers = client.get("/api/admin/drivers?q=GA-77&online=true", headers=admin).get_json()["data"]
    assert drivers["drivers"][0]["id"] == driver_id

    rides = client.get("/api/admin/rides?status=completed&q=Nina", headers=admin).get_json()["data"]
    assert rides["rides"][0]["id"] == ride_id
    full = client.get(f"/api/admin/rides/{ride_id}", headers=admin).get_json()["data"]
    assert full["client"]["fullname"] and full["walletTransactions"]

    txs = client.get(f"/api/admin/drivers/{driver_id}/transactions", headers=admin).get_json()["data"]
    assert any(t["type"] == "commission" for t in txs["transactions"])
    assert client.get("/api/admin/wallet-transactions?type=commission", headers=admin).status_code == 200
    assert client.get("/api/admin/vehicles", headers=admin).get_json()["data"]["vehicles"]
    assert client.get("/api/admin/payments", headers=admin).status_code == 200
    assert client.get("/api/admin/settings", headers=admin).get_json()["data"]["commissionRate"] == 0.15
    assert client.post("/api/admin/promo-codes", headers=admin, json={"code": "TEST500"}).status_code == 201
    promos = client.get("/api/admin/promo-codes", headers=admin).get_json()["data"]["promoCodes"]
    assert promos[0]["code"] == "TEST500" and promos[0]["usedCount"] == 0

    # Ajustement du portefeuille : solde négatif ⇒ chauffeur bloqué et hors ligne
    adj = client.post(f"/api/admin/drivers/{driver_id}/wallet-adjustment", headers=admin,
                      json={"amount": -100000, "reason": "Régularisation test"})
    assert adj.status_code == 200
    body = adj.get_json()["data"]
    assert body["isWalletBlocked"] is True and body["isAvailable"] is False
    assert client.post(f"/api/admin/drivers/{driver_id}/wallet-adjustment", headers=admin,
                       json={"amount": 5, "reason": ""}).status_code == 422

    # Suspension : jetons refusés, puis réactivation
    sus = client.post(f"/api/admin/users/{passenger['id']}/status", headers=admin,
                      json={"isActive": False, "reason": "Fraude"})
    assert sus.status_code == 200
    assert client.get("/api/auth/me", headers=p).status_code in (401, 403)
    assert client.post(f"/api/admin/users/{passenger['id']}/status", headers=admin,
                       json={"isActive": True}).status_code == 200

    # Notification ciblée + historique
    sent = client.post("/api/admin/notifications", headers=admin,
                       json={"audience": "passengers", "title": "Info", "body": "Bonjour"})
    assert sent.status_code == 200 and sent.get_json()["data"]["sent"] >= 1
    hist = client.get("/api/admin/notifications", headers=admin).get_json()["data"]["notifications"]
    assert hist[0]["title"] == "Info"

    # Paiement en double : marquage remboursé
    with app.app_context():
        db.session.add(RidePayment(id="dup-admin", ride_id=ride_id, payer_user_id=passenger["id"],
                                   amount=2500, status="duplicate"))
        db.session.commit()
    ref = client.post("/api/admin/payments/dup-admin/refunded", headers=admin, json={"note": "OK"})
    assert ref.status_code == 200 and ref.get_json()["data"]["status"] == "refunded"


def test_admin_drivers_map_and_live_positions(app, client):
    admin = _admin_headers(app, client)
    admin_token = admin["Authorization"].split()[1]
    p_token, _ = _auth_via_otp(client, "+24107900001", "Ines", "Map")
    p = {"Authorization": f"Bearer {p_token}"}
    _, d_free, free_id = _driver(client, "+24107900002", plate="GA-901")
    _, d_busy, busy_id = _driver(client, "+24107900003", plate="GA-902", lat=0.42, lng=9.45)
    _, d_off, off_id = _driver(client, "+24107900004", plate="GA-903")
    client.put("/api/drivers/me/availability", headers=d_off, json={"isAvailable": False})

    ride_id = _new_ride(client, p)
    offer = client.post(f"/api/rides/{ride_id}/offers", headers=d_busy, json={"price": 3000}).get_json()["data"]["id"]
    client.post(f"/api/rides/{ride_id}/offers/{offer}/accept", headers=p)

    assert client.get("/api/admin/drivers/map", headers=p).status_code == 403
    data = client.get("/api/admin/drivers/map", headers=admin).get_json()["data"]
    states = {d["id"]: d["state"] for d in data["drivers"]}
    assert states[free_id] == "available" and states[busy_id] == "busy"
    assert off_id not in states  # hors ligne masqués par défaut
    busy = next(d for d in data["drivers"] if d["id"] == busy_id)
    assert busy["ride"]["id"] == ride_id and busy["latitude"] == 0.42
    everyone = client.get("/api/admin/drivers/map?scope=all", headers=admin).get_json()["data"]
    assert {d["id"]: d["state"] for d in everyone["drivers"]}[off_id] == "offline"
    assert everyone["counts"]["offline"] >= 1

    # Le back-office reçoit en direct la position de tous les chauffeurs,
    # y compris hors ligne (pas la carte passagers).
    sio_admin = socketio.test_client(app, auth={"token": admin_token})
    sio_passenger = socketio.test_client(app, auth={"token": p_token})
    sio_admin.get_received()
    sio_passenger.get_received()
    client.put("/api/drivers/me/location", headers=d_off, json={"latitude": 0.43, "longitude": 9.47})
    admin_events = [e for e in sio_admin.get_received() if e["name"] == "admin:driver_update"]
    assert len(admin_events) == 1
    entry = admin_events[0]["args"][0]
    # Fiche complète : la carte n'a besoin d'aucune requête.
    assert entry["id"] == off_id and entry["state"] == "offline" and entry["plate"] == "GA-903"
    assert entry["latitude"] == 0.43 and entry["name"]
    assert not [e for e in sio_passenger.get_received() if e["name"] == "driver:location_updated"]
    client.put("/api/drivers/me/location", headers=d_busy, json={"latitude": 0.415, "longitude": 9.455})
    busy_update = [e for e in sio_admin.get_received() if e["name"] == "admin:driver_update"]
    assert len(busy_update) == 1 and busy_update[0]["args"][0]["state"] == "busy"
    assert busy_update[0]["args"][0]["ride"]["id"] == ride_id
    sio_admin.disconnect()
    sio_passenger.disconnect()


def test_ride_events_reach_admins(app, client):
    admin = _admin_headers(app, client)
    admin_token = admin["Authorization"].split()[1]
    p_token, _ = _auth_via_otp(client, "+24107910001", "Rita", "Live")
    p = {"Authorization": f"Bearer {p_token}"}
    _, d, driver_id = _driver(client, "+24107910002", plate="GA-991")
    sio_admin = socketio.test_client(app, auth={"token": admin_token})
    sio_admin.get_received()
    ride_id = _new_ride(client, p)
    offer = client.post(f"/api/rides/{ride_id}/offers", headers=d, json={"price": 3000}).get_json()["data"]["id"]
    client.post(f"/api/rides/{ride_id}/offers/{offer}/accept", headers=p)
    client.post(f"/api/rides/{ride_id}/arrived", headers=d)
    client.post(f"/api/rides/{ride_id}/cancel", headers=p, json={"reason": "test"})
    names = [e["name"] for e in sio_admin.get_received()]
    assert names.count("ride:accepted") == 1
    assert names.count("ride:status_changed") == 1
    assert names.count("ride:cancelled") == 1
    sio_admin.disconnect()
