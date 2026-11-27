"""Point d'entrée WSGI de production (Linux).

    gunicorn --worker-class gthread --workers 1 --threads 100 --bind 0.0.0.0:5000 wsgi:app

Un seul worker suffit tant que SOCKETIO_MESSAGE_QUEUE n'est pas configuré
(sinon les événements Socket.IO ne seraient pas partagés entre processus).
Placer un proxy HTTPS (nginx, Caddy) devant : l'application exige https/wss.
"""
from app import create_app

app = create_app()
