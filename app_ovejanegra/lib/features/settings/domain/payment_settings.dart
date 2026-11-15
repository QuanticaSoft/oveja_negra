/// Cuenta del negocio y QR de cobro (la imagen la genera el banco; la app solo la muestra).
class PaymentSettings {
  const PaymentSettings({this.bankName, this.accountHolder, this.accountNumber, this.qrUrl, this.updatedAt});

  final String? bankName;
  final String? accountHolder;
  final String? accountNumber;
  final String? qrUrl;
  final String? updatedAt;

  bool get hasQr => qrUrl != null;

  /// URL con versión: al reemplazar el QR, ningún teléfono muestra el anterior desde la caché.
  String? get qrUrlVersioned => qrUrl == null ? null : '$qrUrl?v=${Uri.encodeQueryComponent(updatedAt ?? '')}';

  factory PaymentSettings.fromJson(Map<String, dynamic> json) => PaymentSettings(
        bankName: json['bank_name'] as String?,
        accountHolder: json['account_holder'] as String?,
        accountNumber: json['account_number'] as String?,
        qrUrl: json['qr_url'] as String?,
        updatedAt: json['updated_at'] as String?,
      );
}
