from django.shortcuts import render
from django.http import HttpResponse
from rest_framework.views import APIView
from rest_framework.response import Response

def home(request):
    return HttpResponse("<h1>VladBingo Server is Online</h1><p>Visit /api/live/ for the Hall.</p>")

def live_view(request):
    return render(request, 'live_view.html')

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        return Response({"status": "ok"})
