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
