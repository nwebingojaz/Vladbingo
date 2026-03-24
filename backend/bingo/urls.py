from django.urls import path
from .views import live_view, get_user_card
urlpatterns = [
    path('live/', live_view, name='live_view'),
    path('user-card-data/<int:tg_id>/', get_user_card),
]
