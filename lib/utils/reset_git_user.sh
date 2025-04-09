#!/bin/bash

# 🚨 Limpia la configuración global de Git
# Elimina el nombre de usuario y correo electrónico configurados globalmente
# También elimina las credenciales y el archivo de configuración global

echo "🚨 Limpiando configuración global de Git..."
git config --global --unset user.name 2>/dev/null # Elimina el nombre de usuario global
git config --global --unset user.email 2>/dev/null # Elimina el correo electrónico global
rm -f ~/.git-credentials # Borra las credenciales almacenadas globalmente
rm -f ~/.gitconfig # Borra el archivo de configuración global de Git

# 🧹 Limpia la configuración local de Git en subdirectorios
# Busca todos los directorios .git y elimina configuraciones locales de usuario

echo "🧹 Limpiando configuración local en subdirectorios (si aplica)..."
find . -type d -name ".git" | while read gitdir; do
    repodir=$(dirname "$gitdir") # Obtiene el directorio del repositorio
    echo "➤ Limpiando $repodir"
    git -C "$repodir" config --unset user.name 2>/dev/null # Elimina el nombre de usuario local
    git -C "$repodir" config --unset user.email 2>/dev/null # Elimina el correo electrónico local
done

# ✅ Mensaje de confirmación
echo "✅ Configuración de Git eliminada."

# 🔐 Ayuda para borrar credenciales en Windows
# Proporciona instrucciones para eliminar credenciales almacenadas en el Administrador de Credenciales de Windows
echo ""
echo "🔐 Para borrar las credenciales guardadas en Windows:"
echo "1. Abrí el Panel de Control > Administrador de credenciales."
echo "2. Entrá en 'Credenciales de Windows'."
echo "3. Buscá entradas como 'git:https://github.com' o similares y borralas."

# Pregunta al usuario si desea configurar un nuevo usuario global
read -p "¿Querés configurar un nuevo usuario global ahora? (s/n): " answer
if [[ "$answer" == "s" || "$answer" == "S" ]]; then
    # Solicita el nombre de usuario y el correo electrónico para configurarlos globalmente
    read -p "Nombre de usuario Git: " username
    read -p "Email de Git: " email
    git config --global user.name "$username" # Configura el nombre de usuario global
    git config --global user.email "$email" # Configura el correo electrónico global
    echo "✅ Usuario configurado:"
    git config --global --list # Muestra la configuración global actual
else
    # Mensaje para configurar más tarde
    echo "👋 Podés configurar más tarde con:"
    echo "   git config --global user.name \"Tu Nombre\""
    echo "   git config --global user.email \"tu@email.com\""
fi
