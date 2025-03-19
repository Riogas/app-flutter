import 'dart:async';

class CounterService {
  Timer? _timer;

  void startCounter({required int intervalSeconds, required Function onTick}) {
    stopCounter(); // Ensure any existing timer is stopped
    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (timer) {
      onTick();
    });
  }

  void stopCounter() {
    _timer?.cancel();
    _timer = null;
  }
}
