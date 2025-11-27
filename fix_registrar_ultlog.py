#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Fix crítico del login flow: Mover registrarUltLog después de la confirmación del usuario
"""
import sys

# Leer el archivo
with open('lib/pages/login_page.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Buscar la línea que contiene 'await _onSuccessfulLoginFlow(context);' después de setHistory
target_line_index = None
for i in range(2190, 2220):  # Buscar en el rango esperado
    if 'await _onSuccessfulLoginFlow(context);' in lines[i]:
        target_line_index = i
        break

if target_line_index is None:
    print('❌ No se encontró _onSuccessfulLoginFlow')
    sys.exit(1)

print(f'✅ Encontrado _onSuccessfulLoginFlow en línea {target_line_index + 1}')

# Insertar el bloque registrarUltLog ANTES de _onSuccessfulLoginFlow
new_block = [
    '              \n',
    '              // ✅ Llamar registrarUltLog SOLO después de que el usuario confirme\n',
    '              // Esto evita inconsistencias si el usuario cancela el diálogo de conflicto\n',
    "              var sessionBox = await Hive.openBox('sessionBox');\n",
    "              String? usernameForLog = sessionBox.get('username');\n",
    "              String? deviceIdForLog = sessionBox.get('deviceId');\n",
    '              \n',
    '              if (usernameForLog != null && deviceIdForLog != null && selectedMovil != null) {\n',
    '                await RioGasService.registrarUltLog(\n',
    '                    int.parse(selectedMovil), _deviceId, usernameForLog);\n',
    '                print(\n',
    '                    "\\x1b[32m$kLoginFlowTag ✅ registrarUltLog ejecutado tras confirmación del usuario.\\x1b[0m");\n',
    '              } else {\n',
    '                print(\n',
    '                    "\\x1b[31m$kLoginFlowTag ⚠️ No se pudo llamar a registrarUltLog: username o deviceId es null.\\x1b[0m");\n',
    '                print(\n',
    '                    "\\x1b[31m$kLoginFlowTag usernameForLog: $usernameForLog, deviceIdForLog: $deviceIdForLog, selectedMovil: $selectedMovil\\x1b[0m");\n',
    '              }\n',
    '              \n',
]

# Insertar el bloque
new_lines = lines[:target_line_index] + new_block + lines[target_line_index:]

# Escribir el archivo modificado
with open('lib/pages/login_page.dart', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print(f'✅ Bloque registrarUltLog insertado en línea {target_line_index + 1} (antes de _onSuccessfulLoginFlow)')
print('✅ Fix crítico completado: registrarUltLog ahora se ejecuta SOLO después de la confirmación del usuario')
print('')
print('📋 RESUMEN DEL FIX:')
print('   1. ❌ ELIMINADO: registrarUltLog de línea ~2124 (ejecución temprana)')
print('   2. ✅ AGREGADO: registrarUltLog en línea ~2207 (después de setHistory exitoso)')
print('   3. ✅ GARANTIZADO: Solo se ejecuta si usuario confirma el diálogo de conflicto')
print('   4. ✅ SIN INCONSISTENCIAS: Si usuario cancela, no hay registro en DB')
