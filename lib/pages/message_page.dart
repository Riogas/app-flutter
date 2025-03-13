import 'package:flutter/material.dart';
import '../services/firebase_service.dart'; // Asegúrate de usar la ruta correcta
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                var mensaje =
                    snapshot.data![index].data() as Map<String, dynamic>;
                bool isRead = mensaje.containsKey('FchHoraLeido');
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15.0),
                    ),
                    elevation: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              mensaje['Mensaje'] ?? 'Sin contenido',
                              style: TextStyle(
                                fontWeight: isRead
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                                color: isRead ? Colors.black : Colors.red,
                                fontSize: 16.0,
                              ),
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
                    ),
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
