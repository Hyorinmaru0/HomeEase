enum AlertKind { smartExit, highLoad, abnormalUsage, connection }

class HomeEaseAlert {
  final String id;
  final String title;
  final String message;
  final AlertKind kind;
  final DateTime createdAt;
  bool read;
  HomeEaseAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.kind,
    required this.createdAt,
    this.read = false,
  });
  factory HomeEaseAlert.fromJson(Map<String, dynamic> j) => HomeEaseAlert(
    id: j['id'],
    title: j['title'],
    message: j['message'],
    kind: AlertKind.values.byName(j['kind']),
    createdAt: DateTime.parse(j['createdAt']),
    read: j['read'],
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'read': read,
  };
}
