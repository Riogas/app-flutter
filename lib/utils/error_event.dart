import 'package:hive/hive.dart';

part 'error_event.g.dart';

@HiveType(typeId: 0)
class ErrorEvent extends HiveObject {
  @HiveField(0)
  final String type;

  @HiveField(1)
  final String message;

  @HiveField(2)
  final DateTime timestamp;

  @HiveField(3)
  final String? additionalInfo;

  ErrorEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.additionalInfo,
  });
}
