"""Generate throwaway secrets for the load-test stack into loadtest/.secrets (gitignored).

Runs inside the backend image (it has `cryptography`). Nothing here is a real credential:
the Firebase file is a syntactically valid service account with a freshly generated key that
no Google project knows, and the TLS certificate is self-signed for the production hostnames
so the production nginx config can be used verbatim.
"""

from __future__ import annotations

import datetime as dt
import json
import secrets
import sys
from pathlib import Path

from cryptography import x509
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

out = Path(sys.argv[1] if len(sys.argv) > 1 else "/out")
out.mkdir(parents=True, exist_ok=True)
tls = out / "live" / "mushukistan.uz"
tls.mkdir(parents=True, exist_ok=True)

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
pem = key.private_bytes(
    serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption(),
).decode()

(out / "firebase-admin.json").write_text(
    json.dumps(
        {
            "type": "service_account",
            "project_id": "loadtest-project",
            "private_key_id": secrets.token_hex(20),
            "private_key": pem,
            "client_email": "loadtest@loadtest-project.iam.gserviceaccount.com",
            "client_id": "1",
            "token_uri": "https://oauth2.googleapis.com/token",
        }
    )
)

names = ["mushukistan.uz", "www.mushukistan.uz", "api.mushukistan.uz", "localhost"]
subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, names[0])])
now = dt.datetime.now(dt.UTC)
cert = (
    x509.CertificateBuilder()
    .subject_name(subject)
    .issuer_name(subject)
    .public_key(key.public_key())
    .serial_number(x509.random_serial_number())
    .not_valid_before(now - dt.timedelta(days=1))
    .not_valid_after(now + dt.timedelta(days=30))
    .add_extension(x509.SubjectAlternativeName([x509.DNSName(n) for n in names]), critical=False)
    .sign(key, hashes.SHA256())
)
(tls / "fullchain.pem").write_bytes(cert.public_bytes(serialization.Encoding.PEM))
(tls / "privkey.pem").write_text(pem)

env = {
    "JWT_SECRET_KEY": secrets.token_urlsafe(48),
    "POSTGRES_PASSWORD": secrets.token_urlsafe(24),
    "PUSH_TOKEN_ENCRYPTION_KEY": Fernet.generate_key().decode(),
}
(out / "secrets.env").write_text("".join(f"{k}={v}\n" for k, v in env.items()))
print("secrets written to", out)
