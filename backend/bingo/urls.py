from django.urls import path
from .views import (
    live_view, lobby_info, join_room, get_history, 
    get_game_info, get_card_data, check_win,
    send_otp, verify_otp, submit_deposit,
    submit_withdrawal, submit_transfer, change_password # <-- Added new imports
)

urlpatterns = [
    path('live/', live_view),
    path('lobby-info/<int:tg_id>/', lobby_info),
    
    # Updated: Changed <int:card_num> to <str:card_num> to allow multiple cards (e.g. "12,45,89")
    path('join-room/<int:tg_id>/<int:bet>/<str:card_num>/', join_room),
    
    path('card-data/<int:num>/', get_card_data),
    path('game-info/<int:game_id>/<int:tg_id>/', get_game_info),
    path('history/<int:tg_id>/', get_history),
    
    # Bingo Check route
    path('check-win/<int:game_id>/<int:tg_id>/', check_win),
    
    # Manual Deposit & OTP Routes
    path('send-otp/', send_otp),
    path('verify-otp/', verify_otp),
    path('submit-deposit/', submit_deposit),
    
    # NEW: Wallet & Security Routes
    path('submit-withdrawal/', submit_withdrawal),
    path('submit-transfer/', submit_transfer),
    path('change-password/', change_password),
]