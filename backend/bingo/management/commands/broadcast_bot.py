import time
from django.core.management.base import BaseCommand
from django.conf import settings
import requests
from bingo.models import GameRound

class Command(BaseCommand):
    def handle(self, *args, **options):
        self.stdout.write("BROADCASTER BOT ACTIVE")
        bot_token = settings.TELEGRAM_BOT_TOKEN
        channel_id = settings.CHANNEL_ID # e.g., @vladbingo

        while True:
            # Check for rooms about to start
            lobbies = GameRound.objects.filter(status="LOBBY")
            for room in lobbies:
                # If room is very close to starting (e.g., 60 seconds elapsed)
                # You can add logic to send "Starting in 1 minute" messages here
                pass

            # Check for rooms that just finished
            finished_rooms = GameRound.objects.filter(status="ENDED", winner_username__isnull=False)
            for room in finished_rooms:
                msg = f"🏆 *Game Finished!* \n\n💰 Bet: {room.bet_amount} ETB\n👤 Winner: {room.winner_username}\n🎁 Prize: {room.winner_prize} ETB\n\nPlay now: {settings.WEB_APP_URL}"
                
                requests.get(f"https://api.telegram.org/bot{bot_token}/sendMessage", params={
                    "chat_id": channel_id,
                    "text": msg,
                    "parse_mode": "Markdown"
                })
                
                # Mark as 'ANNOUNCED' so we don't spam the same winner
                room.status = "ANNOUNCED"
                room.save()

            time.sleep(10) # Check every 10 seconds