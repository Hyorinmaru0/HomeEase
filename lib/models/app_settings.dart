import '../services/supported_devices.dart';

class AppSettings {
  String name;
  double electricityRate;
  double highLoadWatts;
  double longRuntimeHours;
  bool alertsEnabled;
  bool demoMode;
  String esp32Url;
  bool voiceEnabled;
  bool alarmEnabled;
  bool vibrationEnabled;
  double budget;
  String budgetPeriod;
  Map<String, double> budgetLimits;
  Map<String, double> applianceWatts;
  AppSettings({
    this.name = 'Alex',
    this.electricityRate = 11.50,
    this.highLoadWatts = 1000,
    this.longRuntimeHours = 8,
    this.alertsEnabled = true,
    this.demoMode = true,
    this.esp32Url = 'http://192.168.1.100',
    this.voiceEnabled = true,
    this.alarmEnabled = true,
    this.vibrationEnabled = false,
    this.budget = 100,
    this.budgetPeriod = 'monthly',
    Map<String, double>? budgetLimits,
    Map<String, double>? applianceWatts,
  }) : budgetLimits = {
         'daily': 100,
         'weekly': 100,
         'monthly': 100,
         ...?budgetLimits,
         budgetPeriod: budget,
       },
       applianceWatts = {
         ...SupportedDevices.defaultWatts,
         for (final e in (applianceWatts ?? <String, double>{}).entries)
           if (SupportedDevices.contains(SupportedDevices.canonical(e.key)))
             SupportedDevices.canonical(e.key): e.value,
       };
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    name: j['name'],
    electricityRate: (j['electricityRate'] as num).toDouble(),
    highLoadWatts: (j['highLoadWatts'] as num).toDouble(),
    longRuntimeHours: (j['longRuntimeHours'] as num).toDouble(),
    alertsEnabled: j['alertsEnabled'],
    demoMode: j['demoMode'],
    esp32Url: j['esp32Url'],
    voiceEnabled: j['voiceEnabled'] as bool? ?? true,
    alarmEnabled: j['alarmEnabled'] as bool? ?? true,
    vibrationEnabled: j['vibrationEnabled'] as bool? ?? false,
    budget: (j['budget'] as num? ?? 100).toDouble(),
    budgetPeriod: j['budgetPeriod'] as String? ?? 'monthly',
    budgetLimits: (j['budgetLimits'] as Map?)?.map(
      (k, v) => MapEntry(k as String, (v as num).toDouble()),
    ),
    applianceWatts: (j['applianceWatts'] as Map?)?.map(
      (k, v) => MapEntry(k as String, (v as num).toDouble()),
    ),
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'electricityRate': electricityRate,
    'highLoadWatts': highLoadWatts,
    'longRuntimeHours': longRuntimeHours,
    'alertsEnabled': alertsEnabled,
    'demoMode': demoMode,
    'esp32Url': esp32Url,
    'voiceEnabled': voiceEnabled,
    'alarmEnabled': alarmEnabled,
    'vibrationEnabled': vibrationEnabled,
    'budget': budget,
    'budgetPeriod': budgetPeriod,
    'budgetLimits': {...budgetLimits, budgetPeriod: budget},
    'applianceWatts': applianceWatts,
  };
}
