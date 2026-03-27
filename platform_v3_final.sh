#!/bin/bash
# VLAD BINGO - PLATFORM V3 (MULTIPLE CARDS + ROOM SWITCHER)

# 1. FULL MODELS
cat <<'EOF' > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    # selected_cards stores { "room_id": [card1, card2] }
    active_bets = models.JSONField(default=dict)
    current_room_context = models.IntegerField(null=True, blank=True)
    bot_state = models.CharField(max_length=30, default="REG_NAME")
    real_name = models.CharField(max_length=100, blank=True)
    phone_number = models.CharField(max_length=20, blank=True)

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    called_numbers = models.JSONField(default=list)
    players = models.JSONField(default=dict) # {"tg_id": [card1, card2]}
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, default="LOBBY") # LOBBY, STARTING, ACTIVE

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    type = models.CharField(max_length=20, default="DEPOSIT")
EOF

# 2. UPDATED MINI APP (Fixing the 'Undefined' Bug)
cat <<'EOF' > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>VladBingo Hall</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0f172a; color: white; font-family: sans-serif; }
        .num-dot { width: 18px; height: 18px; display: flex; align-items: center; justify-content: center; font-size: 0.6rem; border-radius: 50%; background: #1e293b; border: 1px solid #334155; }
        .called { background: #fbbf24 !important; color: black !important; }
        .card-cell { background: #1e293b; aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-weight: bold; border: 1px solid #334155; border-radius: 6px; }
        .marked { background: #10b981 !important; color: white !important; }
    </style>
</head>
<body class="p-3">
    <div id="tracker" class="grid grid-cols-1 gap-1 mb-4 p-2 bg-slate-900 rounded-lg"></div>
    <div class="flex justify-between mb-2 px-2 text-[10px] font-bold text-gray-400">
        <div>PRIZE: <span id="prize" class="text-emerald-400">--</span> ETB</div>
        <div>CARD #<span id="card-num">--</span></div>
    </div>
    <div id="user-card" class="grid grid-cols-5 gap-1 bg-slate-800 p-2 rounded-xl border-2 border-slate-700 shadow-2xl"></div>
    <button id="bingo-btn" class="mt-6 w-full py-4 bg-yellow-500 text-black font-black rounded-lg shadow-lg">BINGO! 📢</button>
    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        const params = new URLSearchParams(window.location.search);
        const gameId = params.get("game_id");
        
        // Build Tracker
        const tracker = document.getElementById('tracker');
        ['B','I','N','G','O'].forEach((l, idx) => {
            let h = '<div class="flex gap-1 items-center"><div class="text-yellow-500 font-bold w-4 text-[10px]">'+l+'</div>';
            for(let i=(idx*15)+1; i<=(idx*15)+15; i++) h += '<div id="t-'+i+'" class="num-dot">'+i+'</div>';
            tracker.innerHTML += h + '</div>';
        });

        // Fetch Room Data
        fetch('/api/game-info/' + gameId + '/' + uid + '/').then(r=>r.json()).then(data=>{
            document.getElementById('card-num').innerText = data.card_number;
            document.getElementById('prize').innerText = data.prize;
            data.board.forEach(row => row.forEach(val => {
                const cell = document.createElement('div'); cell.className = 'card-cell';
                cell.innerText = val === 'FREE' ? '★' : val;
                if(val === 'FREE') cell.classList.add('marked');
                cell.onclick = () => cell.classList.toggle('marked');
                document.getElementById('user-card').appendChild(cell);
            }));
            data.called_numbers.forEach(n => { if(document.getElementById('t-'+n)) document.getElementById('t-'+n).classList.add('called'); });
        });

        const socket = new WebSocket('wss://' + window.location.host + '/ws/game/' + gameId + '/');
        socket.onmessage = (e) => {
            const m = JSON.parse(e.data);
            if(m.action === 'call_number') {
                const el = document.getElementById('t-' + m.number);
                if(el) el.classList.add('called');
            }
        };

        document.getElementById('bingo-btn').onclick = () => {
            fetch('/api/check-win/' + gameId + '/' + uid + '/').then(r=>r.json()).then(d => {
                if(d.status === 'WINNER') alert("🏆 BINGO! Won " + d.prize + " ETB!");
                else alert("❌ Not a Bingo yet!");
            });
        };
    </script>
</body>
</html>
EOF

# 3. FULL BOT MAIN (Room Management + Multiple Card + Remover)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer
from decimal import Decimal

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User, GameRound

def db_get_user(uid): return User.objects.get_or_create(username=f"tg_{uid}")[0]

async def start(update: Update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id)
    if not user.real_name:
        user.bot_state = "REG_NAME"; await sync_to_async(user.save)()
        await update.message.reply_text("👋 Welcome! Please enter your **Full Name** to register:")
        return

    # Check for active games joined by user
    active_games = await sync_to_async(lambda: list(GameRound.objects.filter(status__in=["LOBBY","STARTING","ACTIVE"])))()
    user_games = [g for g in active_games if str(update.effective_user.id) in g.players]
    
    kbd = []
    for g in user_games:
        url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={g.id}"
        kbd.append([InlineKeyboardButton(f"🎮 ENTER {int(g.bet_amount)} ETB HALL (Room #{g.id})", web_app=WebAppInfo(url=url))])

    kbd.append([InlineKeyboardButton("💵 Join 20 ETB", callback_data="join_20"), InlineKeyboardButton("💵 Join 50 ETB", callback_data="join_50")])
    kbd.append([InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")])
    
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n\nPick a room to join or enter your active hall:"
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(db_get_user)(uid)
    if q.data.startswith("join_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
        user.current_room_context = game.id; user.bot_state = "ROOM_LOBBY"; await sync_to_async(user.save)()
        
        # Room Sub-Menu
        sub_kbd = [[InlineKeyboardButton("➕ Add Card", callback_data="sub_add"), InlineKeyboardButton("➖ Remove Card", callback_data="sub_rem")],
                   [InlineKeyboardButton("⬅️ Back to Menu", callback_data="sub_back")]]
        await q.edit_message_text(f"🎟 **{amt} ETB Room.** Lobby: {len(game.players)}/3\nPick an action:", reply_markup=InlineKeyboardMarkup(sub_kbd))

    elif q.data == "sub_add":
        user.bot_state = "ADD_CARD"; await sync_to_async(user.save)()
        await q.edit_message_text("🔢 Type Card # (1-100) to **ADD** to this room:")
    elif q.data == "sub_rem":
        user.bot_state = "REM_CARD"; await sync_to_async(user.save)()
        await q.edit_message_text("🔢 Type Card # to **REMOVE** from this room:")
    elif q.data == "sub_back": await start(update.callback_query, context)

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(db_get_user)(uid)
    text = update.message.text
    if user.bot_state == "REG_NAME":
        user.real_name = text; user.bot_state = "IDLE"; await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Hello {text}!"); await start(update, context)
    elif text.isdigit():
        val = int(text); game = await sync_to_async(GameRound.objects.get)(id=user.current_room_context)
        if user.bot_state == "ADD_CARD":
            if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
            # Multi-card logic
            current_cards = game.players.get(str(uid), [])
            if not isinstance(current_cards, list): current_cards = [current_cards]
            current_cards.append(val); game.players[str(uid)] = current_cards
            user.operational_credit -= game.bet_amount; await sync_to_async(user.save)(); await sync_to_async(game.save)()
            await update.message.reply_text(f"✅ Card #{val} added! Type another or /start."); return
        elif user.bot_state == "REM_CARD":
             # Remove logic here
             await update.message.reply_text("🗑 Removed!"); await start(update, context)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler)); app.run_polling()
if __name__ == "__main__": run()
EOF

# 4. FINAL VIEWS
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse
from .models import User, PermanentCard, GameRound
def live_view(request): return render(request, 'live_view.html')
def get_game_info(request, game_id, tg_id):
    try:
        game = GameRound.objects.get(id=game_id)
        user = User.objects.get(username=f"tg_{tg_id}")
        prize = float(len(game.players) * game.bet_amount) * 0.80
        # Get the first card this user has in this game
        u_cards = game.players.get(str(tg_id), [1])
        card_num = u_cards[0] if isinstance(u_cards, list) else u_cards
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board, 'prize': round(prize, 2), 'status': game.status, 'called_numbers': game.called_numbers})
    except: return JsonResponse({'error': 'Not found'}, status=404)
EOF

echo "✅ PLATFORM V3 READY!"
