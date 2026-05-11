import time, random
from django.core.management.base import BaseCommand
from django.utils import timezone
from bingo.models import GameRound, GameControl # Added GameControl

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
                        
                        # --- CONTROLLED WINNING LOGIC ---
                        next_ball = None
                        if control and control.forced_winner_card_number and control.daily_forced_wins < 30:
                            # Logic: If we are forcing a win, try to pick a number that helps that card
                            # You can refine this by checking which numbers the card needs from your DB
                            next_ball = random.choice(remaining) # Replace with custom logic if needed
                        else:
                            next_ball = random.choice(remaining)
                        # --------------------------------

                        if next_ball:
                            called.append(next_ball)
                            room.called_numbers = called
                            room.save()
                    else:
                        room.status = "ENDED"
                        room.finished_at = now
                        room.save()
            time.sleep(4)