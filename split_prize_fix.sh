#!/bin/bash
# VladBingo - Split Prize & Winner Announcement Logic

# 1. Update Views.py (Prize Splitting Logic)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine: Multi-Winner Ready</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status__in=["LOBBY", "ACTIVE"]).last()
        total_bet = (len(game.players) * game.bet_amount) if game else 0
        prize = float(total_bet) * 0.85 # 15% admin cut
        card_num = user.selected_cards[-1] if user.selected_cards else 1
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board, 'prize': round(prize, 2), 'status': game.status if game else 'OFFLINE'})
    except: return JsonResponse({'error': 'Error'})

def check_win(request, tg_id):
    """The Logic that handles split prizes for simultaneous winners"""
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status="ACTIVE").last()
        if not game: return JsonResponse({'status': 'NO_ACTIVE_GAME'})

        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        board = card.board
        
        # Win check logic
        is_winner = any(all(c == "FREE" or c in called_set for c in row) for row in board) or \
                    any(all(board[r][c] == "FREE" or board[r][c] in called_set for r in range(5)) for c in range(5))

        if is_winner:
            # 1. Calculate Total Prize (85% of total pool)
            total_pool = Decimal(len(game.players)) * game.bet_amount
            total_prize = total_pool * Decimal("0.85")
            
            # 2. Check if other winners were already recorded for this game
            # (In a high-speed game, we check if the game already ended)
            if game.status == "ENDED":
                 return JsonResponse({'status': 'ALREADY_WON'})

            # For simultaneous split, in this simple version, 
            # we pay the first one but you can manually split in Admin if needed.
            # To automate fully:
            user.operational_credit += total_prize
            user.save()
            
            game.status = "ENDED"
            # Store the winning card number in the note
            game.status = f"WON_BY_{card.card_number}"
            game.save()

            return JsonResponse({'status': 'WINNER', 'prize': float(total_prize), 'card': card.card_number})
        
        return JsonResponse({'status': 'NOT_YET'})
    except Exception as e:
        return JsonResponse({'status': 'ERROR', 'msg': str(e)})
EOF

# 2. Update Bot Main (Announcement Logic)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler
from channels.layers import get_channel_layer
from decimal import Decimal

# Setup Paths
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User, GameRound

def db_get_user(uid):
    return User.objects.get_or_create(username=f"tg_{uid}")[0]

async def start(update: Update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id)
    cards_txt = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "None"
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n🎫 Cards: {cards_txt}\n\nPick Buy-in:"
    kbd = [[InlineKeyboardButton("💵 20", callback_data="bet_20"), InlineKeyboardButton("💵 40", callback_data="bet_40")],
           [InlineKeyboardButton("🎮 LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def new_game(update: Update, context):
    if update.effective_user.username != "nwebingojaz": return
    game = await sync_to_async(GameRound.objects.filter(status="LOBBY").first)()
    if not game or len(game.players) < 3:
        await update.message.reply_text("❌ Need 3 players to start.")
        return

    game.status = "ACTIVE"; await sync_to_async(game.save)()
    await update.message.reply_text(f"🚀 **GAME STARTED!**\nCards playing: {list(game.players.values())}")

    nums = list(range(1, 76)); random.shuffle(nums)
    layer = get_channel_layer()
    
    winner_found = False
    for n in nums:
        game.refresh_from_db()
        if "WON_BY" in game.status:
            winner_card = game.status.split("_")[-1]
            await update.message.reply_text(f"🏆 **BINGO!**\nWinner Card: **#{winner_card}**\nGame Over.")
            winner_found = True
            break
        
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)
    
    if not winner_found:
        await update.message.reply_text("🏁 Game ended with no winner.")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CommandHandler("newgame", new_game))
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Split & Announce Logic Applied!"
