class BleDevice {
  final String id;
  final String name;
  final bool isConnected;
  final DateTime? lastSeen;

  const BleDevice({
    required this.id,
    required this.name,
    required this.isConnected,
    this.lastSeen,
  });

  BleDevice copyWith({
    String? id,
    String? name,
    bool? isConnected,
    Object? lastSeen = _sentinel,
  }) {
    return BleDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      isConnected: isConnected ?? this.isConnected,
      lastSeen: lastSeen == _sentinel ? this.lastSeen : lastSeen as DateTime?,
    );
  }
}

const _sentinel = Object();
