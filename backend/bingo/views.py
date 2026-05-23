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
from django.db import transaction

from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync

from .models import User, PermanentCard, GameRound, Transaction, GameControl

def home(request): 
    return HttpResponse("<h1>BIGEST BINGO BOT ENGINE ACTIVE</h1>")

def live_view(request): 
    return render(request, 'live_view.html')

def get_card_data(request, num):
    try:
        card = PermanentCard.objects.get(card_number=num)
        return JsonResponse({"board": card.board})
    except: 
        return JsonResponse({"error": "not found"}, status=404)

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    
    # Exclude both ENDED and ANNOUNCED games from showing up as active lobby cards!
    rooms = GameRound.objects.exclude(status__in=["ENDED", "ANNOUNCED"]).order_by('bet_amount')
    
    room_data = []
    my_lobby_cards = {} # Tracks which cards the user currently owns in the lobbies
    now = timezone.now()
    
    for r in rooms:
        players_dict = r.players if r.players else {}
        p_count = len(players_dict)
        total_cards = sum(len(c) if isinstance(c, list) else 1 for c in players_dict.values())
        win_amount = float(r.bet_amount * total_cards) * 0.73
        
        if r.status == "LOBBY":
            elapsed = (now - r.created_at).total_seconds()
            time_left = max(0, 60 - int(elapsed))
            
            # Fetch user's currently purchased cards for this tier
            c = players_dict.get(str(tg_id), [])
            if isinstance(c, int): c = [c]
            my_lobby_cards[str(int(r.bet_amount))] = c
        else:
            time_left = 0
            
        room_data.append({
            'id': r.id, 'bet': float(r.bet_amount), 'players': p_count,
            'win': win_amount, 'status': r.status,
            'called_count': len(r.called_numbers),
            'time_left': time_left
        })
        
    # Only treat games as "active" if they are currently in the LOBBY or ACTIVE state!
    active_game = GameRound.objects.filter(players__has_key=str(tg_id), status__in=["LOBBY", "ACTIVE"]).last()
    
    return JsonResponse({
        'balance': float(user.operational_credit), 
        'rooms': room_data, 
        'my_lobby_cards': my_lobby_cards,
        'active_game_id': active_game.id if active_game else None
    })

def get_history(request, tg_id):
    history = GameRound.objects.filter(status__in=["ENDED", "ANNOUNCED"]).order_by('-id')[:15]
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

@csrf_exempt
@transaction.atomic
def join_room(request, tg_id, bet, card_num):
    # INSTANT BUY/REFUND TOGGLE API (ULTRA-SAFE)
    try:
        # Use get_or_create so this API never fails with "User Does Not Exist"
        user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
        user = User.objects.select_for_update().get(id=user.id)
        
        game = GameRound.objects.select_for_update().filter(status="LOBBY", bet_amount=bet).first()
        
        if not game: 
            return JsonResponse({'status': 'error', 'error': 'Room is starting or unavailable. Wait for next round.'})
        
        c_num = int(card_num)
        players = dict(game.players) if game.players else {}
        user_cards = players.get(str(tg_id), [])
        if isinstance(user_cards, int): user_cards = [user_cards]
        
        action = ""
        if c_num in user_cards:
            # INSTANT REFUND
            user_cards.remove(c_num)
            if not user_cards:
                del players[str(tg_id)]
            else:
                players[str(tg_id)] = user_cards
            
            user.operational_credit += Decimal(str(bet))
            action = 'removed'
        else:
            # INSTANT BUY
            if len(user_cards) >= 4:
                return JsonResponse({'status': 'error', 'error': 'Max 4 cards allowed!'})
            if user.operational_credit < Decimal(str(bet)):
                return JsonResponse({'status': 'error', 'error': 'Insufficient balance!'})
            
            user_cards.append(c_num)
            players[str(tg_id)] = user_cards
            user.operational_credit -= Decimal(str(bet))
            action = 'added'
            
        game.players = players
        game.save(update_fields=['players'])
        user.save(update_fields=['operational_credit'])
        
        # Recalculate live prize pool
        total_cards = sum(len(c) if isinstance(c, list) else 1 for c in players.values())
        prize = float(Decimal(total_cards) * game.bet_amount * Decimal("0.73"))
        
        return JsonResponse({
            'status': 'ok', 
            'action': action,
            'balance': float(user.operational_credit),
            'prize': prize,
            'my_cards': user_cards
        })
    except Exception as e:
        print(f"Join Room Error: {e}")
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
        
        if game.status in ['ENDED', 'ANNOUNCED']:
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
                            if all(board[i][c] == "FREE" or board[i][c] in called_set for c in range(5)): lines += 1
                            if all(board[r][i] == "FREE" or board[r][i] in called_set for r in range(5)): lines += 1
                        if all(board[i][i] == "FREE" or board[i][i] in called_set for i in range(5)): lines += 1
                        if redemption_board_match := all(board[i][4-i] == "FREE" or board[i][4-i] in called_set for i in range(5)): lines += 1
                        corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
                        if all(c == "FREE" or c in called_set for c in corners): lines += 1
                        
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
            except: pass
            
        return JsonResponse(resp)
    except Exception as e: return JsonResponse({'error': str(e)}, status=404)

@csrf_exempt
@transaction.atomic
def check_win(request, game_id, tg_id):
    try:
        user = User.objects.select_for_update().get(username=f"tg_{tg_id}")
        game = GameRound.objects.select_for_update().get(id=game_id)
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
            board = card.board; lines = 0
            for i in range(5):
                if all(board[i][c] == "FREE" or board[i][c] in valid_marks for c in range(5)): lines += 1
                if all(board[r][i] == "FREE" or board[r][i] in valid_marks for r in range(5)): lines += 1
            if all(board[i][i] == "FREE" or board[i][i] in valid_marks for i in range(5)): lines += 1
            if all(board[i][4-i] == "FREE" or board[i][4-i] in valid_marks for i in range(5)): lines += 1
            corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
            if all(c == "FREE" or c in valid_marks for c in corners): lines += 1
            
            if lines >= 1: winning_card = c_num; break
        
        if winning_card:
            total_cards = sum(len(cards) if isinstance(cards, list) else 1 for cards in game.players.values())
            prize = (Decimal(total_cards) * game.bet_amount) * Decimal("0.73")
            
            user.operational_credit += prize
            user.save(update_fields=['operational_credit'])
            
            game.status = "ENDED"
            game.winner_username = user.username
            game.winner_prize = prize
            game.finished_at = timezone.now()
            game.save(update_fields=['status', 'winner_username', 'winner_prize', 'finished_at'])
            
            try:
                channel_layer = get_channel_layer()
                async_to_sync(channel_layer.group_send)(
                    f'game_{game.id}',
                    {'type': 'bingo_message', 'message': {'action': 'game_ended'}}
                )
            except Exception as ws_e: 
                print(f"WebSocket Broadcast Failed on Win: {ws_e}")
                pass

            return JsonResponse({'status': 'WINNER', 'prize': float(prize), 'winning_card': winning_card})
            
        return JsonResponse({'status': 'NOT_YET'})
    except Exception as e: return JsonResponse({'status': 'error', 'msg': str(e)})


# ==========================================
# TELEGRAM NOTIFICATION SYSTEM
# ==========================================
def send_telegram_message(chat_id, text):
    try: 
        # ==========================================
        # ⚠️ PASTE YOUR EXACT BOT TOKEN HERE:
        # ==========================================
        bot_token = "8212617770:AAEGMXyirnTEjOJVG_t7xINkmF7DAhOP8WM"
        
        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        payload = {"chat_id": chat_id, "text": text, "parse_mode": "HTML"}
        
        response = requests.post(url, json=payload, timeout=5)
        if response.status_code != 200:
            print(f"TELEGRAM API ERROR: {response.text}")
            
    except Exception as e: 
        print(f"TELEGRAM CRASH: {e}")

def send_gateway_otp(phone_number, otp_code):
    gateway_token = os.environ.get("GATEWAY_TOKEN") 
    if phone_number.startswith("0"): phone_number = "+251" + phone_number[1:]
    elif not phone_number.startswith("+"): phone_number = "+" + phone_number
    try: requests.post("https://gatewayapi.telegram.org/sendVerificationMessage", headers={"Authorization": f"Bearer {gateway_token}", "Content-Type": "application/json"}, json={"phone_number": phone_number, "code": otp_code}, timeout=5)
    except: pass

@csrf_exempt
def send_otp(request):
    if request.method == "POST":
        data = json.loads(request.body); tg_id = data.get('tg_id'); phone = data.get('phone', '') 
        try:
            user = User.objects.get(username=f"tg_{tg_id}")
            if phone: user.phone_number = phone
            if not user.phone_number: return JsonResponse({"status": "error", "message": "Phone number is required."})
            otp = str(random.randint(100000, 999999))
            user.otp_code = otp; user.otp_expiry = timezone.now() + timedelta(minutes=5); user.save()
            send_gateway_otp(user.phone_number, otp)
            return JsonResponse({"status": "success", "message": "OTP sent! Check your Telegram Verification Codes."})
        except User.DoesNotExist: return JsonResponse({"status": "error", "message": "User not found."})

@csrf_exempt
def verify_otp(request):
    if request.method == "POST":
        data = json.loads(request.body); tg_id = data.get('tg_id'); otp = str(data.get('otp')).strip()
        try:
            user = User.objects.get(username=f"tg_{tg_id}")
            if user.otp_code == otp:
                user.otp_code = None; user.save(); return JsonResponse({"status": "success"})
            return JsonResponse({"status": "error", "message": "Invalid OTP."})
        except User.DoesNotExist: return JsonResponse({"status": "error", "message": "User not found."})

@csrf_exempt
def submit_deposit(request):
    if request.method == "POST":
        try:
            data = json.loads(request.body)
            tg_id = data.get('tg_id')
            amount_val = data.get('amount', 0)
            tx_id = data.get('tx_id', 'UNKNOWN')
            method = data.get('method', 'UNKNOWN')
            
            try:
                amount = Decimal(str(amount_val))
            except:
                return JsonResponse({"status": "error", "message": "Invalid amount format."})

            user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
            
            # Capture the transaction object so we can get its ID!
            tx = Transaction.objects.create(
                agent=user, 
                amount=amount, 
                note=f"TXID: {tx_id}", 
                type=f"DEPOSIT_{method.upper()}", 
                status="pending"
            )
            
            admin_group_id = "-5139316806"
            send_telegram_message(admin_group_id, f"🟢 <b>NEW DEPOSIT</b>\n<b>ID: {tx.id}</b>\nUser: <code>{tg_id}</code>\nAmount: {amount} ETB\nMethod: {method}\nTXID: {tx_id}\n\n<i>To approve, tap:</i>\n<code>/approve {tx.id}</code>")
            
            return JsonResponse({"status": "success", "message": "Deposit submitted! Waiting for Admin approval."})
            
        except Exception as e:
            print(f"CRITICAL DEPOSIT ERROR: {e}")
            return JsonResponse({"status": "error", "message": f"Server error: {str(e)}"})

@csrf_exempt
def submit_withdrawal(request):
    if request.method == "POST":
        try:
            data = json.loads(request.body)
            tg_id = data.get('tg_id')
            amount_val = data.get('amount', 0)
            
            try:
                amount = Decimal(str(amount_val))
            except:
                return JsonResponse({"status": "error", "message": "Invalid amount format."})

            user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
            
            if user.operational_credit < amount: 
                return JsonResponse({"status": "error", "message": "Insufficient balance!"})
            if amount < 50: 
                return JsonResponse({"status": "error", "message": "Minimum withdrawal is 50 ETB."})
            
            user.operational_credit -= amount
            user.save()
            
            tx = Transaction.objects.create(
                agent=user, 
                amount=amount, 
                note=f"To: {data.get('account')}", 
                type="WITHDRAWAL", 
                status="pending"
            )
            
            admin_group_id = "-5139316806"
            send_telegram_message(admin_group_id, f"🔴 <b>NEW WITHDRAWAL</b>\n<b>ID: {tx.id}</b>\nUser: <code>{tg_id}</code>\nAmount: {amount} ETB\nAccount: <code>{data.get('account')}</code>\nPhone: {user.phone_number}\n\n<i>To approve, tap:</i>\n<code>/approve {tx.id}</code>")
            
            return JsonResponse({"status": "success", "message": "Withdrawal requested successfully!"})
            
        except Exception as e:
            print(f"Withdrawal Error: {e}")
            return JsonResponse({"status": "error", "message": f"Server error: {str(e)}"})

@csrf_exempt
def submit_transfer(request):
    if request.method == "POST":
        try:
            data = json.loads(request.body)
            tg_id = data.get('tg_id')
            amount_val = data.get('amount', 0)
            target_account = data.get('account')
            
            try:
                amount = Decimal(str(amount_val))
            except:
                return JsonResponse({"status": "error", "message": "Invalid amount format."})

            sender, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
            
            if sender.operational_credit < amount: 
                return JsonResponse({"status": "error", "message": "Insufficient balance!"})
            if amount < 10: 
                return JsonResponse({"status": "error", "message": "Minimum transfer is 10 ETB."})
            
            receiver = User.objects.filter(phone_number=target_account).first() or User.objects.filter(username=f"tg_{target_account}").first()
            if not receiver: 
                return JsonResponse({"status": "error", "message": "Receiver account not found!"})
            if sender == receiver: 
                return JsonResponse({"status": "error", "message": "You cannot transfer to yourself!"})
            
            sender.operational_credit -= amount
            sender.save()
            
            receiver.operational_credit += amount
            receiver.save()
            
            tx_out = Transaction.objects.create(agent=sender, amount=amount, note=f"Transfer to {target_account}", type="TRANSFER_OUT", status="approved")
            Transaction.objects.create(agent=receiver, amount=amount, note=f"Transfer from {tg_id}", type="TRANSFER_IN", status="approved")
            
            admin_group_id = "-5139316806"
            send_telegram_message(admin_group_id, f"💸 <b>TRANSFER PROCESSED</b>\n<b>ID: {tx_out.id}</b>\nFrom: <code>{tg_id}</code>\nTo: <code>{target_account}</code>\nAmount: {amount} ETB")
            
            if receiver.telegram_id: 
                send_telegram_message(receiver.telegram_id, f"💸 <b>Transfer Received!</b>\nYou received {amount} ETB from user {tg_id}.")
            
            return JsonResponse({"status": "success", "message": f"Successfully transferred {amount} ETB!"})
            
        except Exception as e:
            print(f"Transfer Error: {e}")
            return JsonResponse({"status": "error", "message": f"Server error: {str(e)}"})

@csrf_exempt
def change_password(request):
    if request.method == "POST":
        data = json.loads(request.body)
        try:
            user = User.objects.get(username=f"tg_{data.get('tg_id')}")
            user.set_password(data.get('password'))
            user.save()
            return JsonResponse({"status": "success", "message": "Security PIN updated successfully!"})
        except: return JsonResponse({"status": "error", "message": "User not found."})

@csrf_exempt
def redeem_promo(request):
    if request.method == "POST":
        data = json.loads(request.body)
        tg_id = data.get('tg_id')
        promo_code = str(data.get('promo_code', '')).strip()
        try:
            user = User.objects.get(username=f"tg_{tg_id}")
            if getattr(user, 'used_promo_code', False): 
                return JsonResponse({"status": "error", "message": "You have already used a promo code!"})
            if promo_code == str(tg_id): 
                return JsonResponse({"status": "error", "message": "You cannot use your own code!"})
            
            friend = User.objects.filter(username=f"tg_{promo_code}").first()
            if not friend: 
                return JsonResponse({"status": "error", "message": "Invalid Promo Code!"})
                
            user.operational_credit += 10; user.used_promo_code = True; user.save()
            friend.operational_credit += 10; friend.save()
            
            Transaction.objects.create(agent=user, amount=10, note=f"Used promo code: {promo_code}", type="BONUS", status="approved")
            Transaction.objects.create(agent=friend, amount=10, note=f"Referral bonus from: {tg_id}", type="REFERRAL_BONUS", status="approved")
            
            if friend.telegram_id: 
                send_telegram_message(friend.telegram_id, f"🎉 <b>Referral Bonus!</b>\nA friend just used your promo code! <b>10 ETB</b> has been added to your balance.")
            
            return JsonResponse({"status": "success", "message": "🎉 Success! 10 ETB added to your balance."})
        except Exception as e: 
            return JsonResponse({"status": "error", "message": "User not found."})