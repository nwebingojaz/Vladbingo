import time, random, traceback
from django.core.management.base import BaseCommand
from django.utils import timezone
from channels.layers import get_channel_layer 
from asgiref.sync import async_to_sync           
from bingo.models import GameRound, GameControl, PermanentCard

class Command(BaseCommand):
    def handle(self, *args, **options):
        self.stdout.write("BIGEST BINGO DEALER: ENGINE STARTED (WEBSOCKET MODE)")
        TIERS = [10, 20, 30, 40, 50, 100]
        channel_layer = get_channel_layer() 

        while True:
            try:
                now = timezone.now()
                control = GameControl.objects.first() if GameControl.objects.exists() else None

                for tier in TIERS:
                    # FIX: Safely exclude ENDED and ANNOUNCED so it ALWAYS creates a new lobby!
                    active_rooms = GameRound.objects.filter(bet_amount=tier).exclude(status__in=["ENDED", "ANNOUNCED"]).order_by('created_at')
                    
                    if not active_rooms.exists():
                        GameRound.objects.create(bet_amount=tier, status="LOBBY")
                        continue
                    
                    room = active_rooms.first()
                    
                    if room.status == "LOBBY":
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

                            async_to_sync(channel_layer.group_send)(
                                f'game_{room.id}',
                                {
                                    'type': 'bingo_message',
                                    'message': {
                                        'action': 'new_ball',
                                        'ball': next_ball,
                                        'called_count': len(called)
                                    }
                                }
                            )
                        else:
                            room.status = "ENDED"
                            room.finished_at = now
                            room.save(update_fields=['status', 'finished_at'])
                            
                            async_to_sync(channel_layer.group_send)(
                                f'game_{room.id}',
                                {'type': 'bingo_message', 'message': {'action': 'game_ended'}}
                            )

            except Exception as e:
                self.stdout.write(f"ENGINE ERROR: {e}")
            
            time.sleep(3)