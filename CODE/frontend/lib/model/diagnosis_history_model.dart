import 'package:hive/hive.dart';

part 'diagnosis_history_model.g.dart';

@HiveType(typeId: 0)
class DiagnosisHistory extends HiveObject {
  /// Epoch Time (milliseconds)
  @HiveField(0)
  int epochTime;

  @HiveField(1)
  String plantName;

  @HiveField(2)
  String imagePath;

  @HiveField(3)
  String result;

  @HiveField(4)
  String diagnosis;

  @HiveField(5)
  double confidence;

  DiagnosisHistory({
    required this.epochTime,
    required this.plantName,
    required this.imagePath,
    required this.result,
    required this.diagnosis,
    required this.confidence,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(epochTime);
}
