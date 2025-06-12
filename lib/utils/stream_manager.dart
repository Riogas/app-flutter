import 'dart:async';

StreamSubscription? ordersSubscription;
StreamSubscription? locationSubscription;
StreamSubscription? gpsSubscription;
StreamSubscription? connectivitySubscription;
Timer? connectivityCheckTimer;

Future<void> cancelAllStreams() async {
  await ordersSubscription?.cancel();
  await locationSubscription?.cancel();
  await gpsSubscription?.cancel();
  await connectivitySubscription?.cancel();
  connectivityCheckTimer?.cancel();
}
