import 'package:flutter/material.dart';
import '../services/firebase_service.dart'; // Asegúrate de usar la ruta correcta
import 'dart:async'; // Import the dart:async package for StreamSubscription
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/riogas_service.dart'; // Import the RioGasService
import 'package:intl/intl.dart'; // Import the intl package for date formatting
import '../services/location_service.dart'; // Import the LocationService
import 'package:geolocator/geolocator.dart'; // Import the Geolocator package
import 'package:hive/hive.dart'; // Import the Hive package

class MessagePage extends StatefulWidget {
  @override
  _MessagePageState createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  final FirebaseService _firebaseService = FirebaseService();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  List<String> _readMessageIds = [];
  StreamSubscription<List<DocumentSnapshot>>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _listenToMessages();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _initializeNotifications() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _listenToMessages() {
    _messageSubscription =
        _firebaseService.getMensajesStream().listen((messages) {
      if (mounted) {
        setState(() {
          _checkForNewMessages(messages);
        });
      }
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

  Future<void> _markMessageAsRead(DocumentSnapshot message) async {
    var box = await Hive.openBox('sessionBox');
    String? escenario = box.get('escenario');
    String? movil = box.get('movil');
    String? username = box.get('username');
    String? deviceId = box.get('deviceId');

    print('📦 Datos obtenidos de Hive:');
    print('Escenario: $escenario');
    print('Movil: $movil');
    print('Username: $username');
    print('DeviceId: $deviceId');

    if (escenario == null ||
        movil == null ||
        username == null ||
        deviceId == null) {
      print('❌ No se pudo obtener los datos necesarios de Hive.');
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      forceAndroidLocationManager: true,
    );

    print(
        '📍 Ubicación obtenida: Lat ${position.latitude}, Lng ${position.longitude}');

    var data = message.data() as Map<String, dynamic>;

    // Extract numeric part from message.id
    final numericIdMatch = RegExp(r'\d+').firstMatch(message.id);
    if (numericIdMatch == null) {
      print('❌ No se pudo extraer un ID numérico del mensaje: ${message.id}');
      return;
    }
    int messageId = int.parse(numericIdMatch.group(0)!);

    if (data.containsKey('FchHoraLeido')) {
      print('📨 Mensaje ya leído: $messageId');
      return;
    }

    print('📨 Marcando mensaje como leído: $messageId');
    await _firebaseService.markMessageAsRead(message.id);
    print('📨 Enviando datos al servicio descargaLecturaMensajes:');
    print('EscenarioId: ${int.parse(escenario)}');
    print('MovilId: ${int.parse(movil)}');
    print('MessageId: $messageId');
    print('Usuario: $username');
    print('NroSesion: ');
    print('TermMobileEquipo: $deviceId');
    print('LectDesc: LECTURA');
    print('FechaHoraCmbEst: ${DateTime.now().toIso8601String()}');
    print('INAux1: ');
    print('INAux2: ');
    print('Latitud: ${position.latitude}');
    print('Longitud: ${position.longitude}');

    await RioGasService.descargaLecturaMensajes(
      int.parse(escenario), // escenarioId
      int.parse(movil), // movilId
      messageId, // messageId
      username, // usuario
      '', // nroSesion
      deviceId, // termMobileEquipo
      'LECTURA', // lectDesc
      DateTime.now().toIso8601String(), // fechaHoraCmbEst
      '', // inAux1
      '', // inAux2
      position.latitude.toString(), // latitud
      position.longitude.toString(), // longitud
    );

    if (mounted) {
      setState(() {
        _readMessageIds.add(message.id);
      });
    }
  }

  void _deleteMessage(DocumentSnapshot message) async {
    await _firebaseService
        .updateMessageField(message.id, {'VisibleEnApp': 'N'});
    if (mounted) {
      setState(() {
        _readMessageIds.remove(message.id);
      });
    }
  }

  void _deleteAllMessages(List<DocumentSnapshot> messages) async {
    for (var message in messages) {
      await _firebaseService
          .updateMessageField(message.id, {'VisibleEnApp': 'N'});
    }
    if (mounted) {
      setState(() {
        _readMessageIds.clear();
      });
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
                  _firebaseService.getMensajesStream().first.then((messages) {
                    _deleteAllMessages(messages);
                  });
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
                          IconButton(
                            icon: Icon(
                              isRead
                                  ? Icons.mark_email_read
                                  : Icons.mark_email_unread,
                              color: isRead ? Colors.grey : Colors.blue,
                            ),
                            onPressed: () {
                              if (!isRead) {
                                _markMessageAsRead(messages[index]);
                              }
                            },
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
                                    color: isRead ? Colors.black : Colors.blue,
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
                              _deleteMessage(messages[index]);
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
