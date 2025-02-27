// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_event.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ErrorEventAdapter extends TypeAdapter<ErrorEvent> {
  @override
  final int typeId = 0;

  @override
  ErrorEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ErrorEvent(
      type: fields[0] as String,
      message: fields[1] as String,
      timestamp: fields[2] as DateTime,
      additionalInfo: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ErrorEvent obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.type)
      ..writeByte(1)
      ..write(obj.message)
      ..writeByte(2)
      ..write(obj.timestamp)
      ..writeByte(3)
      ..write(obj.additionalInfo);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorEventAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
