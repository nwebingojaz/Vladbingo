#!/bin/bash
# VladBingo - Chapa Validation Fix (Email & Title length)

cat <<EOF > backend/bingo/services/chapa.py
import os, requests, uuid

def init_deposit(user, amount):
    CHAPA_KEY = os.environ.get("CHAPA_SECRET_KEY")
    WEBHOOK = os.environ.get("WEBHOOK_URL")
    
    if not CHAPA_KEY:
        return {"status": "error", "message": "Secret Key missing"}, None
        
    ref = f"dep-{uuid.uuid4().hex[:6]}"
    
    # THE FIX: 
    # 1. Use a simpler email format
    # 2. Shorten the title to exactly 13 characters ("Bingo Deposit")
    payload = {
        "amount": str(amount),
        "currency": "ETB",
        "tx_ref": ref,
        "email": "customer@vladbingo.com", 
        "callback_url": WEBHOOK,
        "customization": {
            "title": "Bingo Deposit",
            "description": f"User ID: {user.id}"
        }
    }
    headers = {"Authorization": f"Bearer {CHAPA_KEY}"}
    
    try:
        res = requests.post("https://api.chapa.co/v1/transaction/initialize", json=payload, headers=headers, timeout=10)
        return res.json(), ref
    except Exception as e:
        return {"status": "error", "message": str(e)}, None
EOF

echo "✅ Chapa validation fixes applied!"
