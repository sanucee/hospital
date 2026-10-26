part of 'hospital_store.dart';

/// Insurance billing, pharmacy purchasing and the hospital profile.
extension BillingSupplyOperations on HospitalStore {
  // ---------------------------------------------------------------------------
  // Hospital profile
  // ---------------------------------------------------------------------------

  Future<void> updateProfile({
    required String name,
    String address = '',
    String phone = '',
    String email = '',
    String taxId = '',
    String receiptFooter = '',
    String? countryCode,
    List<int>? reminderHours,
    String? reminderTemplate,
    bool? autoSendReminders,
  }) async {
    if (name.trim().isEmpty) throw HospitalException('Enter the hospital name');
    final code = countryCode?.replaceAll(RegExp(r'[^0-9]'), '');
    if (code != null && (code.isEmpty || code.length > 4)) {
      throw HospitalException('Enter a country calling code such as 234');
    }
    if (reminderHours != null &&
        reminderHours.any((h) => h <= 0 || h > 24 * 14)) {
      throw HospitalException('Reminder times must be 1 to 336 hours ahead');
    }
    if (reminderTemplate != null && reminderTemplate.trim().isEmpty) {
      throw HospitalException('Enter the reminder message');
    }
    if (code != null) profile.countryCode = code;
    if (reminderHours != null) {
      profile.reminderHours = reminderHours.toSet().toList()
        ..sort((a, b) => b.compareTo(a));
    }
    if (reminderTemplate != null) {
      profile.reminderTemplate = reminderTemplate.trim();
    }
    if (autoSendReminders != null) {
      profile.autoSendReminders = autoSendReminders;
    }
    profile
      ..name = name.trim()
      ..address = address.trim()
      ..phone = phone.trim()
      ..email = email.trim()
      ..taxId = taxId.trim()
      ..receiptFooter = receiptFooter.trim();
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Insurers and policies
  // ---------------------------------------------------------------------------

  InsuranceProvider? insurerById(String? id) {
    if (id == null) return null;
    for (final i in insurers) {
      if (i.id == id) return i;
    }
    return null;
  }

  Future<InsuranceProvider> upsertInsurer(InsuranceProvider i) async {
    if (i.name.trim().isEmpty) throw HospitalException('Enter a name');
    if (i.coveragePercent < 0 || i.coveragePercent > 100) {
      throw HospitalException('Coverage must be between 0 and 100%');
    }
    if (i.coverageLimit < 0) {
      throw HospitalException('Limit cannot be negative');
    }
    if (insurerById(i.id) == null) insurers.add(i);
    await _commit();
    return i;
  }

  /// Copies the patient's insurance terms onto a new invoice, if their
  /// policy is valid today.
  void _applyInsurance(Invoice inv) {
    final p = patientById(inv.patientId);
    final insurer = insurerById(p?.insurerId);
    if (p == null || insurer == null || !insurer.active) return;
    if (!p.policyValidOn(inv.createdAt)) return;
    inv
      ..insurerId = insurer.id
      ..coveragePercent = insurer.coveragePercent
      ..coverageLimit = insurer.coverageLimit;
  }

  /// Attaches an insurer to an existing bill (or removes it with null),
  /// before any claim has been made for it.
  Future<void> setInvoiceInsurer(String invoiceId, String? insurerId) async {
    final inv = invoices.firstWhere((i) => i.id == invoiceId);
    final open = activeClaimFor(invoiceId);
    if (open != null) {
      throw HospitalException(
        'Claim ${open.number} exists for this bill; reject or delete it first',
      );
    }
    final insurer = insurerById(insurerId);
    inv
      ..insurerId = insurer?.id
      ..coveragePercent = insurer?.coveragePercent ?? 0
      ..coverageLimit = insurer?.coverageLimit ?? 0
      ..insurerApproved = null;
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Claims
  // ---------------------------------------------------------------------------

  InsuranceClaim? claimById(String id) {
    for (final c in claims) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The claim for this invoice that hasn't been rejected, if any.
  InsuranceClaim? activeClaimFor(String invoiceId) {
    for (final c in claims) {
      if (c.invoiceId == invoiceId && c.status != ClaimStatus.rejected) {
        return c;
      }
    }
    return null;
  }

  List<InsuranceClaim> get claimsByDate =>
      [...claims]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Approved but not yet paid, plus submitted (awaiting a decision).
  double get dueFromInsurers => invoices
      .where((i) => i.insurerId != null)
      .fold(0, (s, i) => s + (i.insurerBalance > 0 ? i.insurerBalance : 0));

  Future<InsuranceClaim> createClaim(String invoiceId) async {
    final inv = invoices.firstWhere((i) => i.id == invoiceId);
    if (inv.insurerId == null) {
      throw HospitalException('This bill has no insurer attached');
    }
    if (activeClaimFor(invoiceId) != null) {
      throw HospitalException('A claim already exists for this bill');
    }
    if (inv.admissionId != null &&
        (admissionById(inv.admissionId!)?.isActive ?? false)) {
      throw HospitalException(
        'Discharge the patient first so room charges are on the claim',
      );
    }
    if (inv.insurerShare <= 0) {
      throw HospitalException('Nothing to claim on this bill');
    }
    final n = await _next('claim');
    final c = InsuranceClaim(
      id: newId('CLM'),
      number: n == null
          ? 'CLM-T${_offlineNumber()}'
          : 'CLM-${n.toString().padLeft(5, '0')}',
      invoiceId: inv.id,
      insurerId: inv.insurerId!,
      patientId: inv.patientId,
      amountClaimed: inv.insurerShare,
      createdAt: DateTime.now(),
    );
    claims.add(c);
    await _commit();
    return c;
  }

  Future<void> submitClaim(String claimId, {String reference = ''}) async {
    final c = claimById(claimId)!;
    if (c.status != ClaimStatus.draft) {
      throw HospitalException('Claim was already submitted');
    }
    // The bill may have changed since the draft was made.
    final inv = invoices.firstWhere((i) => i.id == c.invoiceId);
    c
      ..amountClaimed = inv.insurerShare
      ..status = ClaimStatus.submitted
      ..submittedAt = DateTime.now()
      ..insurerReference = reference.trim();
    await _commit();
  }

  /// Records the insurer's decision. Anything it doesn't approve becomes
  /// payable by the patient.
  Future<void> decideClaim(
    String claimId, {
    required double approvedAmount,
    String notes = '',
  }) async {
    final c = claimById(claimId)!;
    if (c.status != ClaimStatus.submitted) {
      throw HospitalException('Only submitted claims can be decided');
    }
    if (approvedAmount < 0 || approvedAmount > c.amountClaimed + 0.004) {
      throw HospitalException(
        'Approved amount must be between 0 and the '
        '${c.amountClaimed.toStringAsFixed(2)} claimed',
      );
    }
    c
      ..approvedAmount = approvedAmount
      ..status = approvedAmount > 0
          ? ClaimStatus.approved
          : ClaimStatus.rejected
      ..decidedAt = DateTime.now()
      ..notes = notes.trim();
    invoices.firstWhere((i) => i.id == c.invoiceId).insurerApproved =
        approvedAmount;
    final shortfall = c.amountClaimed - approvedAmount;
    if (shortfall > 0.004) {
      _notify(
        title: approvedAmount > 0 ? 'Claim partly approved' : 'Claim rejected',
        body:
            '${c.number} for ${patientName(c.patientId)}: '
            '${shortfall.toStringAsFixed(2)} is now payable by the patient',
        role: UserRole.receptionist,
        patientId: c.patientId,
      );
    }
    await _commit();
  }

  /// Money received from the insurer against an approved claim.
  Future<void> recordInsurerPayment(
    String claimId,
    double amount, {
    String reference = '',
  }) async {
    final c = claimById(claimId)!;
    if (c.status != ClaimStatus.approved) {
      throw HospitalException('The claim must be approved first');
    }
    if (amount <= 0 || amount > c.outstanding + 0.004) {
      throw HospitalException(
        'Amount must be between 0 and the '
        '${c.outstanding.toStringAsFixed(2)} outstanding',
      );
    }
    final inv = invoices.firstWhere((i) => i.id == c.invoiceId);
    c.amountPaid += amount;
    inv.insurerPaid += amount;
    if (reference.trim().isNotEmpty) c.insurerReference = reference.trim();
    if (c.outstanding <= 0.004) c.status = ClaimStatus.paid;
    payments.add(
      Payment(
        id: newId('PMT'),
        invoiceId: inv.id,
        patientId: inv.patientId,
        amount: amount,
        method: 'Insurance',
        receivedAt: DateTime.now(),
        receivedBy: currentUser?.id,
        claimId: c.id,
      ),
    );
    await _commit();
  }

  /// Deletes a claim that hasn't been submitted.
  Future<void> deleteClaim(String claimId) async {
    final c = claimById(claimId)!;
    if (c.status != ClaimStatus.draft) {
      throw HospitalException('Only draft claims can be deleted');
    }
    claims.remove(c);
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Suppliers and purchase orders
  // ---------------------------------------------------------------------------

  Supplier? supplierById(String id) {
    for (final s in suppliers) {
      if (s.id == id) return s;
    }
    return null;
  }

  PurchaseOrder? purchaseOrderById(String id) {
    for (final p in purchaseOrders) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<Supplier> upsertSupplier(Supplier s) async {
    if (s.name.trim().isEmpty) throw HospitalException('Enter a name');
    if (supplierById(s.id) == null) suppliers.add(s);
    await _commit();
    return s;
  }

  List<PurchaseOrder> get purchaseOrdersByDate =>
      [...purchaseOrders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Delivered goods the supplier hasn't been paid for yet.
  List<PurchaseOrder> get unpaidSupplierBills =>
      purchaseOrders.where((p) => p.receivedValue > 0 && !p.isPaid).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Suggested order lines for medicines at or below their reorder level:
  /// enough to reach twice the reorder level.
  List<PurchaseItem> reorderSuggestions() => [
    for (final m in medicines.where((m) => m.isLowStock || m.isExpired))
      PurchaseItem(
        medicineId: m.id,
        medicineName: m.displayName,
        quantity: (m.reorderLevel * 2 - (m.isExpired ? 0 : m.stock)).clamp(
          m.reorderLevel > 0 ? m.reorderLevel : 1,
          1 << 30,
        ),
        unitCost: m.costPrice > 0
            ? m.costPrice
            : (m.unitPrice * 0.6 * 100).roundToDouble() / 100,
      ),
  ];

  Future<PurchaseOrder> createPurchaseOrder({
    required String supplierId,
    required List<PurchaseItem> items,
    DateTime? expectedOn,
    String notes = '',
  }) async {
    final lines = items.where((i) => i.quantity > 0).toList();
    if (lines.isEmpty) throw HospitalException('Add at least one item');
    if (lines.any((i) => i.unitCost < 0)) {
      throw HospitalException('Unit cost cannot be negative');
    }
    final n = await _next('po');
    final po = PurchaseOrder(
      id: newId('PO'),
      number: n == null
          ? 'PO-T${_offlineNumber()}'
          : 'PO-${n.toString().padLeft(5, '0')}',
      supplierId: supplierId,
      items: lines,
      createdAt: DateTime.now(),
      expectedOn: expectedOn,
      createdBy: currentUser?.id,
      notes: notes.trim(),
    );
    purchaseOrders.add(po);
    await _commit();
    return po;
  }

  Future<void> placePurchaseOrder(String poId) async {
    final po = purchaseOrderById(poId)!;
    if (po.status != PurchaseStatus.draft) {
      throw HospitalException('Order was already placed');
    }
    po
      ..status = PurchaseStatus.ordered
      ..orderedAt = DateTime.now();
    await _commit();
  }

  Future<void> cancelPurchaseOrder(String poId) async {
    final po = purchaseOrderById(poId)!;
    if (po.items.any((i) => i.receivedQuantity > 0)) {
      throw HospitalException('Goods were already received on this order');
    }
    po.status = PurchaseStatus.cancelled;
    await _commit();
  }

  /// Books a delivery into stock. [lines] maps item index to the quantity
  /// received with its batch number and expiry date.
  Future<void> receiveGoods(
    String poId,
    Map<int, (int quantity, String batch, DateTime? expiry)> lines, {
    String deliveryNote = '',
  }) async {
    final po = purchaseOrderById(poId)!;
    if (po.status != PurchaseStatus.ordered &&
        po.status != PurchaseStatus.partiallyReceived) {
      throw HospitalException('Place the order before receiving goods');
    }
    final received = <ReceivedLine>[];
    // Validate first so a bad line leaves nothing half-booked.
    for (final MapEntry(key: i, value: (qty, _, _)) in lines.entries) {
      if (qty < 0) throw HospitalException('Quantities cannot be negative');
      if (qty > po.items[i].outstanding) {
        throw HospitalException(
          '${po.items[i].medicineName}: only ${po.items[i].outstanding} '
          'outstanding',
        );
      }
    }
    for (final MapEntry(key: i, value: (qty, batch, expiry)) in lines.entries) {
      if (qty == 0) continue;
      final item = po.items[i];
      final med = medicineById(item.medicineId);
      if (med != null) {
        // The shown expiry is the earliest of the stock on hand.
        if (expiry != null &&
            (med.stock <= 0 ||
                med.expiryDate == null ||
                expiry.isBefore(med.expiryDate!))) {
          med.expiryDate = expiry;
        }
        med
          ..stock += qty
          ..costPrice = item.unitCost;
      }
      item.receivedQuantity += qty;
      received.add(
        ReceivedLine(
          medicineId: item.medicineId,
          quantity: qty,
          batchNumber: batch.trim(),
          expiryDate: expiry,
        ),
      );
    }
    if (received.isEmpty) throw HospitalException('Nothing received');
    po.receipts.add(
      GoodsReceipt(
        receivedAt: DateTime.now(),
        lines: received,
        receivedBy: currentUser?.id,
        deliveryNote: deliveryNote.trim(),
      ),
    );
    po.status = po.items.every((i) => i.outstanding <= 0)
        ? PurchaseStatus.received
        : PurchaseStatus.partiallyReceived;
    _notify(
      title: 'Goods received',
      body:
          '${po.number} from ${supplierById(po.supplierId)?.name ?? 'supplier'}'
          ': supplier bill now ${po.receivedValue.toStringAsFixed(2)}',
      role: UserRole.accountant,
    );
    await _commit();
  }

  /// Pays the supplier for what was delivered and records it as an expense.
  Future<void> paySupplier(
    String poId, {
    String method = 'Bank transfer',
  }) async {
    final po = purchaseOrderById(poId)!;
    if (po.isPaid) throw HospitalException('Already paid');
    if (po.receivedValue <= 0) {
      throw HospitalException('Nothing has been delivered on this order');
    }
    final supplier = supplierById(po.supplierId);
    final e = Expense(
      id: newId('EXP'),
      date: DateTime.now(),
      category: 'Medical supplies',
      description: 'Purchase order ${po.number}',
      amount: po.receivedValue,
      vendor: supplier?.name ?? '',
      paymentMethod: method,
      recordedBy: currentUser?.id,
    );
    expenses.add(e);
    po
      ..paidAt = DateTime.now()
      ..expenseId = e.id;
    await _commit();
  }
}
