import os, requests, uuid
CHAPA_KEY = os.environ.get("CHAPA_SECRET_KEY")
CHAPA_URL = "https://api.chapa.co/v1"

def init_deposit(user, amount):
    ref = f"dep-{uuid.uuid4().hex[:6]}"
    payload = {
        "amount": str(amount), "currency": "ETB", "tx_ref": ref,
        "email": f"{user.id}@vladbingo.com",
        "callback_url": os.environ.get("WEBHOOK_URL")
    }
    headers = {"Authorization": f"Bearer {CHAPA_KEY}"}
    res = requests.post(f"{CHAPA_URL}/transaction/initialize", json=payload, headers=headers)
    return res.json(), ref

def automated_payout(user, amount, bank_code, account_num):
    ref = f"wd-{uuid.uuid4().hex[:6]}"
    payload = {
        "account_name": user.username,
        "account_number": account_num, 
        "amount": str(amount),
        "bank_code": bank_code, 
        "reference": ref, 
        "currency": "ETB"
    }
    headers = {"Authorization": f"Bearer {CHAPA_KEY}"}
    res = requests.post(f"{CHAPA_URL}/transfers", json=payload, headers=headers)
    return res.json()
