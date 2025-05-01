from django.shortcuts import render

def home(request):
    # Por enquanto, apenas renderiza um template HTML
    # Mais tarde, adicionaremos lógica de autenticação aqui
    context = {
        'user': request.user if request.user.is_authenticated else None 
        # Passa o usuário para o template se ele estiver logado (via sessão Django)
    }
    return render(request, 'landingpage/home.html', context)