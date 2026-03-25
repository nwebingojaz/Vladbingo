from django.urls import path
from .views import live_view, get_game_info, check_win
urlpatterns = [
    path('live/', live_view),
    path('game-info/<int:tg_id>/', get_game_info),
    path('check-win/<int:tg_id>/', check_win),
]
