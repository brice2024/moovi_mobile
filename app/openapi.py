"""Génération OpenAPI à partir des routes Flask enregistrées."""

import re
from typing import Any

from flask import Flask, current_app, jsonify
from flask_swagger_ui import get_swaggerui_blueprint
from werkzeug.routing import Rule

_DOCS_PREFIX = "/api/docs"
_OPENAPI_URL = "/api/openapi.json"

_SUMMARIES = {
    "index": "Accueil de l’API",
    "health_check": "Vérifier l’état de l’API",
    "send_otp": "Envoyer un code OTP",
    "resend_otp": "Renvoyer un code OTP",
    "verify_otp": "Vérifier le code OTP et se connecter",
    "register_email": "Créer un compte par email",
    "login_email": "Se connecter par email ou téléphone",
    "request_password_reset": "Demander une réinitialisation de mot de passe",
    "reset_password": "Réinitialiser le mot de passe",
    "refresh_token": "Renouveler le jeton d’accès",
    "logout": "Fermer la session",
    "auth_me": "Lire le compte connecté",
    "get_profile": "Lire le profil utilisateur",
    "update_profile": "Modifier le profil utilisateur",
    "upload_avatar": "Téléverser un avatar",
    "delete_avatar": "Supprimer l’avatar",
    "delete_my_account": "Désactiver et anonymiser le compte",
    "get_my_rides": "Lister l’historique passager",
    "get_referral_summary": "Lire le code de parrainage et les crédits",
    "get_recent_destinations": "Lister les destinations récentes",
    "register_device_token": "Enregistrer un jeton de notification",
    "register_or_update_driver": "Inscrire ou modifier le profil chauffeur",
    "get_my_driver_profile": "Lire le profil chauffeur",
    "get_my_driver_rides": "Lire l’historique et les statistiques chauffeur",
    "list_my_vehicles": "Lister les véhicules du chauffeur",
    "add_vehicle": "Ajouter un véhicule",
    "select_active_vehicle": "Activer un véhicule",
    "get_my_documents": "Lister les documents chauffeur",
    "upload_driver_document": "Téléverser un document chauffeur",
    "update_availability": "Modifier la disponibilité chauffeur",
    "update_location": "Mettre à jour la position chauffeur",
    "get_nearby_drivers": "Rechercher les chauffeurs proches",
    "estimate_ride": "Estimer le prix d’une course",
    "create_ride": "Créer une course",
    "get_active_ride": "Lire la course active",
    "get_available_rides": "Lister les courses disponibles",
    "get_ride_detail": "Lire une course",
    "list_ride_offers": "Lister les offres d’une course",
    "submit_ride_offer": "Proposer un prix pour une course",
    "accept_offer": "Accepter une offre",
    "mark_driver_arrived": "Signaler l’arrivée du chauffeur",
    "start_ride": "Démarrer une course",
    "complete_ride": "Terminer une course",
    "cancel_ride": "Annuler une course",
    "rate_ride": "Évaluer une course",
    "confirm_cash_payment": "Confirmer le paiement en espèces",
    "list_mobile_money_countries": "Lister les opérateurs Mobile Money (passager)",
    "initiate_mobile_money_ride_payment": "Payer une course par Mobile Money (PawaPay)",
    "check_mobile_money_ride_payment": "Vérifier le paiement Mobile Money d’une course",
    "pawapay_webhook": "Recevoir un webhook PawaPay",
    "list_supported_countries": "Lister les pays et opérateurs pris en charge",
    "get_wallet": "Lire le portefeuille chauffeur",
    "recharge_wallet": "Initier une recharge du portefeuille",
    "check_recharge_status": "Vérifier une recharge",
    "autocomplete": "Rechercher une adresse Google Places",
    "details": "Lire les détails d’un lieu",
    "route_compute": "Calculer un itinéraire",
    "list_notifications": "Lister les notifications",
    "mark_read": "Marquer une notification comme lue",
    "mark_all_read": "Marquer toutes les notifications comme lues",
    "list_ride_messages": "Lister les messages d’une course",
    "send_ride_message": "Envoyer un message dans une course",
    "list_promo_codes": "Lister les codes promotionnels",
    "create_promo_code": "Créer un code promotionnel",
    "update_promo_code": "Activer ou désactiver un code promotionnel",
    "list_drivers": "Lister les chauffeurs",
    "get_driver_detail": "Lire le profil d’un chauffeur",
    "review_driver_document": "Examiner un document chauffeur",
    "verify_driver_bulk": "Valider ou rejeter un dossier chauffeur",
    "review_driver_vehicle": "Examiner un véhicule",
    "get_stats": "Lire les statistiques administrateur",
    "seed_test_drivers_endpoint": "Créer des chauffeurs de test",
    "serve_driver_file": "Télécharger un fichier chauffeur protégé",
    "serve_file": "Télécharger un fichier public",
}

_BODY_DESCRIPTIONS = {
    "send_otp": "Fournir phoneNumber (ou phone).",
    "resend_otp": "Fournir phoneNumber (ou phone).",
    "verify_otp": "Fournir phoneNumber et code à 6 chiffres; referralCode est facultatif.",
    "register_email": "Fournir email et password; fullname ou firstName/lastName sont facultatifs.",
    "login_email": "Fournir email (ou identifier/phoneNumber) et password.",
    "create_ride": "Fournir départ, destination et éventuellement rideType, price et promoCode.",
    "submit_ride_offer": "Fournir price et éventuellement arrivalMinutes/message.",
    "add_vehicle": "Fournir vehicleType, brand, model, color et plate.",
    "update_availability": "Fournir isAvailable et éventuellement latitude/longitude.",
    "update_location": "Fournir latitude et longitude.",
    "recharge_wallet": "Fournir country, operatorCode, amount et phoneNumber.",
    "route_compute": "Fournir originLat, originLng, destinationLat et destinationLng.",
    "create_promo_code": "Fournir code et éventuellement discountAmount, maxUses et expiresAt.",
}

_PUBLIC_ENDPOINTS = {
    "health.index",
    "health.health_check",
    "auth.send_otp",
    "auth.resend_otp",
    "auth.verify_otp",
    "auth.register_email",
    "auth.login_email",
    "auth.request_password_reset",
    "auth.reset_password",
    "payments.pawapay_webhook",
    "files.serve_file",
}

_CREATED_ENDPOINTS = {
    "auth.register_email",
    "drivers.register_or_update_driver",
    "drivers.add_vehicle",
    "rides.create_ride",
    "rides.submit_ride_offer",
    "chat.send_ride_message",
    "wallet.recharge_wallet",
    "admin.create_promo_code",
}


def _openapi_path(rule: Rule) -> str:
    return re.sub(
        r"<(?:(?:[^:<>]+):)?([^<>]+)>",
        r"{\1}",
        rule.rule,
    )


def _path_parameters(rule: Rule) -> list[dict[str, Any]]:
    parameters = []
    for name in sorted(rule.arguments):
        parameters.append(
            {
                "name": name,
                "in": "path",
                "required": True,
                "schema": {"type": "string"},
                "description": f"Identifiant {name}.",
            }
        )
    return parameters


def _query_parameters(endpoint: str) -> list[dict[str, Any]]:
    names = {
        "rides.get_active_ride": ["role"],
        "rides.get_available_rides": ["lat", "lng", "radiusKm", "matchVehicle"],
        "drivers.get_nearby_drivers": ["lat", "lng", "radiusKm", "vehicleType", "includeTest"],
        "drivers.get_my_driver_rides": ["page", "perPage", "status"],
        "users.get_my_rides": ["page", "perPage", "status"],
        "users.get_recent_destinations": ["limit"],
        "notifications.list_notifications": ["page", "perPage", "unreadOnly"],
        "wallet.get_wallet": ["page", "perPage"],
        "admin.list_drivers": ["page", "perPage", "verificationStatus"],
        "maps.autocomplete": ["input", "q", "country", "language", "lat", "lng", "sessionToken"],
        "maps.details": ["placeId", "sessionToken"],
    }.get(endpoint, [])
    integer_params = {"page", "perPage", "limit"}
    number_params = {"lat", "lng", "radiusKm"}
    return [
        {
            "name": name,
            "in": "query",
            "required": False,
            "schema": {
                "type": (
                    "integer"
                    if name in integer_params
                    else "number"
                    if name in number_params
                    else "string"
                )
            },
        }
        for name in names
    ]


def _request_body(endpoint: str, method: str) -> dict[str, Any] | None:
    if method in {"GET", "HEAD", "OPTIONS", "DELETE"}:
        return None

    content_types = (
        ["multipart/form-data", "application/json"]
        if endpoint == "drivers.register_or_update_driver"
        else ["multipart/form-data"]
        if endpoint in {"users.upload_avatar", "drivers.upload_driver_document"}
        else ["application/json"]
    )
    description = _BODY_DESCRIPTIONS.get(
        endpoint.rsplit(".", 1)[-1],
        "Corps JSON selon les paramètres de l’opération.",
    )
    schema = {"type": "object", "additionalProperties": True}
    if "multipart/form-data" in content_types:
        schema = {
            "type": "object",
            "properties": {"file": {"type": "string", "format": "binary"}},
            "additionalProperties": True,
        }
    return {
        "required": endpoint.rsplit(".", 1)[-1]
        in {"send_otp", "verify_otp", "register_email", "login_email", "create_ride"},
        "description": description,
        "content": {
            content_type: {"schema": schema}
            for content_type in content_types
        },
    }


def build_openapi_spec(app: Flask) -> dict[str, Any]:
    paths: dict[str, dict[str, Any]] = {}
    for rule in app.url_map.iter_rules():
        if (
            not rule.rule.startswith("/api/")
            or rule.rule.startswith(_DOCS_PREFIX)
            or rule.rule == _OPENAPI_URL
        ):
            continue
        endpoint = rule.endpoint
        view = app.view_functions.get(endpoint)
        if view is None:
            continue
        path = _openapi_path(rule)
        path_item = paths.setdefault(path, {})
        for method in sorted(rule.methods - {"HEAD", "OPTIONS"}):
            operation_id = f"{endpoint.replace('.', '_')}_{method.lower()}"
            summary = _SUMMARIES.get(
                view.__name__,
                view.__name__.replace("_", " ").capitalize(),
            )
            operation: dict[str, Any] = {
                "operationId": operation_id,
                "summary": summary,
                "tags": [endpoint.split(".", 1)[0].replace("_", " ").title()],
                "parameters": [
                    *_path_parameters(rule),
                    *_query_parameters(endpoint),
                ],
                "responses": {
                    "200": {"description": "Opération réussie.", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/SuccessResponse"}}}},
                    "400": {"description": "Requête invalide.", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/ErrorResponse"}}}},
                    "401": {"description": "Authentification requise ou invalide."},
                    "403": {"description": "Accès refusé."},
                    "404": {"description": "Ressource introuvable."},
                    "422": {"description": "Données invalides."},
                },
            }
            if endpoint not in _PUBLIC_ENDPOINTS:
                operation["security"] = [{"BearerAuth": []}]
            body = _request_body(endpoint, method)
            if body:
                operation["requestBody"] = body
            if method == "POST" and endpoint in _CREATED_ENDPOINTS:
                operation["responses"]["201"] = {
                    "description": "Ressource créée.",
                    "content": {"application/json": {"schema": {"$ref": "#/components/schemas/SuccessResponse"}}},
                }
            if "webhook" in endpoint:
                operation["description"] = (
                    "Endpoint serveur-à-serveur. En production, la requête doit "
                    "respecter les contrôles de signature ou de vérification fournisseur configurés."
                )
            path_item[method.lower()] = operation

    return {
        "openapi": "3.0.3",
        "info": {
            "title": "Moovi VTC API",
            "version": "1.0.0",
            "description": (
                "Documentation REST générée depuis les routes Flask. Les réponses "
                "utilisent une enveloppe JSON {success, data, message} ou {success, error}. "
                "Les routes authentifiées utilisent un JWT d’accès Bearer. Socket.IO "
                "est documenté dans README.md."
            ),
        },
        "tags": [
            {"name": name}
            for name in sorted(
                {operation["tags"][0] for item in paths.values() for operation in item.values()}
            )
        ],
        "paths": paths,
        "components": {
            "securitySchemes": {
                "BearerAuth": {
                    "type": "http",
                    "scheme": "bearer",
                    "bearerFormat": "JWT",
                    "description": "Access token retourné par les routes d’authentification.",
                }
            },
            "schemas": {
                "SuccessResponse": {
                    "type": "object",
                    "properties": {
                        "success": {"type": "boolean", "example": True},
                        "message": {"type": "string"},
                        "data": {"type": "object", "additionalProperties": True},
                    },
                    "required": ["success"],
                },
                "ErrorResponse": {
                    "type": "object",
                    "properties": {
                        "success": {"type": "boolean", "example": False},
                        "error": {
                            "type": "object",
                            "properties": {
                                "code": {"type": "string"},
                                "message": {"type": "string"},
                                "details": {"type": "object"},
                            },
                            "required": ["code", "message"],
                        },
                    },
                    "required": ["success", "error"],
                },
            },
        },
    }


def register_openapi(app: Flask) -> None:
    swagger_blueprint = get_swaggerui_blueprint(
        _DOCS_PREFIX,
        _OPENAPI_URL,
        config={"app_name": "Moovi VTC API"},
    )
    app.register_blueprint(swagger_blueprint)

    @app.get(_OPENAPI_URL, endpoint="openapi_spec")
    def openapi_spec():
        return jsonify(build_openapi_spec(current_app))
