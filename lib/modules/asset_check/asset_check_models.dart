/// Asset Check Models
/// 
/// Data models for asset checking functionality

class ScannedItem {
  final String smallPlantNo;
  final String? smallPlantDescription; // Kept for backward compatibility
  final String? type;
  final String? makeModel;
  final String? serialNumber;
  final String? checkId; // ID from small_plant_check table (null until submitted)
  final DateTime scannedAt;
  final bool hasFault;
  final String? faultId; // ID from small_plant_faults table (null if no fault)

  ScannedItem({
    required this.smallPlantNo,
    this.smallPlantDescription,
    this.type,
    this.makeModel,
    this.serialNumber,
    this.checkId,
    required this.scannedAt,
    this.hasFault = false,
    this.faultId,
  });

  ScannedItem copyWith({
    String? smallPlantNo,
    String? smallPlantDescription,
    String? type,
    String? makeModel,
    String? serialNumber,
    String? checkId,
    DateTime? scannedAt,
    bool? hasFault,
    String? faultId,
  }) {
    return ScannedItem(
      smallPlantNo: smallPlantNo ?? this.smallPlantNo,
      smallPlantDescription: smallPlantDescription ?? this.smallPlantDescription,
      type: type ?? this.type,
      makeModel: makeModel ?? this.makeModel,
      serialNumber: serialNumber ?? this.serialNumber,
      checkId: checkId ?? this.checkId,
      scannedAt: scannedAt ?? this.scannedAt,
      hasFault: hasFault ?? this.hasFault,
      faultId: faultId ?? this.faultId,
    );
  }

  /// Get display description - uses new fields if available, falls back to description
  String getDisplayDescription() {
    final parts = <String>[];
    if (type != null && type!.isNotEmpty) {
      parts.add(type!);
    }
    if (makeModel != null && makeModel!.isNotEmpty) {
      parts.add(makeModel!);
    }
    if (serialNumber != null && serialNumber!.isNotEmpty) {
      parts.add('S/N: ${serialNumber!}');
    }
    
    if (parts.isNotEmpty) {
      return parts.join(' • ');
    }
    
    // Fallback to description if new fields are not available
    return smallPlantDescription ?? 'No description';
  }
}

class FaultReport {
  final String smallPlantCheckId;
  final String comment;
  final String? photoUrl;
  final String? supervisorId;
  final String? actionType;
  final DateTime? actionDate;
  final String? actionNotes;

  FaultReport({
    required this.smallPlantCheckId,
    required this.comment,
    this.photoUrl,
    this.supervisorId,
    this.actionType,
    this.actionDate,
    this.actionNotes,
  });
}

