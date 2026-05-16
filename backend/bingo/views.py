import os
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

def home(request): return HttpResponse("<h1>BIGEST BINGO BOT ENGINE ACTIVE</h1>")
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
        players_dict = r['players'] or {}
        p_count = len(players_dict)
        total_cards = sum(len(c) if isinstance(c, list) else 1 for c in players_dict.values())
        win_amount = float(r['bet_amount'] * total_cards) * 0.73
        
        elapsed = (now - r['created_at']).total_seconds()
        room_data.append({
            'id': r['id'], 'bet': float(r['bet_amount']), 'players': p_count,
            'win': win_amount, 'status': r['status'],
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
        if isinstance(my_cards, list): card_str = ", ".join(str(x) for x in my_cards)
        else: card_str = str(my_cards)
            
        is_winner = g.winner_username == f"tg_{tg_id}"
        my_bets_data.append({
            'game_id': g.id, 'bet': float(g.bet_amount), 'card': card_str, 
            'status': "WON" if is_winner else "LOST", 
            'prize': float(g.winner_prize) if is_winner else 0
        })
    return JsonResponse({'winners': winners_data, 'my_bets': my_bets_data})

def join_room(request, tg_id, bet, card_num):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        selected_cards = [int(x) for x in str(card_num).split(',') if x.isdigit()]
        
        if len(selected_cards) == 0: return JsonResponse({'status': 'error', 'error': 'No cards selected'})
        if len(selected_cards) > 4: return JsonResponse({'status': 'error', 'error': 'Max 4 cards allowed!'})
        
        total_cost = Decimal(str(bet)) * len(selected_cards)
        if user.operational_credit < total_cost: 
            return JsonResponse({'status': 'error', 'error': f'Low Balance! You need {total_cost} ETB'})
            
        game = GameRound.objects.filter(status="LOBBY", bet_amount=bet).first()
        if not game: return JsonResponse({'status': 'error', 'error': 'No Lobby'})
        
        players_dict = dict(game.players or {})
        players_dict[str(tg_id)] = selected_cards
        game.players = players_dict
        game.save(update_fields=['players'])
        
        user.operational_credit -= total_cost
        user.save(update_fields=['operational_credit'])
        
        return JsonResponse({'status': 'ok'})
    except Exception as e:
        return JsonResponse({'status': 'error', 'error': str(e)})

def get_game_info(request, game_id, tg_id):
    try:
        game = GameRound.objects.get(id=game_id)
        user_cards = game.players.get(str(tg_id), [])
        if isinstance(user_cards, int): user_cards = [user_cards]
        
        boards_data = []
        for c_num in user_cards:
            try:
                card_obj = PermanentCard.objects.get(card_number=c_num)
                boards_data.append({"card_number": c_num, "board": card_obj.board})
            except: pass
            
        total_cards_in_game = sum(len(cards) if isinstance(cards, list) else 1 for cards in game.players.values())
        prize = (Decimal(total_cards_in_game) * game.bet_amount) * Decimal("0.73")
        
        resp = {
            'boards_data': boards_data, 'called': game.called_numbers, 
            'prize': float(prize), 'status': game.status
        }
        
        if game.status == 'ENDED':
            winner_user = User.objects.filter(username=game.winner_username).first()
            if winner_user and winner_user.real_name:
                resp['winner'] = winner_user.real_name
            else:
                resp['winner'] = game.winner_username.replace('tg_', '') if game.winner_username else "PLAYER"
                
            resp['prize'] = float(game.winner_prize)
            
            try:
                if game.winner_username:
                    w_tg = game.winner_username.replace('tg_', '')
                    w_cards = game.players.get(w_tg) or game.players.get(int(w_tg)) or []
                    if isinstance(w_cards, int): w_cards = [w_cards]
                    
                    winning_card_num = None
                    winning_board = None
                    
                    called_set = set(game.called_numbers)
                    called_set.add("FREE")
                    
                    for c_num in w_cards:
                        card_obj = PermanentCard.objects.get(card_number=c_num)
                        board = card_obj.board
                        lines = 0
                        for i in range(5):
                            if all(board[i][c] in called_set for c in range(5)): lines += 1
                            if all(board[r][i] in called_set for r in range(5)): lines += 1
                        if all(board[i][i] in called_set for i in range(5)): lines += 1
                        if all(board[i][4-i] in called_set for i in range(5)): lines += 1
                        corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
                        if all(c in called_set for c in corners): lines += 1
                        
                        if lines >= 1:
                            winning_card_num = c_num
                            winning_board = board
                            break
                    
                    if not winning_card_num and w_cards:
                        winning_card_num = w_cards[0]
                        winning_board = PermanentCard.objects.get(card_number=winning_card_num).board
                        
                    if winning_card_num:
                        resp['winning_card'] = winning_card_num
                        resp['winning_board'] = winning_board
            except Exception as e:
                print(f"Error fetching winning board: {e}")
            
        return JsonResponse(resp)
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
        
        if marked_nums == [0]: valid_marks = set(game.called_numbers)
        else: valid_marks = set(game.called_numbers).intersection(set(marked_nums))
            
        valid_marks.add("FREE")
        winning_card = None
        
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
            prize = (Decimal(total_cards) * game.bet_amount) * Decimal("0.73")
            
            user.operational_credit += prize; user.save()
            game.status = "ENDED"; game.winner_username = user.username; game.winner_prize = prize
            game.finished_at = timezone.now(); game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize), 'winning_card': winning_card})
            
        return JsonResponse({'status': 'NOT_YET'})
    except Exception as e:
        return JsonResponse({'status': 'error', 'msg': str(e)})

def send_telegram_message(chat_id, text):
    token = settings.TELEGRAM_BOT_TOKEN
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    try:
        requests.post(url, json={"chat_id": chat_id, "text": text, "parse_mode": "HTML"}, timeout=5)
    except Exception as e:
        pass

def send_gateway_otp(phone_number, otp_code):
    gateway_token = os.environ.get("GATEWAY_TOKEN") 
    url = "https://gatewayapi.telegram.org/sendVerificationMessage"
    if phone_number.startswith("0"): phone_number = "+251" + phone_number[1:]
    elif not phone_number.startswith("+"): phone_number = "+" + phone_number
    headers = { "Authorization": f"Bearer {gateway_token}", "Content-Type": "application/json" }
    payload = { "phone_number": phone_number, "code": otp_code }
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=5)
        response.raise_for_status()
    except Exception as e:
        pass

@csrf_exempt
def send_otp(request):
    if request.method == "POST":
        data = json.loads(request.body)
        tg_id = data.get('tg_id')
        phone = data.get('phone', '') 
        try:
            user = User.objects.get(username=f"tg_{tg_id}")
            if phone: user.phone_number = phone
            if not user.phone_number: return JsonResponse({"status": "error", "message": "Phone number is required."})
            otp = str(random.randint(100000, 999999))
            user.otp_code = otp
            user.otp_expiry = timezone.now() + timedelta(minutes=5)
            user.save()
            send_gateway_otp(user.phone_number, otp)
            return JsonResponse({"status": "success", "message": "OTP sent! Check your Telegram Verification Codes."})
        except User.DoesNotExist:
            return JsonResponse({"status": "error", "message": "User not found."})

@csrf_exempt
def verify_otp(request):
    if request.method == "POST":
        data = json.loads(request.body)
        tg_id = data.get('tg_id')
        otp = str(data.get('otp')).strip()
        try:
            user = User.objects.get(username=f"tg_{tg_id}")
            if user.otp_code == otp:
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
            Transaction.objects.create(agent=user, amount=amount, note=f"TXID: {tx_id}", type=f"DEPOSIT_{method.upper()}", status="pending")
            send_telegram_message(settings.CHANNEL_ID, f"🟢 <b>NEW DEPOSIT</b>\nUser: {tg_id}\nAmount: {amount} ETB\nMethod: {method}\nTXID: {tx_id}")
            return JsonResponse({"status": "success", "message": "Deposit submitted! Waiting for Admin approval."})
        except User.DoesNotExist:
            return JsonResponse({"status": "error", "message": "User not found."})

@csrf_exempt
def submit_withdrawal(request):
    if request.method == "POST":
        data = json.loads(request.body)
        tg_id = data.get('tg_id')
        amount = Decimal(str(data.get('amount', 0)))
        account = data.get('account')
        try:
            user = User.objects.get(username=f"tg_{tg_id}")
            if user.operational_credit < amount: return JsonResponse({"status": "error", "message": "Insufficient balance!"})
            if amount < 50: return JsonResponse({"status": "error", "message": "Minimum withdrawal is 50 ETB."})
            user.operational_credit -= amount
            user.save()
            Transaction.objects.create(agent=user, amount=amount, note=f"To: {account}", type="WITHDRAWAL", status="pending")
            send_telegram_message(settings.CHANNEL_ID, f"🔴 <b>NEW WITHDRAWAL</b>\nUser: {tg_id}\nAmount: {amount} ETB\nAccount: {account}\nPhone: {user.phone_number}")
            return JsonResponse({"status": "success", "message": "Withdrawal requested successfully!"})
        except User.DoesNotExist:
            return JsonResponse({"status": "error", "message": "User not found."})

@csrf_exempt
def submit_transfer(request):
    if request.method == "POST":
        data = json.loads(request.body)
        tg_id = data.get('tg_id')
        amount = Decimal(str(data.get('amount', 0)))
        target_account = data.get('account')
        try:
            sender = User.objects.get(username=f"tg_{tg_id}")
            if sender.operational_credit < amount: return JsonResponse({"status": "error", "message": "Insufficient balance!"})
            if amount < 10: return JsonResponse({"status": "error", "message": "Minimum transfer is 10 ETB."})
            receiver = User.objects.filter(phone_number=target_account).first()
            if not receiver: receiver = User.objects.filter(username=f"tg_{target_account}").first()
            if not receiver: return JsonResponse({"status": "error", "message": "Receiver account not found!"})
            if sender == receiver: return JsonResponse({"status": "error", "message": "You cannot transfer to yourself!"})
            sender.operational_credit -= amount
            sender.save()
            receiver.operational_credit += amount
            receiver.save()
            Transaction.objects.create(agent=sender, amount=amount, note=f"Transfer to {target_account}", type="TRANSFER_OUT", status="approved")
            Transaction.objects.create(agent=receiver, amount=amount, note=f"Transfer from {tg_id}", type="TRANSFER_IN", status="approved")
            if receiver.telegram_id:
                send_telegram_message(receiver.telegram_id, f"💸 <b>Transfer Received!</b>\nYou received {amount} ETB from user {tg_id}.")
            return JsonResponse({"status": "success", "message": f"Successfully transferred {amount} ETB!"})
        except User.DoesNotExist:
            return JsonResponse({"status": "error", "message": "User not found."})

@csrf_exempt
def change_password(request):
    if request.method == "POST":
        data = json.loads(request.body)
        tg_id = data.get('tg_id')
        new_pass = data.get('password')
        try:
            user = User.objects.get(username=f"tg_{tg_id}")
            user.set_password(new_pass)
            user.save()
            return JsonResponse({"status": "success", "message": "Security PIN updated successfully!"})
        except User.DoesNotExist:
            return JsonResponse({"status": "error", "message": "User not found."})

@csrf_exempt
def redeem_promo(request):
    if request.method == "POST":
        data = json.loads(request.body)
        tg_id = data.get('tg_id')
        promo_code = str(data.get('promo_code', '')).strip()
        try:
            user = User.objects.get(username=f"tg_{tg_id}")
            if getattr(user, 'used_promo_code', False): return JsonResponse({"status": "error", "message": "You have already used a promo code!"})
            if promo_code == str(tg_id): return JsonResponse({"status": "error", "message": "You cannot use your own code!"})
            friend = User.objects.filter(username=f"tg_{promo_code}").first()
            if not friend: return JsonResponse({"status": "error", "message": "Invalid Promo Code!"})
            user.operational_credit += 10
            user.used_promo_code = True
            user.save()
            friend.operational_credit += 10
            friend.save()
            Transaction.objects.create(agent=user, amount=10, note=f"Used promo code: {promo_code}", type="BONUS", status="approved")
            Transaction.objects.create(agent=friend, amount=10, note=f"Referral bonus from: {tg_id}", type="REFERRAL_BONUS", status="approved")
            if friend.telegram_id:
                send_telegram_message(friend.telegram_id, f"🎉 <b>Referral Bonus!</b>\nA friend just used your promo code! <b>10 ETB</b> has been added to your balance.")
            return JsonResponse({"status": "success", "message": "🎉 Success! 10 ETB added to your balance."})
        except User.DoesNotExist:
            return JsonResponse({"status": "error", "message": "User not found."})