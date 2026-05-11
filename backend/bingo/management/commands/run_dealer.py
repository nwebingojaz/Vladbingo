import time, random
from django.core.management.base import BaseCommand
from django.utils import timezone
from bingo.models import GameRound, GameControl, PermanentCard

class Command(BaseCommand):
    def handle(self, *args, **options):
        self.stdout.write("VLAD BINGO DEALER: INSTANT RESPAWN ACTIVE")
        TIERS = [10, 20, 30, 40, 50, 100]

        while True:
            now = timezone.now()
            # Fetch the control object once per loop
            control = GameControl.objects.first()
            
            for tier in TIERS:
                room = GameRound.objects.filter(bet_amount=tier).exclude(status="ENDED").first()
                
                if not room:
                    room = GameRound.objects.create(bet_amount=tier, status="LOBBY")
                    self.stdout.write(f"New {tier} ETB Lobby Created instantly.")
                
                elif room.status == "LOBBY":
                    elapsed = (now - room.created_at).total_seconds()
                    if elapsed >= 60:
                        room.status = "ACTIVE"
                        room.save()
                
                elif room.status == "ACTIVE":
                    called = room.called_numbers
                    if len(called) < 75:
                        remaining = [n for n in range(1, 76) if n not in called]
                        
                        # --- 100% EFFECTIVE CONTROLLED WINNING LOGIC ---
                        next_ball = None
                        if control and control.forced_winner_card_number and control.daily_forced_wins < 30:
                            try:
                                target_card = PermanentCard.objects.get(card_number=control.forced_winner_card_number)
                                # Flatten the 5x5 board into a simple list of numbers
                                board_nums = [num for row in target_card.board for num in row if isinstance(num, int)]
                                
                                # Only pick numbers the card actually needs
                                needed_numbers = [n for n in board_nums if n not in called]
                                
                                if needed_numbers:
                                    next_ball = random.choice(needed_numbers)
                                    self.stdout.write(f"FORCE WIN: Picking {next_ball} for card {control.forced_winner_card_number}")
                                
                                # If the card completes, mark the win and increment counter
                                if len(needed_numbers) == 1:
                                    control.daily_forced_wins += 1
                                    control.forced_winner_card_number = None
                                    control.save()
                            except Exception as e:
                                self.stdout.write(f"Force win error: {e}")

                        # If no forced ball chosen, pick randomly from remaining
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