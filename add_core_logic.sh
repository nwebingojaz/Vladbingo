#!/bin/bash
# Adding Core Bingo Logic to VladBingo

# 1. Create manage.py
cat <<EOF > backend/manage.py
#!/usr/bin/env python
import os, sys
if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
    from django.core.management import execute_from_command_line
    execute_from_command_line(sys.argv)
EOF
chmod +x backend/manage.py

# 2. Create Django Settings
cat <<EOF > backend/vlad_bingo/settings.py
import os, dj_database_url
from pathlib import Path
BASE_DIR = Path(__file__).resolve().parent.parent
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "dev-secret")
DEBUG = False
ALLOWED_HOSTS = ["*"]
INSTALLED_APPS = [
    "django.contrib.admin", "django.contrib.auth", "django.contrib.contenttypes",
    "django.contrib.sessions", "django.contrib.messages", "django.contrib.staticfiles",
    "rest_framework", "corsheaders", "channels", "bingo",
]
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware", "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware", "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware", "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
]
ROOT_URLCONF = "vlad_bingo.urls"
WSGI_APPLICATION = "vlad_bingo.wsgi.application"
ASGI_APPLICATION = "vlad_bingo.asgi.application"
DATABASES = {"default": dj_database_url.config(conn_max_age=600)}
CHANNEL_LAYERS = {"default": {"BACKEND": "channels_redis.core.RedisChannelLayer", "CONFIG": {"hosts": [os.environ.get("REDIS_URL")]}}}
AUTH_USER_MODEL = "bingo.User"
STATIC_URL = "/static/"
STATIC_ROOT = os.path.join(BASE_DIR, "staticfiles")
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
EOF

# 3. Create core Bingo Models
cat <<EOF > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    is_agent = models.BooleanField(default=False)
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    running_balance = models.DecimalField(max_digits=12, decimal_places=2)
    note = models.TextField(blank=True)

class GameRound(models.Model):
    created_at = models.DateTimeField(default=timezone.now)
    called_numbers = models.JSONField(default=list)
    status = models.CharField(max_length=16, default="PENDING")
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
EOF

# 4. Create necessary __init__ and asgi files
touch backend/vlad_bingo/__init__.py backend/bingo/__init__.py
cat <<EOF > backend/vlad_bingo/asgi.py
import os
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
application = ProtocolTypeRouter({"http": get_asgi_application()})
EOF

cat <<EOF > backend/vlad_bingo/urls.py
from django.contrib import admin
from django.urls import path
urlpatterns = [path('admin/', admin.site.urls)]
EOF

echo "✅ Core Django Logic Added!"
