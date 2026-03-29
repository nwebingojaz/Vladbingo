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

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < Decimal(str(bet)): return JsonResponse({'status': 'error', 'error': 'Low Balance'})
    game = GameRound.objects.filter(status="LOBBY", bet_amount=bet).first()
    if not game: return JsonResponse({'status': 'error', 'error': 'No Lobby'})
    game.players[str(tg_id)] = card_num
    game.save(); user.operational_credit -= Decimal(str(bet)); user.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    game = GameRound.objects.get(id=game_id)
    card_num = game.players.get(str(tg_id), 1)
    card = PermanentCard.objects.get(card_number=card_num)
    prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
    return JsonResponse({'board': card.board, 'called': game.called_numbers, 'prize': float(prize), 'status': game.status})

def get_history(request):
    history = GameRound.objects.filter(status="ENDED").order_by('-id')[:15]
    data = [{'game_id': g.id, 'winner': g.winner_username or "None", 'called': f"{len(g.called_numbers)}/75", 'prize': float(g.winner_prize)} for g in history]
    return JsonResponse({'history': data})

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
