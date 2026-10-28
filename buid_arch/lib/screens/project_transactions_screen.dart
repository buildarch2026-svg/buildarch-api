import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:upi_intent/upi_intent.dart';

import '../models/project.dart';
import '../models/project_transaction.dart';
import '../models/upi_qr_payment.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'login_screen.dart';
import 'shop_upi_qr_scanner_screen.dart';

class ProjectTransactionsScreen extends StatefulWidget {
  const ProjectTransactionsScreen({super.key, required this.project});

  final Project project;

  @override
  State<ProjectTransactionsScreen> createState() =>
      _ProjectTransactionsScreenState();
}

class _ProjectTransactionsScreenState extends State<ProjectTransactionsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _payeeController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();
  final _paymentMethodController = TextEditingController(text: 'UPI');

  List<ProjectTransaction> _transactions = [];
  bool _loading = true;
  bool _submitting = false;
  UpiQrPayment? _selectedQrPayment;
  String? _selectedQrPayload;
  String _status = 'completed';
  String _payeeType = 'shop';
  String _paymentType = 'manual';

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  @override
  void dispose() {
    _payeeController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _paymentMethodController.dispose();
    super.dispose();
  }

  Future<String> _requireToken() async {
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthApiException(
          'Your session expired. Please sign in again.',
          statusCode: 401);
    }
    return token;
  }

  Future<void> _handleUnauthorized(AuthApiException error) async {
    final sessionStatus =
        await AuthSessionService.instance.validateSavedSession();
    if (!mounted) return;
    if (sessionStatus == SavedSessionStatus.signedOut) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      return;
    }

    final message = sessionStatus == SavedSessionStatus.authenticated
        ? 'Payment request rejected: ${error.message} Your sign-in is still active; try again.'
        : 'Could not verify your sign-in. Your session was kept; please try again.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadTransactions() async {
    setState(() => _loading = true);
    try {
      final token = await _requireToken();
      final transactions = await AuthApiService.instance.getProjectTransactions(
        token: token,
        projectId: widget.project.id,
      );
      if (mounted) {
        setState(() => _transactions = transactions);
      }
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        await _handleUnauthorized(error);
      } else if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
                content: Text('Could not load the project payment history.')),
          );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanShopQr() async {
    final payment = await Navigator.of(context).push<UpiQrPayment>(
      MaterialPageRoute(builder: (_) => const ShopUpiQrScannerScreen()),
    );
    if (!mounted || payment == null) return;

    setState(() {
      _selectedQrPayment = payment;
      _selectedQrPayload = jsonEncode({
        'vpa': payment.vpa,
        'name': payment.name,
        'amount': payment.amount,
        'note': payment.note,
        'merchantCode': payment.merchantCode,
      });
      _payeeController.text = payment.name;
      _paymentMethodController.text = 'Google Pay';
      _status = 'pending';
      _paymentType = 'provider';
      if (payment.amount != null) {
        _amountController.text = payment.amount!.toStringAsFixed(2);
      }
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
            content: Text('Shop QR loaded. Review the amount and pay.')),
      );
  }

  Future<void> _submitProviderPayment(String token, double amount) async {
    final qrPayment = _selectedQrPayment;
    if (qrPayment == null) {
      throw const AuthApiException(
          'Scan a valid shop UPI QR code before continuing.');
    }

    final attemptId = 'BA-${DateTime.now().microsecondsSinceEpoch}';
    final pending = await AuthApiService.instance.createProjectTransaction(
      token: token,
      projectId: widget.project.id,
      payeeName: qrPayment.name,
      payeeType: _payeeType,
      payeeVpa: qrPayment.vpa,
      attemptId: attemptId,
      qrPayload: _selectedQrPayload,
      amount: amount,
      currency: 'INR',
      status: 'pending',
      paymentMethod: 'Google Pay',
      paymentType: 'provider',
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      category: _categoryController.text.trim().isEmpty
          ? null
          : _categoryController.text.trim(),
    );

    final apps = await UpiIntent.getInstalledApps();
    UpiApp? googlePay;
    for (final app in apps) {
      if (app.packageName == 'com.google.android.apps.nbu.paisa.user') {
        googlePay = app;
        break;
      }
    }
    if (googlePay == null) {
      await AuthApiService.instance.updateProjectTransactionStatus(
        token: token,
        projectId: widget.project.id,
        transactionId: pending.id,
        status: 'failed',
      );
      throw const AuthApiException(
          'Google Pay is not installed on this phone.');
    }

    final response = await UpiIntent.payWithApp(
      app: googlePay,
      payment: UpiPayment(
        payeeVpa: qrPayment.vpa,
        payeeName: qrPayment.name,
        amount: amount,
        transactionNote: _descriptionController.text.trim().isEmpty
            ? 'Build Arch project ${widget.project.name}'
            : _descriptionController.text.trim(),
        transactionRefId: attemptId,
        merchantCode: qrPayment.merchantCode,
      ),
    );

    final status = response == null
        ? 'cancelled'
        : response.isSuccess
            ? 'completed'
            : 'failed';
    await AuthApiService.instance.updateProjectTransactionStatus(
      token: token,
      projectId: widget.project.id,
      transactionId: pending.id,
      status: status,
      providerReference: response?.transactionId ?? response?.approvalRefNo,
    );

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(status == 'completed'
                ? 'Payment confirmed by Google Pay.'
                : status == 'cancelled'
                    ? 'Google Pay payment was cancelled.'
                    : 'Google Pay payment was not successful.'),
          ),
        );
    }
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;

    final amountText = _amountController.text.trim();
    final parsedAmount = double.tryParse(amountText);
    if (parsedAmount == null || parsedAmount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Enter a valid amount above 0.')));
      return;
    }

    setState(() => _submitting = true);
    try {
      final token = await _requireToken();
      if (_paymentType == 'provider') {
        await _submitProviderPayment(token, parsedAmount);
      } else {
        await AuthApiService.instance.createProjectTransaction(
          token: token,
          projectId: widget.project.id,
          payeeName: _payeeController.text.trim(),
          payeeType: _payeeType,
          amount: parsedAmount,
          currency: 'INR',
          status: _status,
          paymentMethod: _paymentMethodController.text.trim().isEmpty
              ? 'manual'
              : _paymentMethodController.text.trim(),
          paymentType: _paymentType,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
        );
      }
      if (!mounted) return;
      _payeeController.clear();
      _amountController.clear();
      _descriptionController.clear();
      _categoryController.clear();
      _paymentMethodController.text = 'UPI';
      _status = 'completed';
      _payeeType = 'shop';
      _paymentType = 'manual';
      _selectedQrPayment = null;
      _selectedQrPayload = null;
      await _loadTransactions();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Payment recorded for the project.')));
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        await _handleUnauthorized(error);
      } else if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
              SnackBar(content: Text('Could not save this payment: $error')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openAddTransactionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Record a payment',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _scanShopQr,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(
                    _selectedQrPayment == null
                        ? 'Scan shop UPI QR'
                        : 'QR loaded · Scan again',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _payeeController,
                  decoration: const InputDecoration(
                    labelText: 'Payee or shop',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Enter the payee name.'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _payeeType,
                  decoration: const InputDecoration(
                    labelText: 'Payee type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'shop', child: Text('Shop')),
                    DropdownMenuItem(
                        value: 'supplier', child: Text('Supplier')),
                    DropdownMenuItem(
                        value: 'contractor', child: Text('Contractor')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) =>
                      setState(() => _payeeType = value ?? 'shop'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Enter an amount.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _paymentMethodController,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                        value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'failed', child: Text('Failed')),
                    DropdownMenuItem(
                        value: 'cancelled', child: Text('Cancelled')),
                    DropdownMenuItem(
                        value: 'refunded', child: Text('Refunded')),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'completed'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _paymentType,
                  decoration: const InputDecoration(
                    labelText: 'Payment type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'manual', child: Text('Manual / recorded')),
                    DropdownMenuItem(
                        value: 'external', child: Text('External')),
                    DropdownMenuItem(
                        value: 'provider', child: Text('Provider')),
                  ],
                  onChanged: (value) =>
                      setState(() => _paymentType = value ?? 'manual'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Purpose or notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submitTransaction,
                  icon: const Icon(Icons.check),
                  label: Text(_submitting ? 'Saving...' : 'Save payment'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSpent = _transactions
        .where((transaction) => transaction.status == 'completed')
        .fold<double>(0, (sum, transaction) => sum + transaction.amount);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'Project payments',
          style: AppTextStyles.cardTitle.copyWith(color: AppColors.textPrimary),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddTransactionSheet,
        icon: const Icon(Icons.add),
        label: const Text('Record payment'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTransactions,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                children: [
                  Card(
                    color: AppColors.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total spent',
                                style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.outline,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₹ ${totalSpent.toStringAsFixed(2)}',
                                style: AppTextStyles.cardTitle.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Chip(
                            label: Text(
                              '${_transactions.length} records',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_transactions.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(Icons.receipt_long_outlined, size: 42),
                            const SizedBox(height: 12),
                            Text(
                              'No project payments recorded yet.',
                              style: AppTextStyles.bodyMd.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add a payment to track work, material, and project spending.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySm
                                  .copyWith(color: AppColors.outline),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._transactions.map((transaction) {
                      final dateLabel = transaction.createdAt == null
                          ? 'Recent payment'
                          : '${transaction.createdAt!.day.toString().padLeft(2, '0')}/'
                              '${transaction.createdAt!.month.toString().padLeft(2, '0')}/'
                              '${transaction.createdAt!.year}';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.secondary.withAlpha(30),
                            child: Icon(
                              transaction.status == 'completed'
                                  ? Icons.check_circle_outline
                                  : Icons.pending_actions_outlined,
                              color: AppColors.secondary,
                            ),
                          ),
                          title: Text(
                            transaction.payeeName,
                            style: AppTextStyles.bodyMd.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                '${transaction.paymentMethod} · ${transaction.status.toUpperCase()}',
                                style: AppTextStyles.bodySm
                                    .copyWith(color: AppColors.outline),
                              ),
                              if (transaction.description != null &&
                                  transaction.description!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    transaction.description!,
                                    style: AppTextStyles.bodySm.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                transaction.amountLabel,
                                style: AppTextStyles.bodyMd.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                dateLabel,
                                style: AppTextStyles.bodySm
                                    .copyWith(color: AppColors.outline),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
