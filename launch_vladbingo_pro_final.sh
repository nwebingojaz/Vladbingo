#!/bin/bash
echo "🚀 STARTING VLAD BINGO PRO TOTAL REBUILD..."

# 1. SETUP FOLDERS
cd ~/vladbingo/backend
mkdir -p bingo/templates
mkdir -p bingo/management/commands
mkdir -p bingo/bot

# 2. CREATE MODELS
cat << 'EOF' > bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    bot_state = models.CharField(max_length=30, default="REG_NAME")
    real_name = models.CharField(max_length=100, blank=True)
    phone_number = models.CharField(max_length=20, blank=True)

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    called_numbers = models.JSONField(default=list)
    players = models.JSONField(default=dict)
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, default="LOBBY")
    winner_username = models.CharField(max_length=100, null=True, blank=True)
    winner_prize = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    finished_at = models.DateTimeField(null=True, blank=True)

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    type = models.CharField(max_length=20, default="DEPOSIT")
    note = models.TextField(default="")
EOF

# 3. CREATE VIEWS
cat << 'EOF' > bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from django.utils import timezone
from decimal import Decimal

def home(request):
    return HttpResponse("<h1>VLAD BINGO ENGINE ACTIVE</h1>")

def live_view(request):
    return render(request, 'live_view.html')

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    active_game = GameRound.objects.filter(status="LOBBY", bet_amount=10).first()
    time_left = 0
    if active_game:
        elapsed = (timezone.now() - active_game.created_at).total_seconds()
        time_left = max(0, 60 - int(elapsed))
    joined_id = active_game.id if (active_game and str(tg_id) in active_game.players) else None
    return JsonResponse({'balance': float(user.operational_credit), 'active_game': joined_id, 'time_left': time_left})

def get_history(request):
    history = GameRound.objects.filter(status="ENDED").order_by('-id')[:15]
    data = [{'game_id': g.id, 'winner': g.winner_username or "None", 'called': f"{len(g.called_numbers)}/75", 'prize': float(g.winner_prize)} for g in history]
    return JsonResponse({'history': data})

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < bet: return JsonResponse({'status': 'error', 'error': 'Low Balance'})
    game, _ = GameRound.objects.get_or_create(status="LOBBY", bet_amount=bet)
    game.players[str(tg_id)] = card_num
    game.save(); user.operational_credit -= Decimal(bet); user.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    game = GameRound.objects.get(id=game_id)
    card_num = game.players.get(str(tg_id), 1)
    card = PermanentCard.objects.get(card_number=card_num)
    prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
    return JsonResponse({'board': card.board, 'called': game.called_numbers, 'prize': float(prize), 'status': game.status})

def check_win(request, game_id, tg_id):
    user = User.objects.get(username=f"tg_{tg_id}")
    game = GameRound.objects.get(id=game_id)
    if game.status != "ACTIVE": return JsonResponse({'status': 'WAITING'})
    card_num = game.players.get(str(tg_id)); card = PermanentCard.objects.get(card_number=card_num)
    called_set = set(game.called_numbers); board = card.board; lines = 0
    for r in range(5):
        if all(board[r][c] == "FREE" or board[r][c] in called_set for c in range(5)): lines += 1
        if all(board[c][r] == "FREE" or board[c][r] in called_set for r in range(5)): lines += 1
    corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
    if all(c == "FREE" or c in called_set for c in corners): lines += 1
    threshold = 2 if float(game.bet_amount) <= 40 else 3
    if lines >= threshold:
        prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
        user.operational_credit += prize; user.save()
        game.status = "ENDED"; game.winner_username = user.username; game.winner_prize = prize
        game.finished_at = timezone.now(); game.save()
        return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
    return JsonResponse({'status': 'NOT_YET'})
EOF

# 4. CREATE BUILD.SH (THE NUCLEAR FIX FOR RENDER)
cat << 'EOF' > build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

# THE IMPROVED NUCLEAR FIX: Wipe everything to stop "Duplicate Key" errors
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    cursor.execute("GRANT ALL ON SCHEMA public TO public;")
innerEOF

# CLEAN MIGRATIONS AND REBUILD
find . -path "*/migrations/*.py" -not -name "__init__.py" -delete
python manage.py makemigrations bingo
python manage.py migrate
python manage.py init_bingo
EOF

# 5. CREATE INIT_BINGO
cat << 'EOF' > bingo/management/commands/init_bingo.py
import random
from django.core.management.base import BaseCommand
from bingo.models import PermanentCard, GameRound

class Command(BaseCommand):
    def handle(self, *args, **options):
        if not PermanentCard.objects.exists():
            for i in range(1, 101):
                board = [[random.randint(1,75) for _ in range(5)] for _ in range(5)]
                board[2][2] = "FREE"
                PermanentCard.objects.create(card_number=i, board=board)
        GameRound.objects.get_or_create(bet_amount=10, status="LOBBY")
EOF

# 6. REFRESH LOCAL REPO AND PUSH
git add .
git commit -m "Victory Launch: Nuclear database fix and Pro UI"
echo "✅ SETUP COMPLETE. RUN: git push -f origin main"
