import os, requests, uuid

def init_deposit(user, amount):
    CHAPA_KEY = os.environ.get("CHAPA_SECRET_KEY")
    WEBHOOK = os.environ.get("WEBHOOK_URL")
    
    if not CHAPA_KEY:
        return {"status": "error", "message": "Secret Key missing"}, None
        
    ref = f"dep-{uuid.uuid4().hex[:6]}"
    payload = {
        "amount": str(amount),
        "currency": "ETB",
        "tx_ref": ref,
        "email": f"tg_{user.id}@vladbingo.com",
        "callback_url": WEBHOOK,
        "customization": {"title": "VladBingo Deposit"}
    }
    headers = {"Authorization": f"Bearer {CHAPA_KEY}"}
    
    try:
        res = requests.post("https://api.chapa.co/v1/transaction/initialize", json=payload, headers=headers, timeout=10)
        return res.json(), ref
    except Exception as e:
        return {"status": "error", "message": str(e)}, None
