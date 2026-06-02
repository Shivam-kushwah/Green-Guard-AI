import 'package:hive/hive.dart';

import '../model/user_model.dart';

class HiveBoxes {
  static Future<Box> getUserHistoryBox() async {
    final userBox = Hive.box<UserModel>('userBox');

    final user = userBox.get("currentUser");

    if (user == null) {
      throw Exception("User not logged in");
    }

    /// Dynamic box name
    final boxName = "history_${user.uid}";

    return await Hive.openBox(boxName);
  }
}
