#!/bin/bash
# VladBingo - Infinite Loop Engine (End -> 1 Min Wait -> New Game)

# 1. Update Bot Main (The Automated Cycle)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer
from decimal import Decimal

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User, GameRound

async def run_infinite_dealer(game_id):
    """The Logic that never sleeps"""
    layer = get_channel_layer()
    game = await sync_to_async(GameRound.objects.get)(id=game_id)
    
    # 1. THE 5-MINUTE LOBBY TIMER (Before Start)
    game.status = "STARTING"; await sync_to_async(game.save)()
    await asyncio.sleep(300) 
    
    # 2. START THE GAME
    game.status = "ACTIVE"; await sync_to_async(game.save)()
    nums = list(range(1, 76)); random.shuffle(nums)
    
    for n in nums:
        game.refresh_from_db()
        if "WON" in game.status: break # Someone clicked BINGO!
        
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)

    # 3. GAME ENDED -> THE 1-MINUTE RESET (Like the screenshot!)
    await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "game_over"}})
    print(f"🏁 Game #{game.id} finished. Waiting 60 seconds to reset...")
    await asyncio.sleep(60) 
    
    # 4. START NEW LOBBY AUTOMATICALLY
    new_game = await sync_to_async(GameRound.objects.create)(status="LOBBY", bet_amount=game.bet_amount)
    print(f"🆕 New Lobby Created: Game #{new_game.id}")

async def start(update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\nPick a room to join:"
    kbd = [[InlineKeyboardButton("💵 20", callback_data="r_20"), InlineKeyboardButton("💵 50", callback_data="r_50")],
           [InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if q.data.startswith("r_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        game, created = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
        game.players[str(uid)] = user.selected_cards[-1] if user.selected_cards else 1
        await sync_to_async(game.save)()
        user.operational_credit -= Decimal(amt); await sync_to_async(user.save)()
        if len(game.players) == 3: # 3 Players triggers the 5-min timer
            asyncio.create_task(run_infinite_dealer(game.id))
            await q.edit_message_text("🔥 **LOBBY FULL!** 5 mins to start.")
        else: await q.edit_message_text(f"✅ Joined! Lobby {len(game.players)}/3")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(btn_handler))
    app.run_polling()

if __name__ == "__main__": run()
EOF

# 2. Update Mini App HTML (Show "GAME OVER" message)
sed -i 's/alert("BINGO/if(m.action==="game_over"){document.getElementById("game-status").innerText="RESETTING...";setTimeout(()=>location.reload(), 5000);} alert("BINGO/g' backend/bingo/templates/live_view.html

echo "✅ Infinite Loop Engine Applied!"
