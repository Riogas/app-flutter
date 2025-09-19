// Ejemplo de cómo agregar acceso a la página de debug
// Puedes agregar esto en tu SettingsPage o crear un botón flotante

import 'package:flutter/material.dart';
import '../pages/native_log_debug_page.dart';

class DebugAccessWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => NativeLogDebugPage()),
        );
      },
      icon: Icon(Icons.bug_report),
      label: Text('Debug Logs'),
      backgroundColor: Colors.orange,
    );
  }
}

// O como un ListTile en settings:
class DebugSettingsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.developer_mode, color: Colors.orange),
      title: Text('Debug del Sistema GPS'),
      subtitle: Text('Ver logs y estado del servicio'),
      trailing: Icon(Icons.arrow_forward_ios),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => NativeLogDebugPage()),
        );
      },
    );
  }
}
