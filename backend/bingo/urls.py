from django.urls import path
from .views import live_view, get_user_card, check_win
urlpatterns = [
    path('live/', live_view),
    path('user-card-data/<int:tg_id>/', get_user_card),
    path('check-win/<int:tg_id>/', check_win),
]
