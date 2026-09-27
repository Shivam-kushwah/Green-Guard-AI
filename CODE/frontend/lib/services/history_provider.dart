import 'package:flutter/foundation.dart';

import '../model/diagnosis_history_model.dart';
import 'history_service.dart';

/// Live view of the signed-in user's scan history.
///
/// HistoryService itself is a static, one-shot Hive reader - it has no way to
/// tell anyone new data arrived. Without this, a screen that read history in
/// initState (Home, History) never found out about a scan saved afterwards,
/// so a fresh diagnosis only appeared after a screen revisit or app restart.
/// ScanReportingService calls [reload] right after a successful save, and
/// every screen that watches this provider (via Consumer/context.watch)
/// updates in the same frame.
class HistoryProvider extends ChangeNotifier {
  HistoryProvider._();
  static final HistoryProvider instance = HistoryProvider._();

  List<DiagnosisHistory> _items = const [];
  List<DiagnosisHistory> get items => _items;

  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  Future<void> reload() async {
    _items = await HistoryService.getHistory();
    _hasLoaded = true;
    notifyListeners();
  }

  Future<void> clear() async {
    await HistoryService.clearHistory();
    _items = const [];
    notifyListeners();
  }
}
