import os, requests, uuid
CHAPA_KEY = os.environ.get("CHAPA_SECRET_KEY")
WEBHOOK = os.environ.get("WEBHOOK_URL")

def init_deposit(user, amount):
    ref = f"dep-{uuid.uuid4().hex[:6]}"
    payload = {
        "amount": str(amount), "currency": "ETB", "tx_ref": ref,
        "email": f"user_{user.id}@vladbingo.com", "callback_url": WEBHOOK
    }
    headers = {"Authorization": f"Bearer {CHAPA_KEY}"}
    res = requests.post("https://api.chapa.co/v1/transaction/initialize", json=payload, headers=headers)
    return res.json(), ref
