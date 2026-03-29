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
    # Get all active lobbies
    rooms = GameRound.objects.filter(status="LOBBY").values('id', 'bet_amount', 'players')
    room_data = []
    for r in rooms:
        p_count = len(r['players'])
        room_data.append({
            'id': r['id'],
            'bet': float(r['bet_amount']),
            'players': p_count,
            'win': float(r['bet_amount'] * p_count) * 0.8
        })
    
    # Check if user is already IN a game
    active_game = GameRound.objects.filter(players__has_key=str(tg_id)).exclude(status="ENDED").first()
    
    return JsonResponse({
        'balance': float(user.operational_credit), 
        'rooms': room_data,
        'active_game_id': active_game.id if active_game else None
    })

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < bet: return JsonResponse({'status': 'error', 'error': 'Low Balance'})
    game, _ = GameRound.objects.get_or_create(status="LOBBY", bet_amount=bet)
    game.players[str(tg_id)] = card_num
    game.save(); user.operational_credit -= Decimal(bet); user.save()
    return JsonResponse({'status': 'ok'})
