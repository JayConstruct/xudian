import 'module_package.dart';

class ServiceRef {
  const ServiceRef(this.moduleId, this.serviceId, this.major);
  final String moduleId, serviceId;
  final int major;
  factory ServiceRef.parse(Object? value) {
    final v = object(value, 'ServiceRef');
    return ServiceRef(
      string(v['moduleId'], 'moduleId'),
      string(v['serviceId'], 'serviceId'),
      v['majorVersion'] as int,
    );
  }
  String get key => '$moduleId/$serviceId@$major';
  Map<String, Object?> toJson() => {
    'moduleId': moduleId,
    'serviceId': serviceId,
    'majorVersion': major,
  };
}
