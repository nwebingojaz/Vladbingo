import os, requests, uuid
def init_deposit(user, amount):
    # THE SECRET: We hide the user ID in the reference so the Webhook can find them
    ref = f"vlad_{user.id}_{uuid.uuid4().hex[:4]}"
    payload = {
        "amount": str(amount), "currency": "ETB", "tx_ref": ref,
        "email": "bababingo22@gmail.com", 
        "callback_url": "https://vlad-bingo-web.onrender.com/api/chapa-webhook/",
        "customization": {"title": "Bingo Deposit"}
    }
    headers = {"Authorization": f"Bearer {os.environ.get('CHAPA_SECRET_KEY')}"}
    res = requests.post("https://api.chapa.co/v1/transaction/initialize", json=payload, headers=headers)
    return res.json(), ref
