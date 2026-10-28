import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/upi_qr_payment.dart';

class ShopUpiQrScannerScreen extends StatefulWidget {
  const ShopUpiQrScannerScreen({super.key});

  @override
  State<ShopUpiQrScannerScreen> createState() => _ShopUpiQrScannerScreenState();
}

class _ShopUpiQrScannerScreenState extends State<ShopUpiQrScannerScreen> {
  String? _error;
  String? _lastRejectedValue;
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .cast<String?>()
        .firstWhere((value) => value != null && value.isNotEmpty,
            orElse: () => null);
    if (value == null || value == _lastRejectedValue) return;

    try {
      final payment = UpiQrPayment.fromQrValue(value);
      _handled = true;
      Navigator.of(context).pop(payment);
    } on FormatException catch (error) {
      _lastRejectedValue = value;
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan shop UPI QR')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorDetails?.message ??
                      'Camera unavailable. Allow camera access in phone settings.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: Column(
              children: [
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                const Card(
                  color: Colors.black87,
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Align the shop’s UPI QR code inside the frame.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
