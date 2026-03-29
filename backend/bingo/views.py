from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from django.utils import timezone
from decimal import Decimal

def home(request):
    return HttpResponse("<h1>VLAD BINGO ENGINE ACTIVE</h1>")

def live_view(request):
    return render(request, 'live_view.html')

def get_card_data(request, num):
    try:
        card = PermanentCard.objects.get(card_number=num)
        return JsonResponse({"board": card.board})
    except: return JsonResponse({"error": "not found"}, status=404)

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
