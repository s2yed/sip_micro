class User {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final String? sipExtension;

  const User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    this.sipExtension,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'],
        name: json['name'],
        email: json['email'],
        phone: json['phone'],
        role: json['role'] ?? 'customer',
        sipExtension: json['sip_extension'],
      );

  bool get isAgent => role == 'agent';
}
