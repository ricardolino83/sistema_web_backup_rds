# core/urls.py
from django.urls import path
from . import views

app_name = 'core'
urlpatterns = [
    # A view 'home' agora também lida com a listagem S3
    path('', views.home, name='home'),

    # A linha abaixo foi REMOVIDA:
    # path('backups/', views.list_s3_backups, name='list_backups'),
]