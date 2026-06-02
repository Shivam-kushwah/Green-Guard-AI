// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diagnosis_history_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DiagnosisHistoryAdapter extends TypeAdapter<DiagnosisHistory> {
  @override
  final int typeId = 0;

  @override
  DiagnosisHistory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DiagnosisHistory(
      epochTime: fields[0] as int,
      plantName: fields[1] as String,
      imagePath: fields[2] as String,
      result: fields[3] as String,
      diagnosis: fields[4] as String,
      confidence: fields[5] as double,
    );
  }

  @override
  void write(BinaryWriter writer, DiagnosisHistory obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.epochTime)
      ..writeByte(1)
      ..write(obj.plantName)
      ..writeByte(2)
      ..write(obj.imagePath)
      ..writeByte(3)
      ..write(obj.result)
      ..writeByte(4)
      ..write(obj.diagnosis)
      ..writeByte(5)
      ..write(obj.confidence);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosisHistoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
