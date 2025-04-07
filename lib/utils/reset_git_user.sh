#!/bin/bash

echo "🚨 Limpiando configuración global de Git..."
git config --global --unset user.name 2>/dev/null
git config --global --unset user.email 2>/dev/null
rm -f ~/.git-credentials
rm -f ~/.gitconfig

echo "🧹 Limpiando configuración local en subdirectorios (si aplica)..."
find . -type d -name ".git" | while read gitdir; do
    repodir=$(dirname "$gitdir")
    echo "➤ Limpiando $repodir"
    git -C "$repodir" config --unset user.name 2>/dev/null
    git -C "$repodir" config --unset user.email 2>/dev/null
done

echo "✅ Configuración de Git eliminada."

# Ayuda para borrar credenciales en Windows
echo ""
echo "🔐 Para borrar las credenciales guardadas en Windows:"
echo "1. Abrí el Panel de Control > Administrador de credenciales."
echo "2. Entrá en 'Credenciales de Windows'."
echo "3. Buscá entradas como 'git:https://github.com' o similares y borralas."

read -p "¿Querés configurar un nuevo usuario global ahora? (s/n): " answer
if [[ "$answer" == "s" || "$answer" == "S" ]]; then
    read -p "Nombre de usuario Git: " username
    read -p "Email de Git: " email
    git config --global user.name "$username"
    git config --global user.email "$email"
    echo "✅ Usuario configurado:"
    git config --global --list
else
    echo "👋 Podés configurar más tarde con:"
    echo "   git config --global user.name \"Tu Nombre\""
    echo "   git config --global user.email \"tu@email.com\""
fi
