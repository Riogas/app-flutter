import 'package:flutter/widgets.dart';

class AppLifecycleObserver extends WidgetsBindingObserver {
  AppLifecycleState _lastLifecycleState = AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;
    print('🔄 AppLifecycleState changed to $state');
  }

  AppLifecycleState get lastLifecycleState => _lastLifecycleState;
}
