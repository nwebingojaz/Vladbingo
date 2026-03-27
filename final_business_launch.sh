#!/bin/bash
# VladBingo - Final Business Launch (20% CUT + LOBBY TIMER)

# 1. FULL MODELS
cat <<'EOF' > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    current_joining_room = models.IntegerField(null=True, blank=True)
    bot_state = models.CharField(max_length=30, default="IDLE")

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    called_numbers = models.JSONField(default=list)
    players = models.JSONField(default=dict) # {"tg_id": card_num}
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, default="LOBBY") # LOBBY, STARTING, ACTIVE, ENDED

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    type = models.CharField(max_length=20, default="DEPOSIT")
    note = models.TextField(default="")
EOF

# 2. FULL VIEWS (20% Cut + Tiered Win Logic)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine is Active</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        # 20% CUT FOR ADMIN
        prize = float(len(game.players) * game.bet_amount) * 0.80 
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({
            'game_id': game.id, 'card_number': card.card_number, 'board': card.board,
            'prize': round(prize, 2), 'status': game.status, 'called_numbers': game.called_numbers
        })
    except: return JsonResponse({'error': 'Error'})

def check_win(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        if game.status != "ACTIVE": return JsonResponse({'status': 'NOT_ACTIVE'})
        if "WON" in game.status: return JsonResponse({'status': 'ALREADY_WON'})

        card_num = game.players.get(str(tg_id))
        card = PermanentCard.objects.get(card_number=card_num)
        called_set = set(game.called_numbers)
        board = card.board
        
        lines = 0
        for row in board:
            if all(c == "FREE" or c in called_set for c in row): lines += 1
        for c in range(5):
            if all(board[r][c] == "FREE" or board[r][c] in called_set for r in range(5)): lines += 1
        
        # Rule: 4 Corners count as a line
        corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
        if all(c in called_set for c in corners): lines += 1

        is_winner = False
        if float(game.bet_amount) <= 40:
            if lines >= 2: is_winner = True
        else: # 50-100 ETB
            if lines >= 3: is_winner = True

        if is_winner:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
            user.operational_credit += prize; user.save()
            game.status = f"WON_BY_{card.card_number}"; game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'ERROR'})

from rest_framework.views import APIView
from rest_framework.response import Response
class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request): return Response({"status": "ok"})
EOF

# 3. FULL BOT MAIN (Room Selection -> Unique Card -> 5 Min Timer)
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

async def game_dealer(game_id):
    await asyncio.sleep(300) # 5 MINUTE TIMER
    game = await sync_to_async(GameRound.objects.get)(id=game_id)
    game.status = "ACTIVE"; await sync_to_async(game.save)()
    nums = list(range(1, 76)); random.shuffle(nums)
    layer = get_channel_layer()
    for n in nums:
        game.refresh_from_db()
        if "WON" in game.status: break
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send(f"game_{game_id}", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)

async def start(update: Update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    user.bot_state = "IDLE"; await sync_to_async(user.save)()
    msg = f"🎰 **VLAD BINGO PLATFORM** 🎰\n💰 Balance: {user.operational_credit} ETB\n\nPick a room to join:"
    kbd = [[InlineKeyboardButton("💵 20 ETB", callback_data="room_20"), InlineKeyboardButton("💵 40 ETB", callback_data="room_40")],
           [InlineKeyboardButton("💵 50 ETB", callback_data="room_50"), InlineKeyboardButton("💵 100 ETB", callback_data="room_100")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def room_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    amt = int(q.data.split("_")[1]); user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.operational_credit < amt: await q.edit_message_text("❌ Insufficient Balance!"); return
    game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
    user.current_joining_room = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
    await q.edit_message_text(f"🎟 **Room {amt} ETB.**\nType your Card Number (1-100):")

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.bot_state != "PICKING" or not update.message.text.isdigit(): return
    val = int(update.message.text)
    game = await sync_to_async(GameRound.objects.get)(id=user.current_joining_room)
    if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
    user.operational_credit -= game.bet_amount; user.bot_state = "IDLE"; await sync_to_async(user.save)()
    game.players[str(uid)] = val; await sync_to_async(game.save)()
    url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={game.id}"
    if len(game.players) == 3:
        game.status = "STARTING"; await sync_to_async(game.save)()
        asyncio.create_task(game_dealer(game.id))
        await update.message.reply_text(f"✅ **LOBBY FULL!** {game.bet_amount} ETB Game starts in 5 minutes.", 
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url=url))]]))
    else:
        await update.message.reply_text(f"✅ Joined! Lobby: {len(game.players)}/3.", 
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url=url))]]))

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(room_handler, pattern="^room_"))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
EOF

# 4. MINI APP TEMPLATE (With 1-75 Tracker)
cat <<'EOF' > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>VladBingo Live</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0f172a; color: white; font-family: sans-serif; }
        .num-dot { width: 18px; height: 18px; display: flex; align-items: center; justify-content: center; font-size: 0.6rem; border-radius: 50%; background: #1e293b; border: 1px solid #334155; }
        .called { background: #fbbf24 !important; color: black !important; box-shadow: 0 0 8px #fbbf24; }
        .card-cell { background: #1e293b; aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-weight: bold; border: 1px solid #334155; border-radius: 6px; }
        .marked { background: #10b981 !important; color: white !important; }
    </style>
</head>
<body class="p-3">
    <div id="tracker" class="grid grid-cols-1 gap-1 mb-4 p-2 bg-slate-900 rounded-lg"></div>
    <div class="flex justify-between mb-2 px-2 text-xs font-bold text-gray-400 uppercase">
        <div>Prize: <span id="prize" class="text-emerald-400">0.00</span> ETB</div>
        <div>Card #<span id="card-num">--</span></div>
    </div>
    <div id="user-card" class="grid grid-cols-5 gap-1 bg-slate-800 p-2 rounded-xl border-2 border-slate-700 shadow-2xl"></div>
    <button id="bingo-btn" class="mt-6 w-full py-4 bg-yellow-500 text-black font-black text-xl rounded-lg shadow-lg">BINGO! 📢</button>
    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        const params = new URLSearchParams(window.location.search); const gameId = params.get("game_id") || 1;
        const tracker = document.getElementById('tracker');
        ['B','I','N','G','O'].forEach((l, idx) => {
            let h = '<div class="flex gap-1 items-center"><div class="text-yellow-500 font-bold w-4 text-[10px]">'+l+'</div>';
            for(let i=(idx*15)+1; i<=(idx*15)+15; i++) h += '<div id="t-'+i+'" class="num-dot">'+i+'</div>';
            tracker.innerHTML += h + '</div>';
        });
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
            data.called_numbers.forEach(n => { document.getElementById('t-'+n).classList.add('called'); });
        });
        const socket = new WebSocket('wss://' + window.location.host + '/ws/game/' + gameId + '/');
        socket.onmessage = (e) => {
            const m = JSON.parse(e.data);
            if(m.action === 'call_number') { document.getElementById('t-' + m.number).classList.add('called'); }
        };
        document.getElementById('bingo-btn').onclick = () => {
            fetch('/api/check-win/' + gameId + '/' + uid + '/').then(r=>r.json()).then(d => {
                if(d.status === 'WINNER') alert("🏆 BINGO! You won " + d.prize + " ETB!");
                else alert("❌ Not a Bingo yet!");
            });
        };
    </script>
</body>
</html>
EOF

# 5. SYNC URLS
cat <<'EOF' > backend/bingo/urls.py
from django.urls import path
from .views import live_view, get_game_info, check_win, ChapaWebhookView
urlpatterns = [
    path('live/', live_view, name='live_view'),
    path('game-info/<int:game_id>/<int:tg_id>/', get_game_info),
    path('check-win/<int:game_id>/<int:tg_id>/', check_win),
    path('chapa-webhook/', ChapaWebhookView.as_view()),
]
EOF

echo "🚀 MASTER SCRIPT READY FOR PUSH!"
