// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — pending_action.g.dart   (hand-written adapter — no build_runner)
//  Hive TypeAdapter for PendingAction.
// ═══════════════════════════════════════════════════════════════════════════
// ignore_for_file: type=lint

part of 'pending_action.dart';

class PendingActionAdapter extends TypeAdapter<PendingAction> {
  @override
  final int typeId = 10;

  @override
  PendingAction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PendingAction(
      id:           fields[0] as String,
      type:         fields[1] as String,
      payload:      (fields[2] as Map).cast<String, dynamic>(),
      createdAt:    fields[3] as DateTime,
      retryCount:   fields[4] as int,
      nextRetryAt:  fields[5] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, PendingAction obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.type)
      ..writeByte(2)..write(obj.payload)
      ..writeByte(3)..write(obj.createdAt)
      ..writeByte(4)..write(obj.retryCount)
      ..writeByte(5)..write(obj.nextRetryAt);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingActionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;

  @override
  int get hashCode => typeId.hashCode;
}
