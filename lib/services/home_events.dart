import '../models/app_settings.dart';
import '../models/usage_record.dart';

abstract class HomeEvents {
  void settingsChanged(AppSettings settings);
  void observedEnergy(UsageRecord record);
  void commandObserved(
    String deviceId,
    bool on,
    String source,
    bool success,
    DateTime at,
  );
}
