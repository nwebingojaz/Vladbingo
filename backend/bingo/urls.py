from django.urls import path
from .views import live_view, get_card_data
urlpatterns = [
    path('live/', live_view, name='live_view'),
    path('card-data/<int:card_num>/', get_card_data),
]
