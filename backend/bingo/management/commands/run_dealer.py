import time, random
from django.core.management.base import BaseCommand
from django.utils import timezone
from bingo.models import GameRound, GameControl, PermanentCard

class Command(BaseCommand):
    def handle(self, *args, **options):
        self.stdout.write("BIGEST BINGO DEALER: INSTANT RESPAWN ACTIVE")
        TIERS = [10, 20, 30, 40, 50, 100]

        while True:
            now = timezone.now()
            control = GameControl.objects.first()
            
            for tier in TIERS:
                # Get ALL rooms for this tier that are NOT ended
                active_rooms = GameRound.objects.filter(bet_amount=tier).exclude(status="ENDED").order_by('created_at')
                
                # If no active rooms exist at all, create EXACTLY ONE lobby
                if not active_rooms.exists():
                    GameRound.objects.create(bet_amount=tier, status="LOBBY")
                    self.stdout.write(f"New {tier} ETB Lobby Created instantly.")
                    continue # Move to next tier
                
                # If there is more than 1 room active for this tier (A duplicate glitch happened!)
                if active_rooms.count() > 1:
                    # Keep the oldest one running, delete the rest to fix the UI instantly
                    keeper = active_rooms.first()
                    active_rooms.exclude(id=keeper.id).delete()
                    room = keeper
                else:
                    room = active_rooms.first()
                
                # Handle Lobby State
                if room.status == "LOBBY":
                    elapsed = (now - room.created_at).total_seconds()
                    if elapsed >= 60:
                        room.status = "ACTIVE"
                        room.save()
                
                # Handle Active State (Calling numbers)
                elif room.status == "ACTIVE":
                    called = room.called_numbers
                    if len(called) < 75:
                        remaining = [n for n in range(1, 76) if n not in called]
                        
                        # --- 100% EFFECTIVE CONTROLLED WINNING LOGIC ---
                        next_ball = None
                        if control and control.forced_winner_card_number and control.daily_forced_wins < 30:
                            try:
                                target_card = PermanentCard.objects.get(card_number=control.forced_winner_card_number)
                                board_nums = [num for row in target_card.board for num in row if isinstance(num, int)]
                                needed_numbers = [n for n in board_nums if n not in called]
                                
                                if needed_numbers:
                                    next_ball = random.choice(needed_numbers)
                                
                                if len(needed_numbers) == 1:
                                    control.daily_forced_wins += 1
                                    control.forced_winner_card_number = None
                                    control.save()
                            except Exception as e:
                                self.stdout.write(f"Force win error: {e}")

                        # Pick randomly if no forced ball
                        if next_ball is None:
                            next_ball = random.choice(remaining)
                        # ------------------------------------------------

                        called.append(next_ball)
                        room.called_numbers = called
                        room.save()
                    else:
                        room.status = "ENDED"
                        room.finished_at = now
                        room.save()
                        
            time.sleep(4)