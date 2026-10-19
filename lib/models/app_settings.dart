class AppSettings {
  String name;
  double electricityRate;
  double highLoadWatts;
  double longRuntimeHours;
  bool alertsEnabled;
  bool demoMode;
  String esp32Url;
  AppSettings({
    this.name = 'Alex',
    this.electricityRate = 11.50,
    this.highLoadWatts = 1000,
    this.longRuntimeHours = 8,
    this.alertsEnabled = true,
    this.demoMode = true,
    this.esp32Url = 'http://192.168.1.100',
  });
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    name: j['name'],
    electricityRate: (j['electricityRate'] as num).toDouble(),
    highLoadWatts: (j['highLoadWatts'] as num).toDouble(),
    longRuntimeHours: (j['longRuntimeHours'] as num).toDouble(),
    alertsEnabled: j['alertsEnabled'],
    demoMode: j['demoMode'],
    esp32Url: j['esp32Url'],
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'electricityRate': electricityRate,
    'highLoadWatts': highLoadWatts,
    'longRuntimeHours': longRuntimeHours,
    'alertsEnabled': alertsEnabled,
    'demoMode': demoMode,
    'esp32Url': esp32Url,
  };
}
