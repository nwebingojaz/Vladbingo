#!/bin/bash
# VladBingo - Real-Time Money Control & 20 ETB Minimum

# 1. Update Views.py (The Webhook that adds the money)
cat <<EOF > backend/bingo/views.py
from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, Transaction
from decimal import Decimal
import os, requests

def home(request):
    return HttpResponse("<h1>VladBingo Banker is Online</h1>")

def live_view(request):
    return render(request, 'live_view.html')

def get_card_data(request, card_num):
    from .models import PermanentCard
    try:
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        return JsonResponse({'error': 'Not found'}, status=404)

class ChapaWebhookView(APIView):
    permission_classes = [] 
    def post(self, request):
        data = request.data
        if data.get('status') == 'success':
            # Chapa returns the email we sent. We use it to find the user.
            email = data.get('email') # format: user_ID@vladbingo.com
            user_id = email.split('_')[1].split('@')[0]
            amount = Decimal(data.get('amount'))
            
            user = User.objects.get(id=user_id)
            user.operational_credit += amount
            user.save()
            
            Transaction.objects.create(
                agent=user, amount=amount, type="DEPOSIT", status="SUCCESS",
                note=f"Chapa Ref: {data.get('tx_ref')}"
            )
            
            # NOTIFY BOT: Send a message to the user via Telegram API
            bot_token = os.environ.get("TELEGRAM_BOT_TOKEN")
            tg_id = user.username.split('_')[1]
            msg = f"💰 **DEPOSIT CONFIRMED!**\n\n{amount} ETB has been added to your balance.\nYour new balance: {user.operational_credit} ETB"
            requests.get(f"https://api.telegram.org/bot{bot_token}/sendMessage?chat_id={tg_id}&text={msg}&parse_mode=Markdown")
            
            return Response(status=200)
        return Response(status=400)
EOF

# 2. Update the Bot Main (Enforcing 20 Birr Minimum)
cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler
from bingo.models import User
from bingo.services.chapa import get_deposit_link

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    msg = (f"🎰 **VLAD BINGO** 🎰\n\n"
           f"🎫 Card: #{user.selected_card}\n"
           f"💰 Balance: {user.operational_credit} ETB\n\n"
           f"Commands:\n/select <1-100>\n/deposit <amount> (Min 20 ETB)\n/withdraw <amount>")
    kbd = [[InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def deposit(update, context):
    try:
        amount = int(context.args[0])
        # THE 20 BIRR SECURITY CHECK
        if amount < 20:
            await update.message.reply_text("⚠️ **Minimum deposit is 20 Birr.**")
            return
            
        user = User.objects.get(username=f"tg_{update.effective_user.id}")
        res = get_deposit_link(user, amount)
        link = res['data']['checkout_url']
        
        kbd = [[InlineKeyboardButton(f"💳 Pay {amount} ETB Now", url=link)]]
        await update.message.reply_text(f"To add {amount} ETB, click the button below:", 
                                      reply_markup=InlineKeyboardMarkup(kbd))
    except:
        await update.message.reply_text("Usage: /deposit 100")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("deposit", deposit))
    print("🤖 Banker Bot is Online...")
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Real-Time Banker logic applied!"
