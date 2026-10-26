part of 'hospital_store.dart';

/// Imaging: doctors request studies from a consultation, radiology books,
/// performs and reports them, and the doctor is told when the report is
/// ready. Studies are billed on the visit's invoice when requested, like
/// lab tests.
extension RadiologyOperations on HospitalStore {
  ImagingStudy? imagingStudyById(String id) =>
      _find(imagingStudies, (s) => s.id == id);

  ImagingOrder? imagingOrderById(String id) =>
      _find(imagingOrders, (o) => o.id == id);

  /// Studies still to be done or reported, urgent first.
  List<ImagingOrder> get imagingQueue =>
      imagingOrders.where((o) => o.isPending).toList()..sort((a, b) {
        if (a.urgent != b.urgent) return a.urgent ? -1 : 1;
        return a.orderedAt.compareTo(b.orderedAt);
      });

  List<ImagingOrder> imagingOrdersFor({
    String? patientId,
    String? consultationId,
  }) =>
      imagingOrders
          .where(
            (o) =>
                (patientId == null || o.patientId == patientId) &&
                (consultationId == null || o.consultationId == consultationId),
          )
          .toList()
        ..sort((a, b) => b.orderedAt.compareTo(a.orderedAt));

  /// Reports the doctor hasn't acknowledged yet.
  List<ImagingOrder> unreviewedImaging(String doctorId) => imagingOrders
      .where(
        (o) =>
            o.doctorId == doctorId &&
            o.status == ImagingStatus.reported &&
            !o.reviewedByDoctor,
      )
      .toList();

  Future<ImagingStudy> upsertImagingStudy(ImagingStudy s) async {
    if (s.name.trim().isEmpty) throw HospitalException('Enter a name');
    if (s.price < 0) throw HospitalException('Price cannot be negative');
    if (imagingStudyById(s.id) == null) imagingStudies.add(s);
    await _commit();
    return s;
  }

  Future<List<ImagingOrder>> orderImaging({
    required String consultationId,
    required List<String> studyIds,
    bool urgent = false,
    String clinicalNotes = '',
  }) async {
    final c = consultationById(consultationId)!;
    final invoice = _invoiceFor(c);
    final created = <ImagingOrder>[];
    for (final sid in studyIds) {
      final s = imagingStudyById(sid);
      if (s == null) continue;
      final o = ImagingOrder(
        id: newId('IMG'),
        consultationId: c.id,
        patientId: c.patientId,
        doctorId: c.doctorId,
        studyId: s.id,
        studyName: s.name,
        modality: s.modality,
        price: s.price,
        orderedAt: DateTime.now(),
        urgent: urgent,
        clinicalNotes: clinicalNotes.trim(),
      );
      imagingOrders.add(o);
      created.add(o);
      invoice.lines.add(
        InvoiceLine(
          id: newId('LINE'),
          department: BillingDepartment.radiology,
          description: 'Imaging: ${s.name}',
          quantity: 1,
          unitPrice: s.price,
          sourceId: o.id,
        ),
      );
    }
    if (created.isNotEmpty) {
      _notify(
        title: urgent ? 'URGENT imaging request' : 'New imaging request',
        body:
            '${created.map((o) => o.studyName).join(', ')} for '
            '${patientName(c.patientId)} from ${userName(c.doctorId)}',
        role: UserRole.radiographer,
        patientId: c.patientId,
      );
    }
    await _commit();
    return created;
  }

  /// Books a time for the study (e.g. an MRI slot or a fasting ultrasound).
  Future<void> scheduleImaging(String orderId, DateTime at) async {
    final o = imagingOrderById(orderId)!;
    if (o.status != ImagingStatus.ordered &&
        o.status != ImagingStatus.scheduled) {
      throw HospitalException('Study is ${o.status.label.toLowerCase()}');
    }
    o
      ..scheduledAt = at
      ..status = ImagingStatus.scheduled;
    await _commit();
  }

  Future<void> markImagingPerformed(String orderId) async {
    final o = imagingOrderById(orderId)!;
    if (o.status != ImagingStatus.ordered &&
        o.status != ImagingStatus.scheduled) {
      throw HospitalException('Study is ${o.status.label.toLowerCase()}');
    }
    o
      ..status = ImagingStatus.performed
      ..performedAt = DateTime.now()
      ..radiographerId = currentUser?.id;
    await _commit();
  }

  /// Records the report and tells the requesting doctor.
  Future<void> reportImaging(
    String orderId, {
    required String findings,
    required String impression,
    bool abnormal = false,
  }) async {
    final o = imagingOrderById(orderId)!;
    if (o.status == ImagingStatus.cancelled) {
      throw HospitalException('Study was cancelled');
    }
    if (o.status == ImagingStatus.ordered ||
        o.status == ImagingStatus.scheduled) {
      throw HospitalException('Mark the study as performed first');
    }
    if (impression.trim().isEmpty) {
      throw HospitalException('Enter the impression');
    }
    o
      ..findings = findings.trim()
      ..impression = impression.trim()
      ..abnormal = abnormal
      ..status = ImagingStatus.reported
      ..reportedAt = DateTime.now()
      ..reportedBy = currentUser?.id
      ..reviewedByDoctor = false;
    _notify(
      title: abnormal ? 'ABNORMAL imaging report' : 'Imaging report ready',
      body: '${o.studyName} for ${patientName(o.patientId)}: ${o.impression}',
      userId: o.doctorId,
      patientId: o.patientId,
    );
    await _commit();
  }

  /// Cancels a study that hasn't been done and removes its charge.
  Future<void> cancelImagingOrder(String orderId) async {
    final o = imagingOrderById(orderId)!;
    if (o.status != ImagingStatus.ordered &&
        o.status != ImagingStatus.scheduled) {
      throw HospitalException('Only studies not yet done can be cancelled');
    }
    o.status = ImagingStatus.cancelled;
    invoiceForConsultation(o.consultationId)?.lines
        .removeWhere((l) => l.sourceId == o.id);
    await _commit();
  }

  Future<void> markImagingReviewed(String orderId) async {
    imagingOrderById(orderId)?.reviewedByDoctor = true;
    await _commit();
  }
}
