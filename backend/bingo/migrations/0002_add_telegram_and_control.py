from django.db import migrations, models

class Migration(migrations.Migration):

    dependencies = [
        ('bingo', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='telegram_id',
            field=models.BigIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='user',
            name='otp_code',
            field=models.CharField(blank=True, max_length=6, null=True),
        ),
        migrations.AddField(
            model_name='user',
            name='otp_expiry',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.CreateModel(
            name='GameControl',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('forced_winner_card_number', models.IntegerField(blank=True, null=True)),
                ('daily_forced_wins', models.IntegerField(default=0)),
                ('last_reset', models.DateField(auto_now_add=True)),
            ],
        ),
    ]