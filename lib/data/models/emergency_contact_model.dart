import 'package:flutter/material.dart';

/// Emergency Contact Model - Uses Phone Number for SOS SMS alerts
class EmergencyContactModel {
  final String? id;
  final String name;
  final String phone;
  final String role;
  final IconData icon;
  final Color color;

  EmergencyContactModel({
    this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.icon = Icons.person,
    this.color = const Color(0xFF4A90D9),
  });

  /// Create from JSON/Firestore
  factory EmergencyContactModel.fromJson(Map<String, dynamic> json) {
    return EmergencyContactModel(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      phone:
          json['phone'] ?? json['email'] ?? '', // Support old email field too
      role: json['role'] ?? 'Contact',
      icon: _getIconFromString(json['icon']),
      color: Color(json['color'] ?? 0xFF4A90D9),
    );
  }

  /// Convert to JSON for Firestore
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'role': role,
      'icon': _getStringFromIcon(icon),
      'color': color.value,
    };
  }

  /// Copy with updated fields
  EmergencyContactModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? role,
    IconData? icon,
    Color? color,
  }) {
    return EmergencyContactModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      icon: icon ?? this.icon,
      color: color ?? this.color,
    );
  }

  static IconData _getIconFromString(String? iconName) {
    switch (iconName) {
      case 'favorite':
        return Icons.favorite_rounded;
      case 'medical':
        return Icons.medical_services_rounded;
      case 'hospital':
        return Icons.local_hospital_rounded;
      case 'police':
        return Icons.local_police_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  static String _getStringFromIcon(IconData icon) {
    if (icon == Icons.favorite_rounded) return 'favorite';
    if (icon == Icons.medical_services_rounded) return 'medical';
    if (icon == Icons.local_hospital_rounded) return 'hospital';
    if (icon == Icons.local_police_rounded) return 'police';
    return 'person';
  }
}
