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

  @HiveField(4)
  final String? endpoint;

  @HiveField(5)
  final String? payload;

  ErrorEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.additionalInfo,
    this.endpoint,
    this.payload,
  });
}
