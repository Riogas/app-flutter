import 'package:flutter/material.dart';
import '../services/firebase_service.dart'; // Asegúrate de usar la ruta correcta
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/riogas_service.dart'; // Import the RioGasService
import 'package:intl/intl.dart'; // Import the intl package for date formatting

class MessagePage extends StatefulWidget {
  @override
  _MessagePageState createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  final FirebaseService _firebaseService = FirebaseService();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  List<String> _readMessageIds = [];

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _listenToMessages();
    _markMessagesAsRead(); // Mark messages as read when the page is accessed
  }

  void _initializeNotifications() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _listenToMessages() {
    _firebaseService.getMensajesStream().listen((messages) {
      setState(() {
        _checkForNewMessages(messages);
      });
    });
  }

  void _checkForNewMessages(List<DocumentSnapshot> messages) {
    for (var message in messages) {
      if (!_readMessageIds.contains(message.id)) {
        _showNotification(message);
        _readMessageIds.add(message.id);
      }
    }
  }

  Future<void> _showNotification(DocumentSnapshot message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'your_channel_id',
      'your_channel_name',
      channelDescription: 'your_channel_description',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      0,
      'Nuevo Mensaje',
      'Mensaje: ${message['Mensaje'] ?? 'Sin contenido'}',
      platformChannelSpecifics,
      payload: 'item x',
    );
  }

  Future<void> _markMessagesAsRead() async {
    var messages = await _firebaseService.getUnreadMessages();
    for (var message in messages) {
      await _firebaseService.markMessageAsRead(message.id);
      await RioGasService.descargaLecturaMensajes(
        1, // escenarioId
        1, // movilId
        int.parse(message.id), // messageId
        'usuario', // usuario
        'nroSesion', // nroSesion
        'termMobileEquipo', // termMobileEquipo
        'lectDesc', // lectDesc
        DateTime.now().toIso8601String(), // fechaHoraCmbEst
        'inAux1', // inAux1
        'inAux2', // inAux2
        'latitud', // latitud
        'longitud', // longitud
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mensajes'),
        actions: [
          Row(
            children: [
              Text(
                'Borrar Todo',
                style: TextStyle(color: Colors.red),
              ),
              IconButton(
                icon: Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  // Acción para borrar todos los mensajes
                },
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<DocumentSnapshot>>(
        stream: _firebaseService.getMensajesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No hay mensajes disponibles.'));
          } else {
            var messages = snapshot.data!;
            messages.sort((a, b) {
              var aDate = (a['FchHoraCreado'] as Timestamp).toDate();
              var bDate = (b['FchHoraCreado'] as Timestamp).toDate();
              return bDate.compareTo(aDate);
            });
            return ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, index) {
                var mensaje = messages[index].data() as Map<String, dynamic>;
                bool isRead = mensaje.containsKey('FchHoraLeido');
                String formattedDate = mensaje['FchHoraCreado'] != null
                    ? DateFormat('dd/MM/yyyy HH:mm').format(
                        (mensaje['FchHoraCreado'] as Timestamp).toDate())
                    : '';
                return Container(
                  color: isRead ? Colors.white : Colors.blue.withOpacity(0.1),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isRead
                                ? Icons.mark_email_read
                                : Icons.mark_email_unread,
                            color: isRead ? Colors.grey : Colors.blue,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mensaje['Mensaje'] ?? 'Sin contenido',
                                  style: TextStyle(
                                    fontWeight: isRead
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                    color: isRead ? Colors.black : Colors.red,
                                    fontSize: 16.0,
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  formattedDate,
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              // Acción para borrar el mensaje individual
                            },
                          ),
                        ],
                      ),
                      Divider(), // Add a horizontal line separator
                    ],
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}
