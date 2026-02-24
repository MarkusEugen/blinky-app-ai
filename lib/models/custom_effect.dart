import 'effect_data.dart';

class CustomEffect {
  final String id;
  final String name;
  final EffectData data;

  const CustomEffect({
    required this.id,
    required this.name,
    required this.data,
  });

  CustomEffect copyWith({String? id, String? name, EffectData? data}) {
    return CustomEffect(
      id: id ?? this.id,
      name: name ?? this.name,
      data: data ?? this.data,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'data': data.toJson(),
      };

  factory CustomEffect.fromJson(Map<String, dynamic> json) => CustomEffect(
        id: json['id'] as String,
        name: json['name'] as String,
        data: EffectData.fromJson(json['data'] as Map<String, dynamic>),
      );
}
