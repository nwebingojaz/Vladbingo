import json
import requests
import random
from datetime import timedelta
from decimal import Decimal
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.conf import settings
from .models import User, PermanentCard, GameRound, Transaction

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
        
        # Calculate total cards bought by all players for accurate prize pool
        total_cards = sum(len(c) if isinstance(c, list) else 1 for c in r['players'].values())
        win_amount = float(r['bet_amount'] * total_cards) * 0.8
        
        elapsed = (now - r['created_at']).total_seconds()
        room_data.append({
            'id': r['id'], 'bet': float(r['bet_amount']), 'players': p_count,
            'win': win_amount,
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
    
    my_bets_data = []
    for g in my_games:
        my_cards = g.players.get(str(tg_id))
        if isinstance(my_cards, list):
            card_str = ", ".join(str(x) for x in my_cards)
        else:
            card_str = str(my_cards)
            
        is_winner = g.winner_username == f"tg_{tg_id}"
        my_bets_data.append({
            'game_id': g.id, 'bet': float(g.bet_amount), 'card': card_str, 
            'status': "WON" if is_winner else "LOST", 
            'prize': float(g.winner_prize) if is_winner else 0
        })
    return JsonResponse({'winners': winners_data, 'my_bets': my_bets_data})

# --- MULTI-CARD JOIN ROOM LOGIC ---
def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    
    # Convert comma-separated string into a list of integers
    selected_cards = [int(x) for x in str(card_num).split(',') if x.isdigit()]
    
    if len(selected_cards) == 0: return JsonResponse({'status': 'error', 'error': 'No cards selected'})
    if len(selected_cards) > 4: return JsonResponse({'status': 'error', 'error': 'Max 4 cards allowed!'})
    
    total_cost = Decimal(str(bet)) * len(selected_cards)
    if user.operational_credit < total_cost: 
        return JsonResponse({'status': 'error', 'error': f'Low Balance! You need {total_cost} ETB'})
        
    game = GameRound.objects.filter(status="LOBBY", bet_amount=bet).first()
    if not game: return JsonResponse({'status': 'error', 'error': 'No Lobby'})
    
    # Save the list of cards to the user
    game.players[str(tg_id)] = selected_cards
    game.save()
    
    user.operational_credit -= total_cost
    user.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    try:
        game = GameRound.objects.get(id=game_id)
        user_cards = game.players.get(str(tg_id), [])
        
        # Backward compatibility for old single int format
        if isinstance(user_cards, int): user_cards = [user_cards]
        
        boards_data = []
        for c_num in user_cards:
            card_obj = PermanentCard.objects.get(card_number=c_num)
            boards_data.append({
                "card_number": c_num,
                "board": card_obj.board
            })
            
        total_cards_in_game = sum(len(cards) if isinstance(cards, list) else 1 for cards in game.players.values())
        prize = (Decimal(total_cards_in_game) * game.bet_amount) * Decimal("0.80")
        
        return JsonResponse({
            'boards_data': boards_data, 
            'called': game.called_numbers, 
            'prize': float(prize), 
            'status': game.status
        })
    except Exception as e: return JsonResponse({'error': str(e)}, status=404)

def check_win(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        if game.status != "ACTIVE": return JsonResponse({'status': 'WAITING'})
        
        user_cards = game.players.get(str(tg_id), [])
        if isinstance(user_cards, int): user_cards = [user_cards]
        
        marked_str = request.GET.get('marked', '')
        marked_nums = [int(x) for x in marked_str.split(',') if x.isdigit()]
        
        # If marked is [0] (Auto Mode), assume all called numbers are marked
        if marked_nums == [0]:
            valid_marks = set(game.called_numbers)
        else:
            valid_marks = set(game.called_numbers).intersection(set(marked_nums))
            
        valid_marks.add("FREE") # Center is free
        
        winning_card = None
        
        # Loop through all up to 4 cards the user owns
        for c_num in user_cards:
            card = PermanentCard.objects.get(card_number=c_num)
            board = card.board
            lines = 0
            
            for i in range(5):
                if all(board[i][c] == "FREE" or board[i][c] in valid_marks for c in range(5)): lines += 1
                if all(board[r][i] == "FREE" or board[r][i] in valid_marks for r in range(5)): lines += 1
                
            if all(board[i][i] == "FREE" or board[i][i] in valid_marks for i in range(5)): lines += 1
            if all(board[i][4-i] == "FREE" or board[i][4-i] in valid_marks for i in range(5)): lines += 1
                
            corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
            if all(c == "FREE" or c in valid_marks for c in corners): lines += 1
            
            if lines >= 1:
                winning_card = c_num
                break
        
        if winning_card:
            total_cards = sum(len(cards) if isinstance(cards, list) else 1 for cards in game.players.values())
            prize = (Decimal(total_cards) * game.bet_amount) * Decimal("0.80")
            
            user.operational_credit += prize; user.save()
            game.status = "ENDED"; game.winner_username = user.username; game.winner_prize = prize
            game.finished_at = timezone.now(); game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize), 'winning_card': winning_card})
            
        return JsonResponse({'status': 'NOT_YET'})
    except Exception as e:
        return JsonResponse({'status': 'error', 'msg': str(e)})


# ==========================================
# OTP & MANUAL DEPOSIT LOGIC
# ==========================================

def send_telegram_message(chat_id, text):
    token = settings.TELEGRAM_BOT_TOKEN
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    requests.post(url, json={"chat_id": chat_id, "text": text, "parse_mode": "HTML"})

@csrf_exempt
def send_otp(request):
    if request.method == "POST":
        data = json.loads(request.body)
        tg_id = data.get('tg_id')
        try:
            user = User.objects.get(username=f"tg_{tg_id}")
            otp = str(random.randint(100000, 999999))
            user.otp_code = otp
            user.otp_expiry = timezone.now() + timedelta(minutes=5)
            user.save()
            
            msg = f"🔐 <b>Vlad Bingo Security</b>\n\nYour Deposit Verification Code is: <code>{otp}</code>\n\n<i>This code expires in 5 minutes.</i>"
            send_telegram_message(tg_id, msg)
            return JsonResponse({"status": "success", "message": "OTP sent to your Telegram chat!"})
        except User.DoesNotExist:
            return JsonResponse({"status": "error", "message": "User not found."})

@csrf_exempt
def verify_otp(request):
    if request.method == "POST":
        data = json.loads(request.body)
        tg_id = data.get('tg_id')
        otp = data.get('otp')
        try:
            user = User.objects.get(username=f"tg_{tg_id}")
            if user.otp_code == otp and user.otp_expiry and user.otp_expiry > timezone.now():
                user.otp_code = None
                user.save()
                return JsonResponse({"status": "success"})
            else:
                return JsonResponse({"status": "error", "message": "Invalid or expired OTP."})
        except User.DoesNotExist:
            return JsonResponse({"status": "error", "message": "User not found."})

@csrf_exempt
def submit_deposit(request):
    if request.method == "POST":
        data = json.loads(request.body)
        tg_id = data.get('tg_id')
        amount = data.get('amount')
        tx_id = data.get('tx_id')
        method = data.get('method')
        try:
            user = User.objects.get(username=f"tg_{tg_id}")
            Transaction.objects.create(
                agent=user, amount=amount, note=f"TXID: {tx_id}",
                type=f"DEPOSIT_{method.upper()}", status="pending"
            )
            return JsonResponse({"status": "success", "message": "Deposit submitted! Waiting for Admin approval."})
        except User.DoesNotExist:
            return JsonResponse({"status": "error", "message": "User not found."})