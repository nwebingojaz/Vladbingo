from django.core.management.base import BaseCommand
from bingo.models import User
import os

class Command(BaseCommand):
    def handle(self, *args, **options):
        username = "admin"
        password = "VladBingoPassword123" # You can change this later in Admin
        if not User.objects.filter(username=username).exists():
            User.objects.create_superuser(username=username, password=password, email="admin@vlad.com")
            self.stdout.write("✅ Admin Created: User: admin / Pass: VladBingoPassword123")
        else:
            self.stdout.write("ℹ️ Admin already exists.")
