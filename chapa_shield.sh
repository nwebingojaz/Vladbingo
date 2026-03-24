#!/bin/bash
# VladBingo - Robust Chapa Integration

# 1. Fix Chapa Service with Error Checking
cat <<EOF > backend/bingo/services/chapa.py
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
EOF

# 2. Update Bot to handle the response
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from asgiref.sync import sync_to_async

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from bingo.models import User
from bingo.services.chapa import init_deposit

def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "state": user.bot_state = val
    user.save()
    return user

async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "state", "IDLE")
    msg = f"🎰 **VLAD BINGO** 🎰\n\n💰 Balance: {user.operational_credit} ETB\n🎫 Cards: {user.selected_cards}"
    kbd = [[InlineKeyboardButton("💳 DEPOSIT", callback_data="dep"), InlineKeyboardButton("🎮 LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer()
    if q.data == "dep":
        await sync_to_async(db_op)(q.from_user.id, "state", "DEPOSITING")
        await q.edit_message_text("💵 **How much ETB do you want to add?** (Min 20):", parse_mode='Markdown')

async def text_handler(update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if not update.message.text.isdigit(): return
    val = int(update.message.text)

    if user.bot_state == "DEPOSITING":
        if val < 20:
            await update.message.reply_text("❌ Minimum deposit is 20 ETB.")
            return
        
        await update.message.reply_text("⏳ Generating payment link...")
        
        # Call the robust service
        res, ref = await sync_to_async(init_deposit)(user, val)
        
        if res.get('status') == 'success':
            link = res['data']['checkout_url']
            await update.message.reply_text(f"✅ **Link Ready!**\nClick below to pay {val} ETB via Telebirr/CBE:", 
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔗 PAY NOW", url=link)]]), parse_mode='Markdown')
        else:
            err_msg = res.get('message', 'Unknown Error')
            await update.message.reply_text(f"❌ **Chapa Error:** {err_msg}\nCheck your CHAPA_SECRET_KEY in Render settings.")
        
        # Reset state to IDLE
        await sync_to_async(db_op)(update.effective_user.id, "state", "IDLE")

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Chapa Shield applied!"
