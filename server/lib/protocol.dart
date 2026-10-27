/// The wire format shared by NAAK HMS Server and the app (pure Dart, so the
/// app can import it on every platform, including the web).
///
/// Every message is a JSON object sent over a WebSocket. Requests carry a
/// `rid` that the server's reply repeats. Data changes travel as [Op]s:
/// a whole new document, a merge of changed fields (with numeric fields that
/// several computers change at once sent as increments), or a deletion.
library;

/// Default TCP port of the server.
const kDefaultServerPort = 8787;

/// WebSocket path on the server.
const kSyncPath = '/sync';

/// Bumped when the protocol changes incompatibly.
const kProtocolVersion = 1;

enum OpKind { set, merge, delete }

class Op {
  const Op.set(this.collection, this.id, Map<String, dynamic> this.data)
    : kind = OpKind.set,
      increments = const {};

  const Op.merge(
    this.collection,
    this.id,
    Map<String, dynamic> this.data, {
    this.increments = const {},
  }) : kind = OpKind.merge;

  const Op.delete(this.collection, this.id)
    : kind = OpKind.delete,
      data = null,
      increments = const {};

  final String collection;
  final String id;
  final OpKind kind;

  /// The document ([OpKind.set]) or the changed fields ([OpKind.merge]).
  final Map<String, dynamic>? data;

  /// Field → amount to add, applied to the value on the server, so two
  /// computers deducting stock at once both count.
  final Map<String, num> increments;

  /// Fields this op changes.
  Set<String> get fields => {...?data?.keys, ...increments.keys};

  /// The document after this op, given the current one (null = absent).
  Map<String, dynamic>? applyTo(Map<String, dynamic>? current) {
    switch (kind) {
      case OpKind.delete:
        return null;
      case OpKind.set:
        return {...data!};
      case OpKind.merge:
        final next = {...?current, ...?data};
        for (final MapEntry(key: f, value: by) in increments.entries) {
          final v = next[f];
          next[f] = (v is num ? v : 0) + by;
        }
        return next;
    }
  }

  Map<String, dynamic> toJson() => {
    'c': collection,
    'id': id,
    'k': kind.name,
    if (data != null) 'd': data,
    if (increments.isNotEmpty) 'inc': increments,
  };

  factory Op.fromJson(Map<String, dynamic> j) {
    final c = j['c'] as String;
    final id = j['id'] as String;
    return switch (j['k']) {
      'set' => Op.set(c, id, _map(j['d'])),
      'merge' => Op.merge(
        c,
        id,
        _map(j['d'] ?? const {}),
        increments: {
          for (final MapEntry(key: k, value: v)
              in ((j['inc'] as Map?) ?? const {}).entries)
            k as String: v as num,
        },
      ),
      'delete' => Op.delete(c, id),
      _ => throw FormatException('Unknown op kind ${j['k']}'),
    };
  }
}

/// A document as the server confirmed it: null data means deleted.
class DocState {
  const DocState(this.collection, this.id, this.data);

  final String collection;
  final String id;
  final Map<String, dynamic>? data;

  Map<String, dynamic> toJson() => {'c': collection, 'id': id, 'd': data};

  factory DocState.fromJson(Map<String, dynamic> j) => DocState(
    j['c'] as String,
    j['id'] as String,
    j['d'] == null ? null : _map(j['d']),
  );
}

Map<String, dynamic> _map(Object? v) => (v as Map).cast<String, dynamic>();
