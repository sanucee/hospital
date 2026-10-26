part of 'hospital_store.dart';

/// The general store: non-drug supplies (consumables, linen, cleaning...)
/// received from suppliers and issued to departments against requisitions.
/// Every stock change is written to a stock card. Billable items issued for
/// a patient are charged to that patient.
extension StoresOperations on HospitalStore {
  StoreItem? storeItemById(String id) => _find(storeItems, (i) => i.id == id);

  Requisition? requisitionById(String id) =>
      _find(requisitions, (r) => r.id == id);

  List<StoreItem> get lowStockStoreItems =>
      storeItems.where((i) => i.isLowStock).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// Requisitions waiting for the store, oldest first.
  List<Requisition> get openRequisitions =>
      requisitions.where((r) => r.isOpen).toList()
        ..sort((a, b) => a.requestedAt.compareTo(b.requestedAt));

  List<Requisition> requisitionsBy(String staffId) =>
      requisitions.where((r) => r.requestedBy == staffId).toList()
        ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

  /// The stock card of an item, newest first.
  List<StockMovement> stockCard(String itemId) =>
      stockMovements.where((m) => m.itemId == itemId).toList()
        ..sort((a, b) => b.at.compareTo(a.at));

  double get storeStockValue => storeItems.fold(0, (s, i) => s + i.stockValue);

  void _move(
    StoreItem item,
    StockMovementKind kind,
    int quantity,
    String reference, {
    double? unitCost,
  }) {
    stockMovements.add(
      StockMovement(
        id: newId('MOV'),
        itemId: item.id,
        kind: kind,
        quantity: quantity,
        at: DateTime.now(),
        balance: item.stock,
        unitCost: unitCost ?? item.unitCost,
        reference: reference,
        by: currentUser?.id,
      ),
    );
  }

  Future<StoreItem> upsertStoreItem(StoreItem item) async {
    if (item.name.trim().isEmpty) throw HospitalException('Enter a name');
    if (item.reorderLevel < 0 || item.unitCost < 0 || item.patientPrice < 0) {
      throw HospitalException('Values cannot be negative');
    }
    final isNew = storeItemById(item.id) == null;
    if (isNew) {
      if (item.stock < 0) throw HospitalException('Stock cannot be negative');
      storeItems.add(item);
      if (item.stock > 0) {
        _move(item, StockMovementKind.adjusted, item.stock, 'Opening stock');
      }
    }
    await _commit();
    return item;
  }

  /// Stock delivered by a supplier. A [unitCost] above zero becomes the
  /// item's cost.
  Future<void> receiveStoreStock(
    String itemId,
    int quantity, {
    double unitCost = 0,
    String reference = '',
  }) async {
    if (quantity <= 0) throw HospitalException('Quantity must be positive');
    if (unitCost < 0) throw HospitalException('Cost cannot be negative');
    final item = storeItemById(itemId)!;
    item.stock += quantity;
    if (unitCost > 0) item.unitCost = unitCost;
    _move(
      item,
      StockMovementKind.received,
      quantity,
      reference.trim().isEmpty ? 'Delivery' : reference.trim(),
    );
    await _commit();
  }

  /// Sets the stock to what was physically counted.
  Future<void> countStoreStock(
    String itemId,
    int counted, {
    String reason = '',
  }) async {
    if (counted < 0) throw HospitalException('Count cannot be negative');
    final item = storeItemById(itemId)!;
    final diff = counted - item.stock;
    if (diff == 0) return;
    item.stock = counted;
    _move(
      item,
      StockMovementKind.adjusted,
      diff,
      reason.trim().isEmpty ? 'Stock count' : reason.trim(),
    );
    await _commit();
  }

  Future<Requisition> createRequisition({
    required String department,
    required Map<String, int> quantities,
    String? patientId,
    String notes = '',
  }) async {
    final lines = <RequisitionLine>[];
    for (final MapEntry(key: id, value: qty) in quantities.entries) {
      if (qty <= 0) continue;
      final item = storeItemById(id);
      if (item == null) continue;
      lines.add(
        RequisitionLine(itemId: id, itemName: item.name, quantity: qty),
      );
    }
    if (lines.isEmpty) throw HospitalException('Add at least one item');
    final me = currentUser;
    if (me == null) throw HospitalException('Sign in first');
    final n = await _next('requisition');
    final r = Requisition(
      id: newId('REQ'),
      number: n == null
          ? 'REQ-T${_offlineNumber()}'
          : 'REQ-${n.toString().padLeft(5, '0')}',
      department: department,
      requestedBy: me.id,
      requestedAt: DateTime.now(),
      lines: lines,
      patientId: patientId,
      notes: notes.trim(),
    );
    requisitions.add(r);
    _notify(
      title: 'Store requisition',
      body:
          '${r.number} from $department (${me.name}): '
          '${lines.length} item(s)'
          '${patientId == null ? '' : ' for ${patientName(patientId)}'}',
      role: UserRole.storekeeper,
      patientId: patientId,
    );
    await _commit();
    return r;
  }

  /// Issues stock against a requisition. [quantities] maps line index →
  /// quantity to issue now; omitted lines get their full outstanding amount.
  /// As with dispensing, asking for more than is in stock fails without
  /// changing anything.
  Future<void> issueRequisition(
    String requisitionId, {
    Map<int, int>? quantities,
  }) async {
    final r = requisitionById(requisitionId)!;
    if (!r.isOpen) {
      throw HospitalException('Requisition is ${r.status.label.toLowerCase()}');
    }
    final plan = <int, int>{};
    for (var i = 0; i < r.lines.length; i++) {
      final line = r.lines[i];
      final qty = quantities?[i] ?? line.outstanding;
      if (qty <= 0) continue;
      if (qty > line.outstanding) {
        throw HospitalException(
          '${line.itemName}: only ${line.outstanding} outstanding',
        );
      }
      final item = storeItemById(line.itemId);
      if (item == null) {
        throw HospitalException('${line.itemName} is no longer stocked');
      }
      if (item.stock < qty) {
        throw HospitalException(
          '${item.name}: only ${item.stock} in stock, $qty requested',
        );
      }
      plan[i] = qty;
    }
    if (plan.isEmpty) throw HospitalException('Nothing to issue');

    // Billable items for a patient go on their admission's bill, or a new
    // one.
    Invoice? invoice;
    final pid = r.patientId;
    final billable =
        pid != null &&
        plan.keys.any((i) => storeItemById(r.lines[i].itemId)!.billable);
    if (billable) {
      final admission = activeAdmissionFor(pid);
      invoice = admission == null ? null : invoiceForAdmission(admission.id);
      if (invoice == null) {
        final number = await _next('invoice');
        invoice = _newInvoice(
          patientId: pid,
          admissionId: admission?.id,
          number: number,
        );
      }
    }

    for (final MapEntry(key: i, value: qty) in plan.entries) {
      final line = r.lines[i];
      final item = storeItemById(line.itemId)!;
      item.stock -= qty;
      line.issuedQuantity += qty;
      _move(
        item,
        StockMovementKind.issued,
        -qty,
        '${r.number} ${r.department}',
      );
      if (invoice != null && item.billable) {
        invoice.lines.add(
          InvoiceLine(
            id: newId('LINE'),
            department: BillingDepartment.supplies,
            description: '${item.name} (${item.unit})',
            quantity: qty,
            unitPrice: item.patientPrice,
            sourceId: r.id,
          ),
        );
      }
      if (item.isLowStock) {
        _notify(
          title: 'Store item low',
          body: '${item.name} is down to ${item.stock} ${item.unit}',
          role: UserRole.storekeeper,
        );
      }
    }
    final done = r.lines.every((l) => l.outstanding <= 0);
    r
      ..status = done
          ? RequisitionStatus.issued
          : RequisitionStatus.partlyIssued
      ..issuedBy = currentUser?.id
      ..issuedAt = DateTime.now();
    _notify(
      title: done ? 'Requisition issued' : 'Requisition partly issued',
      body: '${r.number}: supplies ready for ${r.department}',
      userId: r.requestedBy,
      patientId: r.patientId,
    );
    await _commit();
  }

  Future<void> rejectRequisition(String requisitionId, String note) async {
    final r = requisitionById(requisitionId)!;
    if (r.status != RequisitionStatus.pending) {
      throw HospitalException('Only pending requisitions can be rejected');
    }
    if (note.trim().isEmpty) throw HospitalException('Enter the reason');
    r
      ..status = RequisitionStatus.rejected
      ..decisionNote = note.trim()
      ..issuedBy = currentUser?.id
      ..issuedAt = DateTime.now();
    _notify(
      title: 'Requisition rejected',
      body: '${r.number}: ${r.decisionNote}',
      userId: r.requestedBy,
    );
    await _commit();
  }

  /// The requester withdraws a requisition the store hasn't acted on.
  Future<void> cancelRequisition(String requisitionId) async {
    final r = requisitionById(requisitionId)!;
    if (r.status != RequisitionStatus.pending) {
      throw HospitalException('Only pending requisitions can be cancelled');
    }
    r.status = RequisitionStatus.cancelled;
    await _commit();
  }
}
