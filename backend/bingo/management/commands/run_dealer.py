import time, random, traceback
from django.core.management.base import BaseCommand
from django.utils import timezone
from bingo.models import GameRound, GameControl, PermanentCard

class Command(BaseCommand):
    def handle(self, *args, **options):
        self.stdout.write("BIGEST BINGO DEALER: ENGINE STARTED (STABLE MODE)")
        TIERS = [10, 20, 30, 40, 50, 100]

        while True:
            try:
                now = timezone.now()
                try: control = GameControl.objects.first()
                except: control = None

                for tier in TIERS:
                    active_rooms = GameRound.objects.filter(bet_amount=tier).exclude(status="ENDED").order_by('created_at')
                    
                    if not active_rooms.exists():
                        GameRound.objects.create(bet_amount=tier, status="LOBBY")
                        continue
                    
                    if active_rooms.count() > 1:
                        keeper = active_rooms.first()
                        GameRound.objects.filter(bet_amount=tier).exclude(id=keeper.id).exclude(status="ENDED").delete()
                        room = keeper
                    else:
                        room = active_rooms.first()
                    
                    # -----------------------------
                    # STATE MACHINE: LOBBY -> ACTIVE
                    # -----------------------------
                    if room.status == "LOBBY":
                        elapsed = (now - room.created_at).total_seconds()
                        
                        # CRITICAL FIX: Only start the game if time is up AND there are players.
                        # If time is up but 0 players, just reset the clock so the room ID stays the same!
                        if elapsed >= 60:
                            if not room.players:
                                room.created_at = now  # Reset timer, keep the same room
                                room.save(update_fields=['created_at'])
                            else:
                                room.status = "ACTIVE"
                                room.save(update_fields=['status'])
                    
                    # -----------------------------
                    # STATE MACHINE: CALLING BALLS
                    # -----------------------------
                    elif room.status == "ACTIVE":
                        called = room.called_numbers
                        if len(called) < 75:
                            remaining = [n for n in range(1, 76) if n not in called]
                            next_ball = None
                            
                            if control and getattr(control, 'forced_winner_card_number', None) and getattr(control, 'daily_forced_wins', 0) < 30:
                                try:
                                    target_card = PermanentCard.objects.get(card_number=control.forced_winner_card_number)
                                    board_nums = [num for row in target_card.board for num in row if isinstance(num, int)]
                                    needed_numbers = [n for n in board_nums if n not in called]
                                    
                                    if needed_numbers: next_ball = random.choice(needed_numbers)
                                    if len(needed_numbers) == 1:
                                        control.daily_forced_wins += 1
                                        control.forced_winner_card_number = None
                                        control.save()
                                except: pass

                            if next_ball is None: next_ball = random.choice(remaining)

                            called.append(next_ball)
                            room.called_numbers = called
                            room.save(update_fields=['called_numbers'])
                        else:
                            room.status = "ENDED"
                            room.finished_at = now
                            room.save(update_fields=['status', 'finished_at'])

            except Exception as e:
                self.stdout.write(f"ENGINE ERROR: {e}")
            
            time.sleep(3)