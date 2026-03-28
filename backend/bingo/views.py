from django.shortcuts import render
from django.http import JsonResponse
from .models import User, GameRound, PermanentCard
from decimal import Decimal

def live_view(request): return render(request, 'live_view.html')

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    active_game = GameRound.objects.filter(status="ACTIVE").last()
    has_joined = active_game.id if (active_game and str(tg_id) in active_game.players) else None
    return JsonResponse({'balance': float(user.operational_credit), 'active_game': has_joined})

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < bet: return JsonResponse({'status': 'error', 'error': 'Insufficient Balance'})
    game, _ = GameRound.objects.get_or_create(status="LOBBY", bet_amount=bet)
    user.operational_credit -= Decimal(bet); user.save()
    game.players[str(tg_id)] = card_num; game.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    game = GameRound.objects.get(id=game_id)
    user = User.objects.get(username=f"tg_{tg_id}")
    card_num = game.players.get(str(tg_id), 1)
    card = PermanentCard.objects.get(card_number=card_num)
    prize = float(len(game.players) * game.bet_amount) * 0.80
    return JsonResponse({'board': card.board, 'prize': round(prize, 2), 'bet': float(game.bet_amount), 'called_numbers': game.called_numbers})

def check_win(request, tg_id):
    return JsonResponse({'status': 'NOT_YET'})
