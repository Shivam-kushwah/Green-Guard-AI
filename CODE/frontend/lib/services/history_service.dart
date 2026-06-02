import 'package:frontend/model/diagnosis_history_model.dart';
import 'package:frontend/model/user_model.dart';
import 'package:hive/hive.dart';

class HistoryService {
  /// Get current logged-in user
  static UserModel _getCurrentUser() {
    final userBox = Hive.box<UserModel>('userBox');

    final user = userBox.get("currentUser");

    if (user == null) {
      throw Exception("No logged in user found");
    }

    return user;
  }

  /// Open dynamic user box
  static Future<Box<DiagnosisHistory>> _openUserBox() async {
    final user = _getCurrentUser();

    final boxName = "history_${user.uid}";

    return await Hive.openBox<DiagnosisHistory>(boxName);
  }

  /// Save history
  static Future<void> saveHistory({required DiagnosisHistory history}) async {
    final box = await _openUserBox();

    await box.add(history);
  }

  /// Get history
  static Future<List<DiagnosisHistory>> getHistory() async {
    final box = await _openUserBox();

    final list = box.values.toList();

    list.sort((a, b) => b.epochTime.compareTo(a.epochTime));

    return list;
  }

  /// Clear history
  static Future<void> clearHistory() async {
    final box = await _openUserBox();

    await box.clear();
  }
}
