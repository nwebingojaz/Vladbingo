from django.shortcuts import render
from django.http import JsonResponse
from .models import User, GameRound, PermanentCard
from decimal import Decimal

def live_view(request): return render(request, 'live_view.html')

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    active_game = GameRound.objects.exclude(status="ENDED").last()
    joined_id = active_game.id if (active_game and str(tg_id) in active_game.players) else None
    return JsonResponse({'balance': float(user.operational_credit), 'active_game': joined_id})

def get_card_data(request, card_num):
    try:
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'board': card.board})
    except: return JsonResponse({'error': 'Not found'}, status=404)

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < bet: return JsonResponse({'status': 'error'})
    game, _ = GameRound.objects.get_or_create(status="LOBBY", bet_amount=bet)
    user.operational_credit -= Decimal(bet); user.save()
    game.players[str(tg_id)] = card_num; game.save()
    return JsonResponse({'status': 'ok'})
