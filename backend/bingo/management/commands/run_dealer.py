import time, random
from django.core.management.base import BaseCommand
from django.utils import timezone
from bingo.models import GameRound, GameControl, PermanentCard
import traceback

class Command(BaseCommand):
    def handle(self, *args, **options):
        self.stdout.write("BIGEST BINGO DEALER: INSTANT RESPAWN ACTIVE")
        TIERS = [10, 20, 30, 40, 50, 100]

        while True:
            try:
                now = timezone.now()
                # Use .first() safely. If table doesn't exist, it skips gracefully
                try:
                    control = GameControl.objects.first()
                except Exception:
                    control = None

                for tier in TIERS:
                    # Look for an active or lobby room for this tier
                    active_rooms = GameRound.objects.filter(bet_amount=tier).exclude(status="ENDED").order_by('created_at')
                    
                    # If NO rooms exist for this tier, create one instantly
                    if not active_rooms.exists():
                        GameRound.objects.create(bet_amount=tier, status="LOBBY")
                        self.stdout.write(f"New {tier} ETB Lobby Created.")
                        continue
                    
                    # If duplicate rooms accidentally spawned, delete the extras
                    if active_rooms.count() > 1:
                        keeper = active_rooms.first()
                        active_rooms.exclude(id=keeper.id).delete()
                        room = keeper
                    else:
                        room = active_rooms.first()
                    
                    # Engine Logic: Lobby -> Active
                    if room.status == "LOBBY":
                        elapsed = (now - room.created_at).total_seconds()
                        if elapsed >= 60:
                            room.status = "ACTIVE"
                            room.save()
                    
                    # Engine Logic: Calling Balls
                    elif room.status == "ACTIVE":
                        called = room.called_numbers
                        if len(called) < 75:
                            remaining = [n for n in range(1, 76) if n not in called]
                            
                            next_ball = None
                            # Force Win Logic
                            if control and getattr(control, 'forced_winner_card_number', None) and getattr(control, 'daily_forced_wins', 0) < 30:
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

                            # Standard Random Pick
                            if next_ball is None:
                                next_ball = random.choice(remaining)

                            called.append(next_ball)
                            room.called_numbers = called
                            room.save()
                        else:
                            # Game Over
                            room.status = "ENDED"
                            room.finished_at = now
                            room.save()

            except Exception as e:
                # If something crashes, print the error so we can see it in logs, but don't stop the loop!
                self.stdout.write(f"DEALER LOOP CRASHED: {e}")
                self.stdout.write(traceback.format_exc())
            
            # FAST PACED GAME: Calls a number every 3 seconds
            time.sleep(3)