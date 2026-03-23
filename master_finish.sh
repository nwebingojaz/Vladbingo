#!/bin/bash
# VladBingo - Full Feature Completion Script

# 1. Setup proper models.py
cat <<EOF > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_card = models.PositiveSmallIntegerField(default=1)

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    type = models.CharField(max_length=20, default="DEPOSIT") # DEPOSIT or WITHDRAWAL
    status = models.CharField(max_length=20, default="PENDING")
EOF

# 2. Setup Chapa Service logic
cat <<EOF > backend/bingo/services/chapa.py
import os, requests, uuid
CHAPA_KEY = os.environ.get("CHAPA_SECRET_KEY")
WEBHOOK = os.environ.get("WEBHOOK_URL")

def get_deposit_link(user, amount):
    ref = f"tx-{uuid.uuid4().hex[:6]}"
    payload = {
        "amount": str(amount), "currency": "ETB", "tx_ref": ref,
        "email": f"user_{user.id}@vladbingo.com", "callback_url": WEBHOOK
    }
    headers = {"Authorization": f"Bearer {CHAPA_KEY}"}
    res = requests.post("https://api.chapa.co/v1/transaction/initialize", json=payload, headers=headers)
    return res.json()
EOF

# 3. The Professional Bot (Select, Deposit, Withdraw)
cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, filters
from bingo.models import User, Transaction
from bingo.services.chapa import get_deposit_link

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    
    msg = (f"🎰 **VLAD BINGO LIVE** 🎰\n\n"
           f"👤 Player: {update.effective_user.first_name}\n"
           f"🎫 Active Card: #**{user.selected_card}**\n"
           f"💰 Balance: {user.operational_credit} ETB\n\n"
           f"Commands:\n/select <1-100> - Pick a card\n/deposit <amount> - Add ETB\n/withdraw <amount> - Cash out")
    
    kbd = [[InlineKeyboardButton("🎮 OPEN LIVE HALL", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def select(update, context):
    try:
        num = int(context.args[0])
        if not (1 <= num <= 100): raise ValueError
        uid = update.effective_user.id
        # Unique check
        if User.objects.filter(selected_card=num).exclude(username=f"tg_{uid}").exists():
            await update.message.reply_text(f"🚫 Card #{num} is already taken!")
            return
        user = User.objects.get(username=f"tg_{uid}")
        user.selected_card = num
        user.save()
        await update.message.reply_text(f"✅ You now own Card #{num}!")
    except:
        await update.message.reply_text("Usage: /select 45")

async def deposit(update, context):
    try:
        amount = int(context.args[0])
        user = User.objects.get(username=f"tg_{update.effective_user.id}")
        res = get_deposit_link(user, amount)
        link = res['data']['checkout_url']
        await update.message.reply_text(f"💳 [Click here to pay {amount} ETB]({link})", parse_mode='Markdown')
    except:
        await update.message.reply_text("Usage: /deposit 100")

async def withdraw(update, context):
    try:
        amt = int(context.args[0])
        user = User.objects.get(username=f"tg_{update.effective_user.id}")
        if user.operational_credit >= amt:
            Transaction.objects.create(agent=user, amount=-amt, type="WITHDRAWAL")
            await update.message.reply_text(f"✅ Withdrawal request for {amt} ETB sent to admin!")
        else:
            await update.message.reply_text("❌ Insufficient balance.")
    except:
        await update.message.reply_text("Usage: /withdraw 500")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("select", select))
    app.add_handler(CommandHandler("deposit", deposit))
    app.add_handler(CommandHandler("withdraw", withdraw))
    print("🤖 Bot Fully Armed and Online...")
    app.run_polling()

if __name__ == "__main__": run()
EOF

# 4. Final settings polish
cat <<EOF > backend/vlad_bingo/settings.py
import os, dj_database_url
from pathlib import Path
BASE_DIR = Path(__file__).resolve().parent.parent
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "vlad-bingo-secret")
DEBUG = True
ALLOWED_HOSTS = ["*"]
CSRF_TRUSTED_ORIGINS = ["https://vlad-bingo-web.onrender.com"]
INSTALLED_APPS = ["django.contrib.admin","django.contrib.auth","django.contrib.contenttypes","django.contrib.sessions","django.contrib.messages","django.contrib.staticfiles","rest_framework","corsheaders","channels","bingo"]
MIDDLEWARE = ["django.middleware.security.SecurityMiddleware","whitenoise.middleware.WhiteNoiseMiddleware","django.contrib.sessions.middleware.SessionMiddleware","corsheaders.middleware.CorsMiddleware","django.middleware.common.CommonMiddleware","django.middleware.csrf.CsrfViewMiddleware","django.contrib.auth.middleware.AuthenticationMiddleware","django.contrib.messages.middleware.MessageMiddleware"]
ROOT_URLCONF = "vlad_bingo.urls"
TEMPLATES = [{"BACKEND": "django.template.backends.django.DjangoTemplates","DIRS": [os.path.join(BASE_DIR, 'bingo/templates')],"APP_DIRS": True,"OPTIONS": {"context_processors": ["django.template.context_processors.debug","django.template.context_processors.request","django.contrib.auth.context_processors.auth","django.contrib.messages.context_processors.messages"]}}]
WSGI_APPLICATION = "vlad_bingo.wsgi.application"
ASGI_APPLICATION = "vlad_bingo.asgi.application"
DATABASES = {"default": dj_database_url.config(conn_max_age=600)}
AUTH_USER_MODEL = "bingo.User"
STATIC_URL = "/static/"
STATIC_ROOT = os.path.join(BASE_DIR, "staticfiles")
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
EOF

echo "✅ ALL FEATURES SYNCED!"
