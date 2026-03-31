#!/bin/bash
echo "🎰 APPLYING 1-LINE WIN RULES & AUTHENTIC B-I-N-G-O CARDS..."

cd ~/vladbingo/backend

# 1. UPDATE VIEWS.PY (Universal 1-Line Win Logic)
cat << 'INNER' > bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from django.utils import timezone
from decimal import Decimal

def home(request): return HttpResponse("<h1>VLAD BINGO ENGINE ACTIVE</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_card_data(request, num):
    try:
        card = PermanentCard.objects.get(card_number=num)
        return JsonResponse({"board": card.board})
    except: return JsonResponse({"error": "not found"}, status=404)

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    rooms = GameRound.objects.exclude(status="ENDED").values('id', 'bet_amount', 'players', 'created_at', 'status', 'called_numbers')
    room_data = []
    now = timezone.now()
    for r in rooms:
        p_count = len(r['players'])
        elapsed = (now - r['created_at']).total_seconds()
        room_data.append({
            'id': r['id'], 'bet': float(r['bet_amount']), 'players': p_count,
            'win': float(r['bet_amount'] * p_count) * 0.8,
            'status': r['status'],
            'called_count': len(r['called_numbers']),
            'time_left': max(0, 60 - int(elapsed))
        })
    active_game = GameRound.objects.filter(players__has_key=str(tg_id)).exclude(status="ENDED").last()
    return JsonResponse({'balance': float(user.operational_credit), 'rooms': room_data, 'active_game_id': active_game.id if active_game else None})

def get_history(request, tg_id):
    history = GameRound.objects.filter(status="ENDED").order_by('-id')[:15]
    winners_data = [{'game_id': g.id, 'winner': g.winner_username or "None", 'called': f"{len(g.called_numbers)}/75", 'prize': float(g.winner_prize)} for g in history]
    my_games = GameRound.objects.filter(players__has_key=str(tg_id)).order_by('-id')[:15]
    my_bets_data = [{'game_id': g.id, 'bet': float(g.bet_amount), 'card': g.players.get(str(tg_id)), 'status': "WON" if g.winner_username == f"tg_{tg_id}" else "LOST", 'prize': float(g.winner_prize) if g.winner_username == f"tg_{tg_id}" else 0} for g in my_games]
    return JsonResponse({'winners': winners_data, 'my_bets': my_bets_data})

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < Decimal(str(bet)): return JsonResponse({'status': 'error', 'error': 'Low Balance'})
    game = GameRound.objects.filter(status="LOBBY", bet_amount=bet).first()
    if not game: return JsonResponse({'status': 'error', 'error': 'No Lobby'})
    game.players[str(tg_id)] = card_num
    game.save(); user.operational_credit -= Decimal(str(bet)); user.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    try:
        game = GameRound.objects.get(id=game_id)
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
        return JsonResponse({'board': card.board, 'called': game.called_numbers, 'prize': float(prize), 'status': game.status})
    except: return JsonResponse({'error': 'not found'}, status=404)

def check_win(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        if game.status != "ACTIVE": return JsonResponse({'status': 'WAITING'})
        
        card_num = game.players.get(str(tg_id))
        card = PermanentCard.objects.get(card_number=card_num)
        
        # MANUAL CHECK: Get numbers the user ACTUALLY tapped
        marked_str = request.GET.get('marked', '')
        marked_nums = [int(x) for x in marked_str.split(',') if x.isdigit()]
        
        # ONLY count numbers the dealer CALLED that the user MARKED
        valid_marks = set(game.called_numbers).intersection(set(marked_nums))
        valid_marks.add("FREE") # Center is free
        
        board = card.board; lines = 0
        
        # Check Rows & Cols
        for i in range(5):
            if all(board[i][c] == "FREE" or board[i][c] in valid_marks for c in range(5)): lines += 1
            if all(board[r][i] == "FREE" or board[r][i] in valid_marks for r in range(5)): lines += 1
            
        # Check Diagonals
        if all(board[i][i] == "FREE" or board[i][i] in valid_marks for i in range(5)): lines += 1
        if all(board[i][4-i] == "FREE" or board[i][4-i] in valid_marks for i in range(5)): lines += 1
            
        # Check 4 Corners
        corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
        if all(c == "FREE" or c in valid_marks for c in corners): lines += 1
        
        # NEW RULE: 1 Line (or 4 Corners) = WIN for ALL rooms!
        if lines >= 1:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
            user.operational_credit += prize; user.save()
            game.status = "ENDED"; game.winner_username = user.username; game.winner_prize = prize
            game.finished_at = timezone.now(); game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
            
        return JsonResponse({'status': 'NOT_YET'})
    except Exception as e:
        return JsonResponse({'status': 'error', 'msg': str(e)})
INNER

# 2. UPDATE INIT_BINGO.PY (Generate Authentic 1-15, 16-30 Cards)
cat << 'INNER' > bingo/management/commands/init_bingo.py
import random
from django.core.management.base import BaseCommand
from bingo.models import PermanentCard, GameRound

class Command(BaseCommand):
    def handle(self, *args, **options):
        # Always wipe and rebuild cards to ensure authentic layout
        PermanentCard.objects.all().delete()
        
        self.stdout.write("Generating 200 Authentic B-I-N-G-O Cards...")
        for i in range(1, 201):
            # Strict Column Rules
            b = random.sample(range(1, 16), 5)
            i_col = random.sample(range(16, 31), 5)
            n = random.sample(range(31, 46), 5)
            g = random.sample(range(46, 61), 5)
            o = random.sample(range(61, 76), 5)
            
            n[2] = "FREE" # The center space
            
            # Transpose columns into rows for the 5x5 Grid UI
            board = []
            for row_idx in range(5):
                board.append([b[row_idx], i_col[row_idx], n[row_idx], g[row_idx], o[row_idx]])
            
            PermanentCard.objects.create(card_number=i, board=board)
            
        # Ensure rooms exist
        for t in [10, 20, 30, 40, 50, 100]:
            GameRound.objects.get_or_create(bet_amount=t, status="LOBBY")
            
        self.stdout.write("✅ Authentic Cards Generated!")
INNER

# 3. PUSH TO GITHUB
cd ~/vladbingo
git add .
git commit -m "Gameplay: Authentic Card Generator (1-15/16-30) and Universal 1-Line Win logic"
git push -f origin main
echo "✅ AUTHENTIC BINGO RULES DEPLOYED! Watch Render update."
