from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone
from django.db.models.signals import pre_save
from django.dispatch import receiver

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    bot_state = models.CharField(max_length=30, default="REG_NAME")
    real_name = models.CharField(max_length=100, blank=True)
    phone_number = models.CharField(max_length=20, blank=True)
    # Added for Telegram Verification
    telegram_id = models.BigIntegerField(null=True, blank=True)
    otp_code = models.CharField(max_length=6, null=True, blank=True)
    otp_expiry = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"{self.real_name} (@{self.username.replace('tg_', '')})"

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

    def __str__(self):
        return f"Card #{self.card_number}"

class GameRound(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    called_numbers = models.JSONField(default=list)
    players = models.JSONField(default=dict)
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, default="LOBBY")
    winner_username = models.CharField(max_length=100, null=True, blank=True)
    winner_prize = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    finished_at = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"Room {int(self.bet_amount)} ETB - {self.status}"

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    type = models.CharField(max_length=20, default="DEPOSIT")
    note = models.TextField(default="")
    status = models.CharField(max_length=20, default="pending") # pending, approved, rejected

    def __str__(self):
        return f"{self.type} - {self.amount} ETB ({self.status})"

class GameControl(models.Model):
    forced_winner_card_number = models.IntegerField(null=True, blank=True)
    daily_forced_wins = models.IntegerField(default=0)
    last_reset = models.DateField(default=timezone.now)

    def save(self, *args, **kwargs):
        if self.last_reset != timezone.now().date():
            self.daily_forced_wins = 0
            self.last_reset = timezone.now().date()
        super().save(*args, **kwargs)

    def __str__(self):
        return "Master Game Control Settings"

# ==========================================
# AUTOMATIC BALANCE HANDLER (DJANGO SIGNAL)
# ==========================================
@receiver(pre_save, sender=Transaction)
def handle_transaction_approval(sender, instance, **kwargs):
    # Check if this transaction already exists in the database
    if instance.id:
        try:
            old_transaction = Transaction.objects.get(id=instance.id)
            
            # If Admin changes status from "pending" to "approved"
            if old_transaction.status == 'pending' and instance.status == 'approved':
                
                # DEPOSIT: Give the player their money!
                if instance.type.startswith('DEPOSIT'):
                    user = instance.agent
                    user.operational_credit += instance.amount
                    user.save()
                    
            # If Admin changes status from "pending" to "rejected"
            if old_transaction.status == 'pending' and instance.status == 'rejected':
                
                # WITHDRAWAL REJECTED: Refund the money back to the player
                if instance.type == 'WITHDRAWAL':
                    user = instance.agent
                    user.operational_credit += instance.amount
                    user.save()
                    
        except Transaction.DoesNotExist:
            pass