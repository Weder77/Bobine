"""Writes test/fixtures/sync_key_vectors.json: the sync keys of a few accounts.

A third implementation of the key derivation (Python's hashlib), independent of
the app (lib/sync/sync_crypto.dart) and of the site (site/src/lib/keys.js):
both are tested against these values, so a change to one of them cannot go
unnoticed. Usage: python3 tool/sync_key_vectors.py
"""
import base64
import hashlib
import hmac
import json
import os

CASES = [
    ("camille@exemple.fr", "correct horse battery staple", 1000),
    ("  Elodie.Martin@Exemple.FR ", "mot de passe accentué é ü 🎬", 1000),
    ("test@bobine.app", "12345678", 600000),
]


def derive(email, password, iterations):
    salt = ("bobine-sync|" + email.strip().lower()).encode()
    master = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, iterations, dklen=32)

    def sub(label):
        return hmac.new(master, label.encode(), hashlib.sha256).digest()

    return {
        "authSecret": base64.urlsafe_b64encode(sub("bobine-auth")).decode().rstrip("="),
        "encKey": base64.b64encode(sub("bobine-enc")).decode(),
        "idKey": base64.b64encode(sub("bobine-id")).decode(),
    }


vectors = [{"email": e, "password": p, "iterations": n, **derive(e, p, n)} for e, p, n in CASES]
out = os.path.join(os.path.dirname(__file__), "..", "test", "fixtures", "sync_key_vectors.json")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    json.dump(vectors, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(out)
