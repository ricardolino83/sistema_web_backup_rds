# landingpage/urls.py 
from django.urls import path
from . import views

urlpatterns = [
    path('', views.home, name='home'), 
    # Adicionaremos URLs de login/logout/callback aqui depois
]