from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone

class Migration(migrations.Migration):
    initial = True
    dependencies = [
        ('auth', '0012_alter_user_first_name_max_length'),
    ]
    operations = [
        migrations.CreateModel(
            name='GameControl',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('forced_winner_card_number', models.IntegerField(blank=True, null=True)),
                ('daily_forced_wins', models.IntegerField(default=0)),
                ('last_reset', models.DateField(default=django.utils.timezone.now)),
            ],
        ),
        migrations.CreateModel(
            name='PermanentCard',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('card_number', models.PositiveSmallIntegerField(unique=True)),
                ('board', models.JSONField()),
            ],
        ),
        migrations.CreateModel(
            name='User',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('password', models.CharField(max_length=128, verbose_name='password')),
                ('last_login', models.DateTimeField(blank=True, null=True, verbose_name='last login')),
                ('is_superuser', models.BooleanField(default=False)),
                ('username', models.CharField(max_length=150, unique=True)),
                ('is_staff', models.BooleanField(default=False)),
                ('is_active', models.BooleanField(default=True)),
                ('date_joined', models.DateTimeField(default=django.utils.timezone.now)),
                ('operational_credit', models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                ('selected_cards', models.JSONField(default=list)),
                ('bot_state', models.CharField(default='REG_NAME', max_length=30)),
                ('real_name', models.CharField(blank=True, max_length=100)),
                ('phone_number', models.CharField(blank=True, max_length=20)),
                ('telegram_id', models.BigIntegerField(blank=True, null=True)),
                ('otp_code', models.CharField(blank=True, max_length=6, null=True)),
                ('otp_expiry', models.DateTimeField(blank=True, null=True)),
                ('groups', models.ManyToManyField(blank=True, related_name='user_set', to='auth.group')),
                ('user_permissions', models.ManyToManyField(blank=True, related_name='user_set', to='auth.permission')),
            ],
            options={'verbose_name': 'user', 'verbose_name_plural': 'users', 'abstract': False},
        ),
        migrations.CreateModel(
            name='GameRound',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('called_numbers', models.JSONField(default=list)),
                ('players', models.JSONField(default=dict)),
                ('bet_amount', models.DecimalField(decimal_places=2, max_digits=10)),
                ('status', models.CharField(default='LOBBY', max_length=20)),
                ('winner_username', models.CharField(blank=True, max_length=100, null=True)),
                ('winner_prize', models.DecimalField(decimal_places=2, default=0, max_digits=10)),
                ('finished_at', models.DateTimeField(blank=True, null=True)),
            ],
        ),
        migrations.CreateModel(
            name='Transaction',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('timestamp', models.DateTimeField(default=django.utils.timezone.now)),
                ('amount', models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                ('type', models.CharField(default='DEPOSIT', max_length=20)),
                ('note', models.TextField(default='')),
                ('status', models.CharField(default='pending', max_length=20)),
                ('agent', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to=settings.AUTH_USER_MODEL)),
            ],
        ),
    ]