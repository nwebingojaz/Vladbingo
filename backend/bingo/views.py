from django.shortcuts import render
from django.http import JsonResponse
from .models import User, GameRound, PermanentCard
from decimal import Decimal

def live_view(request): return render(request, 'live_view.html')

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    active_game = GameRound.objects.exclude(status="ENDED").last()
    has_joined = active_game.id if (active_game and str(tg_id) in active_game.players) else None
    return JsonResponse({'balance': float(user.operational_credit), 'active_game': has_joined})

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < bet: return JsonResponse({'error': 'Low Balance'})
    game, _ = GameRound.objects.get_or_create(status="LOBBY", bet_amount=bet)
    if card_num in game.players.values(): return JsonResponse({'error': 'Card Taken'})
    user.operational_credit -= Decimal(bet); user.save()
    game.players[str(tg_id)] = card_num; game.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    game = GameRound.objects.get(id=game_id)
    user = User.objects.get(username=f"tg_{tg_id}")
    card_num = game.players.get(str(tg_id), 1)
    card = PermanentCard.objects.get(card_number=card_num)
    prize = float(len(game.players) * game.bet_amount) * 0.80 # 20% Cut
    return JsonResponse({'board': card.board, 'prize': round(prize, 2), 'bet': float(game.bet_amount), 'called_numbers': game.called_numbers, 'status': game.status})

def check_win(request, tg_id):
    user = User.objects.get(username=f"tg_{tg_id}")
    game = GameRound.objects.filter(status="ACTIVE").last()
    if not game: return JsonResponse({'status': 'NO_GAME'})
    card_num = game.players.get(str(tg_id))
    card = PermanentCard.objects.get(card_number=card_num)
    called_set = set(game.called_numbers)
    lines = 0
    for row in card.board:
        if all(c == "FREE" or c in called_set for c in row): lines += 1
    for c in range(5):
        if all(card.board[r][c] == "FREE" or card.board[r][c] in called_set for r in range(5)): lines += 1
    corners = [card.board[0][0], card.board[0][4], card.board[4][0], card.board[4][4]]
    if all(c in called_set for c in corners): lines += 1
    
    win_threshold = 2 if float(game.bet_amount) <= 40 else 3
    if lines >= win_threshold:
        prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
        user.operational_credit += prize; user.save()
        game.status = "ENDED"; game.save()
        return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
    return JsonResponse({'status': 'NOT_YET'})
