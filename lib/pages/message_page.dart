import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../services/persistent_stream_manager.dart'; // Import PersistentStreamManager
import 'dart:async'; // Import the dart:async package for StreamSubscription
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/riogas_service.dart'; // Import the RioGasService
import 'package:intl/intl.dart'; // Import the intl package for date formatting
import '../services/location_service.dart'; // Import the LocationService
import 'package:geolocator/geolocator.dart'; // Import the Geolocator package
import 'package:hive/hive.dart'; // Import the Hive package
import 'package:firebase_messaging/firebase_messaging.dart'; // Import Firebase Messaging
import 'package:firebase_core/firebase_core.dart'; // Import Firebase Core
import 'package:url_launcher/url_launcher.dart'; // Import url_launcher package
import '../utils/constantes.dart'; // Import the constantes.dart file

class MessagePage extends StatefulWidget {
  @override
  _MessagePageState createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  final FirebaseService _firebaseService = FirebaseService();
  final PersistentStreamManager _streamManager = PersistentStreamManager();
  final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance; // Add FirebaseMessaging instance
  List<String> _readMessageIds = [];
  StreamSubscription<List<DocumentSnapshot>>? _messageSubscription;
  StreamSubscription<ServiceStatus>?
      _gpsStatusSubscription; // Subscription to listen to GPS status changes
  bool _isLocationServiceEnabled = true;
  final LocationService locationService =
      LocationService(); // Initialize locationService

  @override
  void initState() {
    super.initState();
    print('📨 MessagePage: initState() called');
    _checkLocationService();
    _listenToMessages();
    _setupFCM(); // Initialize FCM for background notifications
    _listenToGPSChanges(); // Listen to GPS status changes
    _initPersistentStreams();
    print('📨 MessagePage: initState() completed');
  }

  Future<void> _initPersistentStreams() async {
    await _streamManager.initialize();
    print('🔄 [MessagePage] PersistentStreamManager initialized');
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _gpsStatusSubscription?.cancel(); // Cancel GPS status subscription
    super.dispose();
  }

  Future<void> _checkLocationService() async {
    bool isEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Por favor, active el GPS para continuar.')),
        );
      }
    }
    if (mounted) {
      setState(() {
        _isLocationServiceEnabled = isEnabled;
      });
    }
  }

  void _listenToMessages() async {
    print('📨 MessagePage: _listenToMessages() started');
    // Ya no es necesario agregar listeners manuales, ValueListenableBuilder en build() se encarga de actualizar la UI.
    // Si necesitas inicializar _readMessageIds al inicio, puedes hacerlo aquí:
    try {
      var mensajesBox = await Hive.openBox('mensajesBox');
      _readMessageIds = mensajesBox.keys
          .cast<String>()
          .where((key) => mensajesBox.get(key) != 'Borrado')
          .toList();
      print(
          '📦 MessagePage: mensajesBox opened and _readMessageIds initialized (${_readMessageIds.length})');
    } catch (e) {
      print('❌ [MessagePage] Error in _listenToMessages: $e');
    }
  }

  void _setupFCM() {
    // Subscribe to a topic for messages
    _firebaseMessaging.subscribeToTopic('messages');

    /*// Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showForegroundNotification(message.notification!);
      }
    });*/

    // Handle background messages (optional, already handled in main.dart)
    //FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  Future<void> _showForegroundNotification(
    RemoteNotification notification,
  ) async {
    /*const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'messages_channel_id',
      'Messages Notifications',
      channelDescription: 'Notifications for new messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      platformChannelSpecifics,
    );*/
  }

  static Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    //await Firebase.initializeApp();
    print('Handling a background message: ${message.messageId}');
  }

  void _checkForNewMessages(List<DocumentSnapshot> messages) {
    for (var message in messages) {
      if (!_readMessageIds.contains(message.id)) {
        //_showNotification(message);
        _readMessageIds.add(message.id);
      }
    }
  }

  /*Future<void> _showNotification(DocumentSnapshot message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'your_channel_id',
      'your_channel_name',
      channelDescription: 'your_channel_description',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await flutterLocalNotificationsPlugin.show(
      0,
      'Nuevo Mensaje',
      'Mensaje: ${message['Mensaje'] ?? 'Sin contenido'}',
      platformChannelSpecifics,
      payload: 'item x',
    );
  }*/

  Future<void> _markMessageAsRead(DocumentSnapshot message) async {
    var box = await Hive.openBox('sessionBox');
    String? escenario = box.get('escenario');
    String? movil = box.get('movil');
    String? username = box.get('username');
    String? deviceId = box.get('deviceId');

    // print('📦 Datos obtenidos de Hive:');
    // print('Escenario: $escenario');
    // print('Movil: $movil');
    // print('Username: $username');
    // print('DeviceId: $deviceId');

    if (escenario == null ||
        movil == null ||
        username == null ||
        deviceId == null) {
      print('❌ No se pudo obtener los datos necesarios de Hive.');
      return;
    }

    String latitude = '0.0';
    String longitude = '0.0';
    String utmX = '0.0';
    String utmY = '0.0';

    // Invoca el método para obtener la ubicación
    final locationData = await locationService.getCurrentLocation();

    if (locationData != null) {
      latitude = locationData['latitude'].toString();
      longitude = locationData['longitude'].toString();
      utmX = locationData['utmX'].toString();
      utmY = locationData['utmY'].toString();

      print('Latitud: $latitude, Longitud: $longitude');
      print('UTMX: $utmX, UTMY: $utmY');
    } else {
      print('No se pudo obtener la ubicación.');
    }

    // print(
    //   '📍 Ubicación obtenida: Lat ${position.latitude}, Lng ${position.longitude}',
    // );

    var data = message.data() as Map<String, dynamic>;

    // Extract numeric part from message.id
    final numericIdMatch = RegExp(r'\d+').firstMatch(message.id);
    if (numericIdMatch == null) {
      print('❌ No se pudo extraer un ID numérico del mensaje: ${message.id}');
      return;
    }
    int messageId = int.parse(numericIdMatch.group(0)!);

    if (data.containsKey('FchHoraLeido')) {
      // print('📨 Mensaje ya leído: $messageId');
      return;
    }

    // print('📨 Marcando mensaje como leído: $messageId');
    //await _firebaseService.markMessageAsRead(message.id);

    // Open mensajesBox and update the message state to "Leido"
    var mensajesBox = await Hive.openBox('mensajesBox');
    //if (mensajesBox.containsKey(message.id)) {
    await mensajesBox.put(message.id, 'Leido');
    // print('📦 Mensaje actualizado a "Leido" en mensajesBox.');
    //}

    var locationBox = await Hive.openBox('locationBox');
    double velocidad = double.parse(
        locationBox.get('lastSpeed', defaultValue: 0.0).toStringAsFixed(2));
    double distanciaRecorrida =
        locationBox.get('totalDistance', defaultValue: 0.0);

    print('📨 Enviando datos al servicio descargaLecturaMensajes:');
    print('EscenarioId: ${int.parse(escenario)}');
    print('MovilId: ${int.parse(movil)}');
    print('MessageId: $messageId');
    print('Usuario: $username');
    print('NroSesion: ');
    print('TermMobileEquipo: $deviceId');
    print('LectDesc: LECTURA');
    print('FechaHoraCmbEst: ${DateTime.now().toUtc().toIso8601String()}');
    print('INAux1: ');
    print('INAux2: ');
    print('Latitud: ${latitude}');
    print('Longitud: ${longitude}');
    print('Velocidad: $velocidad');
    print('DistanciaRecorrida: $distanciaRecorrida');

    await RioGasService.descargaLecturaMensajes(
        int.parse(escenario), // escenarioId
        int.parse(movil), // movilId
        messageId, // messageId
        username, // usuario
        '', // nroSesion
        deviceId, // termMobileEquipo
        'LECTURA', // lectDesc
        DateTime.now().toUtc().toIso8601String(), // fechaHoraCmbEst
        '', // inAux1
        '', // inAux2
        latitude, // latitud
        longitude, // longitud
        utmX, // utmX
        utmY, // utmY
        velocidad, // velocidad
        distanciaRecorrida // distanciaRecorrida
        );

    if (mounted) {
      setState(() {
        _readMessageIds.add(message.id);
      });
    }
  }

  void _deleteMessage(DocumentSnapshot message) async {
    // Marcar como borrado en Hive
    var mensajesBox = await Hive.openBox('mensajesBox');
    if (mensajesBox.containsKey(message.id)) {
      await mensajesBox.put(message.id, 'Borrado');
    }

    // Invocar el servicio de descargaLecturaMensajes igual que al marcar como leído
    await _descargaLecturaMensajeService(message);

    if (mounted) {
      setState(() {
        _readMessageIds.remove(message.id);
      });
    }
  }

  void _deleteAllMessages(List<DocumentSnapshot> messages) async {
    // Marcar todos como borrado en Hive primero
    var mensajesBox = await Hive.openBox('mensajesBox');
    for (var message in messages) {
      if (mensajesBox.containsKey(message.id)) {
        await mensajesBox.put(message.id, 'Borrado');
      }
    }
    // Ejecutar todas las llamadas al servicio en paralelo
    await Future.wait(
        messages.map((message) => _descargaLecturaMensajeService(message)));
    if (mounted) {
      setState(() {
        _readMessageIds.clear();
      });
    }
  }

  // Servicio para invocar descargaLecturaMensajes (igual que en _markMessageAsRead)
  Future<void> _descargaLecturaMensajeService(DocumentSnapshot message) async {
    var box = await Hive.openBox('sessionBox');
    String? escenario = box.get('escenario');
    String? movil = box.get('movil');
    String? username = box.get('username');
    String? deviceId = box.get('deviceId');

    if (escenario == null ||
        movil == null ||
        username == null ||
        deviceId == null) {
      print('❌ No se pudo obtener los datos necesarios de Hive.');
      return;
    }

    String latitude = '0.0';
    String longitude = '0.0';
    String utmX = '0.0';
    String utmY = '0.0';

    final locationData = await locationService.getCurrentLocation();
    if (locationData != null) {
      latitude = locationData['latitude'].toString();
      longitude = locationData['longitude'].toString();
      utmX = locationData['utmX'].toString();
      utmY = locationData['utmY'].toString();
    }

    var data = message.data() as Map<String, dynamic>;
    final numericIdMatch = RegExp(r'\d+').firstMatch(message.id);
    if (numericIdMatch == null) {
      print('❌ No se pudo extraer un ID numérico del mensaje: ${message.id}');
      return;
    }
    int messageId = int.parse(numericIdMatch.group(0)!);

    var locationBox = await Hive.openBox('locationBox');
    double velocidad = double.parse(
        locationBox.get('lastSpeed', defaultValue: 0.0).toStringAsFixed(2));
    double distanciaRecorrida =
        locationBox.get('totalDistance', defaultValue: 0.0);

    await RioGasService.descargaLecturaMensajes(
        int.parse(escenario),
        int.parse(movil),
        messageId,
        username,
        '',
        deviceId,
        'LECTURA',
        DateTime.now().toUtc().toIso8601String(),
        '',
        '',
        latitude,
        longitude,
        utmX,
        utmY,
        velocidad,
        distanciaRecorrida);
  }

  void _listenToGPSChanges() {
    _gpsStatusSubscription =
        Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      setState(() {
        _isLocationServiceEnabled = status == ServiceStatus.enabled;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            IconButton(
              icon: Icon(Icons.headset_mic, color: Colors.black),
              onPressed: () async {
                final phoneNumber = await getConstantValue('170') ?? '';
                if (phoneNumber.isNotEmpty) {
                  final Uri callUri = Uri(scheme: 'tel', path: phoneNumber);
                  if (await canLaunchUrl(callUri)) {
                    await launchUrl(callUri);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('No se pudo realizar la llamada.')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Número de teléfono no disponible.')),
                  );
                }
              },
            ),
            SizedBox(width: 8),
            Text('Despacho',
                style: TextStyle(color: Colors.black, fontSize: 18)),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: () {
              final mensajes = _streamManager.mensajesNotifier.value;
              _deleteAllMessages(mensajes);
            },
            child: Row(
              children: [
                Text('Borrar Todo', style: TextStyle(color: Colors.black)),
                SizedBox(width: 4),
                Icon(Icons.delete, color: Colors.black),
                SizedBox(width: 12),
              ],
            ),
          ),
        ],
      ),
      body: _isLocationServiceEnabled
          ? ValueListenableBuilder<List<DocumentSnapshot>>(
              valueListenable: _streamManager.mensajesNotifier,
              builder: (context, mensajes, child) {
                if (mensajes.isEmpty) {
                  return Center(child: Text('No hay mensajes disponibles.'));
                }

                mensajes.sort((a, b) {
                  var aDate = (a['FchHoraCreado'] as Timestamp).toDate();
                  var bDate = (b['FchHoraCreado'] as Timestamp).toDate();
                  return bDate.compareTo(aDate);
                });

                return FutureBuilder<Box>(
                  future: Hive.openBox(
                      'mensajesBox'), // 🔧 Fix: Ensure box is opened
                  builder: (context, boxSnapshot) {
                    if (boxSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      print('📦 Waiting for mensajesBox to open...');
                      return Center(child: CircularProgressIndicator());
                    }
                    if (boxSnapshot.hasError) {
                      print(
                          '❌ Error opening mensajesBox: ${boxSnapshot.error}');
                      return Center(
                          child: Text('Error opening message storage'));
                    }

                    var mensajesBox = boxSnapshot.data!;
                    print(
                        '📦 mensajesBox opened successfully with ${mensajesBox.length} entries');

                    return ListView.builder(
                      itemCount: mensajes.length,
                      itemBuilder: (context, index) {
                        var mensaje =
                            mensajes[index].data() as Map<String, dynamic>;
                        bool isRead =
                            mensajesBox.get(mensajes[index].id) == 'Leido';
                        bool isDeleted =
                            mensajesBox.get(mensajes[index].id) == 'Borrado';

                        if (isDeleted) {
                          return SizedBox.shrink(); // Skip rendering this card
                        }

                        String formattedDate = mensaje['FchHoraCreado'] != null
                            ? DateFormat('dd/MM/yyyy HH:mm').format(
                                (mensaje['FchHoraCreado'] as Timestamp)
                                    .toDate(),
                              )
                            : '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 4.0,
                          ),
                          child: Card(
                            color: isRead ? Colors.grey[300] : Colors.lightBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                            elevation: 5,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Eliminado el sobre de marcar como leído
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          mensaje['Mensaje'] ?? 'Sin contenido',
                                          style: TextStyle(
                                            fontWeight: isRead
                                                ? FontWeight.normal
                                                : FontWeight.bold,
                                            color: isRead
                                                ? Colors.black
                                                : Colors.white,
                                            fontSize: 16.0,
                                          ),
                                        ),
                                        SizedBox(height: 5),
                                        Text(
                                          formattedDate,
                                          style: TextStyle(
                                            color: isRead
                                                ? Colors.black
                                                : Colors.white,
                                            fontSize: 12.0,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      color: Colors.black,
                                    ),
                                    onPressed: () {
                                      _deleteMessage(mensajes[index]);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            )
          : Center(
              child: Text(
                'Bloqueado - Sin GPS Activado',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            ),
    );
  }
}
