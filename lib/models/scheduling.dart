part of 'models.dart';

/// A block of working time on one weekday, e.g. 09:00–13:00.
class WorkSession {
  const WorkSession(this.start, this.end);

  /// "HH:mm", 24-hour clock.
  final String start;
  final String end;

  int get startMinutes => _minutes(start);
  int get endMinutes => _minutes(end);

  static int _minutes(String hhmm) {
    final [h, m] = hhmm.split(':').map(int.parse).toList();
    return h * 60 + m;
  }

  bool get isValid =>
      RegExp(r'^\d{2}:\d{2}$').hasMatch(start) &&
      RegExp(r'^\d{2}:\d{2}$').hasMatch(end) &&
      startMinutes < endMinutes &&
      endMinutes <= 24 * 60;

  @override
  String toString() => '$start–$end';

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  factory WorkSession.fromJson(Map<String, dynamic> j) =>
      WorkSession(j['start'], j['end']);
}

const kWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// When a doctor sees booked patients. Weekdays use [DateTime.weekday]
/// numbering (1 = Monday … 7 = Sunday).
class DoctorSchedule {
  DoctorSchedule({
    required this.doctorId,
    this.slotMinutes = 15,
    Map<int, List<WorkSession>>? week,
  }) : week = week ?? {};

  /// Also the record id: one schedule per doctor.
  final String doctorId;
  int slotMinutes;
  final Map<int, List<WorkSession>> week;

  List<WorkSession> sessionsOn(int weekday) => week[weekday] ?? const [];

  bool get isEmpty => week.values.every((s) => s.isEmpty);

  /// e.g. "Mon–Fri 09:00–13:00, 14:00–17:00 · Sat 09:00–12:00".
  String get summary {
    final parts = <String>[];
    var d = 1;
    while (d <= 7) {
      final s = sessionsOn(d);
      if (s.isEmpty) {
        d++;
        continue;
      }
      var e = d;
      while (e < 7 && _same(sessionsOn(e + 1), s)) {
        e++;
      }
      final days = e == d
          ? kWeekdays[d - 1]
          : '${kWeekdays[d - 1]}–${kWeekdays[e - 1]}';
      parts.add('$days ${s.join(', ')}');
      d = e + 1;
    }
    return parts.isEmpty ? 'No working hours set' : parts.join(' · ');
  }

  static bool _same(List<WorkSession> a, List<WorkSession> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i].toString() == b[i].toString()]
          .every((x) => x);

  Map<String, dynamic> toJson() => {
    'id': doctorId,
    'doctorId': doctorId,
    'slotMinutes': slotMinutes,
    'week': {
      for (final MapEntry(key: d, value: s) in week.entries)
        if (s.isNotEmpty) '$d': s.map((x) => x.toJson()).toList(),
    },
  };

  factory DoctorSchedule.fromJson(Map<String, dynamic> j) => DoctorSchedule(
    doctorId: j['doctorId'] ?? j['id'],
    slotMinutes: (j['slotMinutes'] as num?)?.toInt() ?? 15,
    week: {
      for (final MapEntry(key: d, value: s)
          in ((j['week'] as Map?) ?? {}).entries)
        int.parse(d as String): (s as List)
            .map((x) => WorkSession.fromJson((x as Map).cast()))
            .toList(),
    },
  );
}

enum ReminderChannel { sms, whatsapp, email }

extension ReminderChannelX on ReminderChannel {
  String get label => switch (this) {
    ReminderChannel.sms => 'SMS',
    ReminderChannel.whatsapp => 'WhatsApp',
    ReminderChannel.email => 'Email',
  };
}

enum ReminderStatus {
  pending,

  /// Claimed by the server, which is sending it right now.
  sending,
  sent,
  failed,
  cancelled,
}

/// A message reminding a patient of an appointment.
class AppointmentReminder {
  AppointmentReminder({
    required this.id,
    required this.appointmentId,
    required this.patientId,
    required this.channel,
    required this.to,
    required this.message,
    required this.sendAt,
    this.status = ReminderStatus.pending,
    this.sentAt,
    this.sentBy,
    this.error = '',
  });

  final String id;
  final String appointmentId;
  final String patientId;
  final ReminderChannel channel;

  /// Phone in international form (+2348031112233) or email address.
  final String to;
  final String message;

  /// When to send. Stored in UTC so a server can compare it with its own
  /// clock regardless of the hospital's time zone.
  final DateTime sendAt;
  ReminderStatus status;
  DateTime? sentAt;

  /// Staff id, or "system" when sent automatically.
  String? sentBy;
  String error;

  bool isDue(DateTime now) =>
      status == ReminderStatus.pending && !sendAt.isAfter(now);

  Map<String, dynamic> toJson() => {
    'id': id,
    'appointmentId': appointmentId,
    'patientId': patientId,
    'channel': channel.name,
    'to': to,
    'message': message,
    'sendAt': sendAt.toUtc().toIso8601String(),
    'status': status.name,
    'sentAt': sentAt?.toUtc().toIso8601String(),
    'sentBy': sentBy,
    'error': error,
  };

  factory AppointmentReminder.fromJson(Map<String, dynamic> j) =>
      AppointmentReminder(
        id: j['id'],
        appointmentId: j['appointmentId'],
        patientId: j['patientId'],
        channel: _enumByName(
          ReminderChannel.values,
          j['channel'],
          ReminderChannel.sms,
        ),
        to: j['to'] ?? '',
        message: j['message'] ?? '',
        sendAt: DateTime.parse(j['sendAt']),
        status: _enumByName(
          ReminderStatus.values,
          j['status'],
          ReminderStatus.pending,
        ),
        sentAt: _date(j['sentAt']),
        sentBy: j['sentBy'],
        error: j['error'] ?? '',
      );
}
