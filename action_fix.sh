#!/bin/bash
# VladBingo - Final Action & Multi-Winner Sync

# 1. Update Views (Fix Card Sync & Prize Math)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine is Active</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status__in=["LOBBY", "ACTIVE"]).last()
        total_pool = (len(game.players) * game.bet_amount) if game else 0
        prize = float(total_pool) * 0.85 # Your 15% cut is safe
        
        # FIX: Get the actual last card the user added
        card_num = user.selected_cards[-1] if user.selected_cards else 1
        card = PermanentCard.objects.get(card_number=card_num)
        
        return JsonResponse({
            'card_number': card.card_number, 'board': card.board,
            'prize': round(prize, 2), 'status': game.status if game else 'OFFLINE',
            'called_numbers': game.called_numbers if game else []
        })
    except: return JsonResponse({'error': 'Sync Error'})

def check_win(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(status="ACTIVE")
        if "WON_BY" in game.status: return JsonResponse({'status': 'ALREADY_WON'})
        
        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        won = any(all(c == "FREE" or c in called_set for c in row) for row in card.board)
        
        if won:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.85")
            user.operational_credit += prize; user.save()
            game.status = f"WON_BY_{card.card_number}"; game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'NO_ACTIVE_GAME'})
EOF

# 2. Update the Bot Main (The Dealer Loop)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler
from channels.layers import get_channel_layer
from decimal import Decimal

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User, GameRound

async def start(update: Update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    cards = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "None"
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n🎫 Cards: {cards}\n\nPick Buy-in to Join Lobby:"
    kbd = [[InlineKeyboardButton("💵 20 ETB", callback_data="bet_20"), InlineKeyboardButton("💵 50 ETB", callback_data="bet_50")],
           [InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def bet_handler(update, context):
    q = update.callback_query; await q.answer()
    user = await sync_to_async(User.objects.get)(username=f"tg_{q.from_user.id}")
    amt = int(q.data.split("_")[1])
    if user.operational_credit < amt: 
        await q.edit_message_text("❌ Insufficient Balance!"); return
    if not user.selected_cards:
        await q.edit_message_text("❌ Pick a card first!"); return
        
    game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY")
    game.players[str(q.from_user.id)] = user.selected_cards[-1]
    game.bet_amount = Decimal(amt)
    await sync_to_async(game.save)()
    user.operational_credit -= Decimal(amt); await sync_to_async(user.save)()
    await q.edit_message_text(f"✅ **JOINED!** Paid {amt} ETB.\nLobby: {len(game.players)} cards. Admin will type /newgame to start.")

async def new_game(update, context):
    if update.effective_user.username != "nwebingojaz": return
    game = await sync_to_async(GameRound.objects.filter(status="LOBBY").first)()
    if not game or len(game.players) < 1: # Set to 1 for testing, 3 for real
        await update.message.reply_text("❌ Lobby is empty."); return
    
    game.status = "ACTIVE"; await sync_to_async(game.save)()
    await update.message.reply_text(f"🚀 **GAME STARTED!** Calling 75 numbers...")
    nums = list(range(1, 76)); random.shuffle(nums)
    layer = get_channel_layer()
    for n in nums:
        game.refresh_from_db()
        if "WON" in game.status: break
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CommandHandler("newgame", new_game))
    app.add_handler(CallbackQueryHandler(bet_handler, pattern="^bet_"))
    app.run_polling()
if __name__ == "__main__": run()
EOF

echo "✅ Action Fix Applied!"
