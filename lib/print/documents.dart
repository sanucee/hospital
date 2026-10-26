import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/hospital_store.dart';
import '../models/models.dart';

/// Printable documents (A4 PDFs) built from hospital records.
///
/// Pure Dart: these run in tests and on every platform. The built-in PDF
/// fonts only cover basic Latin, so text passes through [_t], which maps
/// typographic characters to plain equivalents.

final _money = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
final _date = DateFormat('d MMM yyyy');
final _dateTime = DateFormat('d MMM yyyy, HH:mm');
final _month = DateFormat('MMMM yyyy');

String _m(num v) => _money.format(v);
String _d(DateTime? d) => d == null ? '-' : _date.format(d);
String _dt(DateTime? d) => d == null ? '-' : _dateTime.format(d);

const _plain = {
  '–': '-',
  '—': '-',
  '×': 'x',
  '·': '|',
  '…': '...',
  '‘': "'",
  '’': "'",
  '“': '"',
  '”': '"',
  '₂': '2',
  '°': ' deg',
  '→': '->',
};

String _t(String s) {
  final b = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    final mapped = _plain[c];
    if (mapped != null) {
      b.write(mapped);
    } else if (ch < 0x20 && ch != 0x0A) {
      continue;
    } else if (ch > 0xFF) {
      b.write('?');
    } else {
      b.write(c);
    }
  }
  return b.toString();
}

final _grey = PdfColor.fromInt(0xFF666666);
final _accent = PdfColor.fromInt(0xFF00796B);

pw.Widget _text(
  String s, {
  double size = 10,
  bool bold = false,
  PdfColor? color,
}) => pw.Text(
  _t(s),
  style: pw.TextStyle(
    fontSize: size,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    color: color,
  ),
);

Future<Uint8List> _document(
  HospitalStore s, {
  required String title,
  required String reference,
  required List<pw.Widget> Function() body,
}) {
  final p = s.profile;
  final doc = pw.Document(title: _t('$title $reference'), author: _t(p.name));
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _text(p.name, size: 16, bold: true, color: _accent),
                    if (p.address.isNotEmpty) _text(p.address, size: 9),
                    _text(
                      [
                        if (p.phone.isNotEmpty) 'Tel ${p.phone}',
                        if (p.email.isNotEmpty) p.email,
                        if (p.taxId.isNotEmpty) 'Tax ID ${p.taxId}',
                      ].join('  |  '),
                      size: 9,
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _text(title.toUpperCase(), size: 14, bold: true),
                  _text(reference, size: 10),
                ],
              ),
            ],
          ),
          pw.Divider(color: _accent, thickness: 1.5),
          pw.SizedBox(height: 6),
        ],
      ),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _text(
            p.receiptFooter.isEmpty ? '' : p.receiptFooter,
            size: 8,
            color: _grey,
          ),
          _text(
            'Printed ${_dt(DateTime.now())}  |  Page ${ctx.pageNumber} of '
            '${ctx.pagesCount}',
            size: 8,
            color: _grey,
          ),
        ],
      ),
      build: (ctx) => body(),
    ),
  );
  return doc.save();
}

/// Label/value pairs in two columns.
pw.Widget _info(List<(String, String)> rows) => pw.Table(
  columnWidths: const {0: pw.FixedColumnWidth(110), 1: pw.FlexColumnWidth()},
  children: [
    for (final (k, v) in rows)
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
            child: _text(k, size: 9, color: _grey),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
            child: _text(v.isEmpty ? '-' : v, size: 9),
          ),
        ],
      ),
  ],
);

pw.Widget _patientBlock(
  HospitalStore s,
  String patientId, {
  List<(String, String)> extra = const [],
}) {
  final p = s.patientById(patientId);
  return _info([
    ('Patient', p?.name ?? 'Unknown'),
    ('MRN', p?.mrn ?? ''),
    if (p != null) ('Age / sex', '${p.age} years, ${p.gender}'),
    if (p != null && p.phone.isNotEmpty) ('Phone', p.phone),
    ...extra,
  ]);
}

pw.Widget _table(
  List<String> headers,
  List<List<String>> rows, {
  Map<int, pw.TableColumnWidth>? widths,
  Set<int> rightAligned = const {},
}) => pw.TableHelper.fromTextArray(
  headers: headers.map(_t).toList(),
  data: [for (final r in rows) r.map(_t).toList()],
  headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
  cellStyle: const pw.TextStyle(fontSize: 9),
  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
  columnWidths: widths,
  cellAlignments: {for (final i in rightAligned) i: pw.Alignment.centerRight},
  border: const pw.TableBorder(
    horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
    bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
  ),
);

pw.Widget _totals(List<(String, double, bool)> rows) => pw.Align(
  alignment: pw.Alignment.centerRight,
  child: pw.SizedBox(
    width: 240,
    child: pw.Column(
      children: [
        for (final (label, v, bold) in rows)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
            child: pw.Row(
              children: [
                pw.Expanded(child: _text(label, bold: bold)),
                _text(_m(v), bold: bold),
              ],
            ),
          ),
      ],
    ),
  ),
);

pw.Widget _section(String title) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
  child: _text(title, size: 11, bold: true, color: _accent),
);

pw.Widget _signature(String label) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 36),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(width: 180, height: 0.7, color: PdfColors.grey600),
      _text(label, size: 9, color: _grey),
    ],
  ),
);

// -----------------------------------------------------------------------------
// Billing
// -----------------------------------------------------------------------------

/// A bill, or a receipt once fully paid: charges by department, insurance
/// split and payments.
Future<Uint8List> invoicePdf(HospitalStore s, Invoice inv) {
  final insurer = s.insurerById(inv.insurerId);
  final patient = s.patientById(inv.patientId);
  final paid = s.paymentsFor(inv.id);
  return _document(
    s,
    title: inv.isPaid ? 'Receipt' : 'Invoice',
    reference: inv.number,
    body: () => [
      _patientBlock(
        s,
        inv.patientId,
        extra: [
          ('Date', _dt(inv.createdAt)),
          (
            'Visit',
            inv.admissionId != null
                ? 'Inpatient admission'
                : inv.surgeryId != null
                ? 'Day-case surgery'
                : 'Outpatient consultation',
          ),
          if (insurer != null)
            (
              'Insurance',
              '${insurer.name}, policy ${patient?.policyNumber ?? ''} '
                  '(${inv.coveragePercent.toStringAsFixed(0)}%'
                  '${inv.coverageLimit > 0 ? ', limit ${_m(inv.coverageLimit)}' : ''})',
            ),
        ],
      ),
      pw.SizedBox(height: 10),
      _table(
        ['Department', 'Description', 'Qty', 'Unit price', 'Amount'],
        [
          for (final l in inv.lines)
            [
              l.department.label,
              l.description,
              '${l.quantity}',
              _m(l.unitPrice),
              _m(l.total),
            ],
        ],
        widths: const {
          0: pw.FixedColumnWidth(85),
          1: pw.FlexColumnWidth(),
          2: pw.FixedColumnWidth(35),
          3: pw.FixedColumnWidth(65),
          4: pw.FixedColumnWidth(70),
        },
        rightAligned: {2, 3, 4},
      ),
      pw.SizedBox(height: 8),
      _totals([
        ('Subtotal', inv.subtotal, false),
        if (inv.discount > 0) ('Discount', -inv.discount, false),
        ('Total', inv.total, true),
        if (insurer != null) ...[
          (
            inv.insurerApproved == null
                ? 'Insurance share (estimated)'
                : 'Insurance share (approved)',
            inv.insurerCovered,
            false,
          ),
          ('Patient share', inv.patientDue, false),
          ('Paid by insurer', inv.insurerPaid, false),
        ],
        ('Paid by patient', inv.amountPaid, false),
        (
          insurer != null ? 'Patient balance due' : 'Balance due',
          insurer != null ? inv.patientBalance : inv.balance,
          true,
        ),
      ]),
      if (paid.isNotEmpty) ...[
        _section('Payments'),
        _table(
          ['Date', 'Method', 'Received by', 'Amount'],
          [
            for (final p in paid)
              [
                _dt(p.receivedAt),
                p.method,
                p.receivedBy == null ? '' : s.userName(p.receivedBy!),
                _m(p.amount),
              ],
          ],
          rightAligned: {3},
        ),
      ],
    ],
  );
}

/// A receipt for a single payment.
Future<Uint8List> paymentReceiptPdf(HospitalStore s, Payment p) {
  final inv = s.invoices.firstWhere((i) => i.id == p.invoiceId);
  final receiptNo =
      p.receiptNo ?? 'RCT-${p.id.split('-').skip(1).take(1).join()}';
  return _document(
    s,
    title: 'Payment receipt',
    reference: receiptNo,
    body: () => [
      _patientBlock(
        s,
        p.patientId,
        extra: [
          ('Received', _dt(p.receivedAt)),
          ('For invoice', inv.number),
          ('Method', p.method),
          if (p.receivedBy != null) ('Received by', s.userName(p.receivedBy!)),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _accent),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(child: _text('Amount received', size: 12)),
            _text(_m(p.amount), size: 16, bold: true),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
      _totals([
        ('Invoice total', inv.total, false),
        ('Paid to date', inv.amountPaid + inv.insurerPaid, false),
        ('Balance remaining', inv.balance, true),
      ]),
      _signature('Cashier'),
    ],
  );
}

/// A counter receipt: one payment that may cover several bills, with the
/// cash handed over and change when given.
Future<Uint8List> counterReceiptPdf(
  HospitalStore s,
  String receiptNo, {
  double? tendered,
  double? change,
}) {
  final paid = s.paymentsOnReceipt(receiptNo);
  final first = paid.first;
  final total = paid.fold<double>(0, (t, p) => t + p.amount);
  final bills = [for (final p in paid) s.invoiceById(p.invoiceId)!];
  final stillOwed = s
      .outstandingFor(first.patientId)
      .fold<double>(0, (t, i) => t + i.patientBalance);
  return _document(
    s,
    title: 'Receipt',
    reference: receiptNo,
    body: () => [
      _patientBlock(
        s,
        first.patientId,
        extra: [
          ('Received', _dt(first.receivedAt)),
          ('Method', first.method),
          if (first.reference.isNotEmpty) ('Reference', first.reference),
          if (first.receivedBy != null)
            ('Cashier', s.userName(first.receivedBy!)),
        ],
      ),
      pw.SizedBox(height: 12),
      _table(
        ['Bill', 'Date', 'Bill total', 'Paid now', 'Left to pay'],
        [
          for (final (i, p) in paid.indexed)
            [
              bills[i].number,
              _d(bills[i].createdAt),
              _m(bills[i].total),
              _m(p.amount),
              _m(bills[i].patientBalance),
            ],
        ],
        rightAligned: {2, 3, 4},
      ),
      pw.SizedBox(height: 12),
      _totals([
        ('Amount received', total, true),
        if (tendered != null) ('Cash handed over', tendered, false),
        if (change != null && tendered != null) ('Change given', change, false),
        ('Still owed on all bills', stillOwed, false),
      ]),
      _signature('Cashier'),
    ],
  );
}

/// The cash-up for one till: takings by method, every payment, and the
/// count against what should be in the drawer.
Future<Uint8List> tillReportPdf(HospitalStore s, CashTill t) {
  final paid = s.paymentsInTill(t.id);
  final totals = s.tillTotals(t.id);
  final expected = t.expectedCash ?? s.expectedCash(t);
  return _document(
    s,
    title: 'Till cash-up',
    reference: _d(t.openedAt),
    body: () => [
      _info([
        ('Cashier', s.userName(t.cashierId)),
        ('Opened', _dt(t.openedAt)),
        ('Closed', t.isOpen ? 'Still open' : _dt(t.closedAt)),
        ('Payments', '${paid.length}'),
        if (t.notes.isNotEmpty) ('Notes', t.notes),
      ]),
      pw.SizedBox(height: 12),
      _table(
        ['Time', 'Receipt', 'Patient', 'Method', 'Reference', 'Amount'],
        [
          for (final p in paid)
            [
              DateFormat('HH:mm').format(p.receivedAt),
              p.receiptNo ?? '',
              s.patientName(p.patientId),
              p.isRefund ? '${p.method} refund' : p.method,
              p.reference,
              _m(p.amount),
            ],
        ],
        rightAligned: {5},
      ),
      pw.SizedBox(height: 12),
      _totals([
        for (final MapEntry(key: m, value: v) in totals.entries)
          ('$m (after refunds)', v, false),
        for (final MapEntry(key: m, value: v) in s.tillRefunds(t.id).entries)
          ('$m refunded', v, false),
        ('Opening float', t.openingFloat, false),
        ('Cash expected in drawer', expected, true),
        if (t.countedCash != null) ('Cash counted', t.countedCash!, false),
        if (t.variance != null)
          (t.variance! < 0 ? 'Short' : 'Over', t.variance!.abs(), true),
      ]),
      _signature('Cashier'),
      _signature('Checked by'),
    ],
  );
}

/// The voucher a patient signs when money is given back.
Future<Uint8List> refundVoucherPdf(HospitalStore s, Refund r) {
  final paid = s.payments.where((p) => p.id == r.paymentId).firstOrNull;
  final inv = s.invoiceById(r.invoiceId);
  return _document(
    s,
    title: 'Refund',
    reference: r.number ?? 'Not yet paid',
    body: () => [
      _patientBlock(
        s,
        r.patientId,
        extra: [
          ('Bill', inv?.number ?? '-'),
          if (paid != null)
            (
              'Original payment',
              '${_m(paid.amount)} ${paid.method} on ${_d(paid.receivedAt)}'
                  '${paid.receiptNo == null ? '' : ' (${paid.receiptNo})'}',
            ),
          ('Refunded by', r.method),
          if (r.reference.isNotEmpty) ('Reference', r.reference),
          ('Reason', r.reason),
          ('Requested by', s.userName(r.requestedBy)),
          if (r.decidedBy != null) ('Approved by', s.userName(r.decidedBy!)),
          if (r.paidAt != null) ('Paid out', _dt(r.paidAt)),
          if (r.paidBy != null) ('Paid out by', s.userName(r.paidBy!)),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _accent),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(child: _text('Amount refunded', size: 12)),
            _text(_m(r.amount), size: 16, bold: true),
          ],
        ),
      ),
      if (inv != null) ...[
        pw.SizedBox(height: 12),
        _totals([
          ('Bill total', inv.total, false),
          ('Paid after this refund', inv.amountPaid + inv.insurerPaid, false),
          ('Balance', inv.balance, true),
        ]),
      ],
      _signature('Received by the patient'),
      _signature('Cashier'),
    ],
  );
}

/// The day's money: takings and refunds by method, every cashier's till
/// and the count, for sign-off at the end of the day.
Future<Uint8List> dayEndPdf(HospitalStore s, DateTime day) {
  final d = s.dayEnd(day);
  final methods = {...d.collected.keys, ...d.refunded.keys}.toList()..sort();
  return _document(
    s,
    title: 'Day-end cash report',
    reference: _d(day),
    body: () => [
      if (d.openTills.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: _text(
            'Still open: ${d.openTills.map((t) => s.userName(t.cashierId)).join(', ')}. '
            'Their figures may change.',
            bold: true,
            color: PdfColors.red,
          ),
        ),
      _section('Takings by method'),
      _table(
        ['Method', 'Collected', 'Refunded', 'Net'],
        [
          for (final m in methods)
            [
              m,
              _m(d.collected[m] ?? 0),
              _m(d.refunded[m] ?? 0),
              _m((d.collected[m] ?? 0) - (d.refunded[m] ?? 0)),
            ],
          [
            'Total',
            _m(d.totalCollected),
            _m(d.totalRefunded),
            _m(d.totalCollected - d.totalRefunded),
          ],
        ],
        rightAligned: {1, 2, 3},
      ),
      pw.SizedBox(height: 8),
      _info([
        ('Patient payments', '${d.payments.length}'),
        ('Refunds paid', '${d.refunds.length}'),
        ('Insurer settlements', _m(d.insurer)),
        ('Net received today', _m(d.net)),
      ]),
      _section('Tills'),
      if (d.tills.isEmpty)
        _text('No tills were opened.')
      else
        _table(
          [
            'Cashier',
            'Opened',
            'Closed',
            'Float',
            'Net cash',
            'Expected',
            'Counted',
            'Over/short',
          ],
          [
            for (final t in d.tills)
              [
                s.userName(t.cashierId),
                DateFormat('HH:mm').format(t.openedAt),
                t.closedAt == null
                    ? 'OPEN'
                    : DateFormat('HH:mm').format(t.closedAt!),
                _m(t.openingFloat),
                _m(s.tillTotals(t.id)['Cash'] ?? 0),
                _m(t.expectedCash ?? s.expectedCash(t)),
                t.countedCash == null ? '-' : _m(t.countedCash!),
                t.variance == null ? '-' : _m(t.variance!),
              ],
          ],
          rightAligned: {3, 4, 5, 6, 7},
        ),
      pw.SizedBox(height: 8),
      _totals([
        ('Net cash taken', d.netCash, false),
        ('Tills over (+) / short (-)', d.variance, true),
      ]),
      if (d.refunds.isNotEmpty) ...[
        _section('Refunds'),
        _table(
          ['Voucher', 'Patient', 'Method', 'Reason', 'Approved by', 'Amount'],
          [
            for (final r in d.refunds)
              [
                r.number ?? '',
                s.patientName(r.patientId),
                r.method,
                r.reason,
                r.decidedBy == null ? '' : s.userName(r.decidedBy!),
                _m(r.amount),
              ],
          ],
          rightAligned: {5},
        ),
      ],
      _signature('Prepared by'),
      _signature('Checked by (accounts)'),
    ],
  );
}

/// A claim form to send to the insurer with the itemised bill.
Future<Uint8List> claimPdf(HospitalStore s, InsuranceClaim c) {
  final inv = s.invoices.firstWhere((i) => i.id == c.invoiceId);
  final insurer = s.insurerById(c.insurerId);
  final patient = s.patientById(c.patientId);
  return _document(
    s,
    title: 'Insurance claim',
    reference: c.number,
    body: () => [
      _info([
        ('To', insurer?.name ?? ''),
        if (insurer != null && insurer.contact.isNotEmpty)
          ('Contact', insurer.contact),
        ('Claim date', _d(c.submittedAt ?? c.createdAt)),
        if (c.insurerReference.isNotEmpty)
          ('Insurer reference', c.insurerReference),
      ]),
      pw.SizedBox(height: 8),
      _patientBlock(
        s,
        c.patientId,
        extra: [
          ('Policy number', patient?.policyNumber ?? ''),
          if (patient?.policyExpiry != null)
            ('Policy valid to', _d(patient!.policyExpiry)),
          ('Invoice', '${inv.number} of ${_d(inv.createdAt)}'),
        ],
      ),
      _section('Services provided'),
      _table(
        ['Department', 'Description', 'Qty', 'Amount'],
        [
          for (final l in inv.lines)
            [l.department.label, l.description, '${l.quantity}', _m(l.total)],
        ],
        rightAligned: {2, 3},
      ),
      pw.SizedBox(height: 8),
      _totals([
        ('Bill total', inv.total, false),
        (
          'Coverage ${inv.coveragePercent.toStringAsFixed(0)}%'
              '${inv.coverageLimit > 0 ? ' (limit ${_m(inv.coverageLimit)})' : ''}',
          inv.insurerShare,
          false,
        ),
        ('Amount claimed', c.amountClaimed, true),
      ]),
      _signature('Authorised signatory, ${s.profile.name}'),
    ],
  );
}

// -----------------------------------------------------------------------------
// Clinical
// -----------------------------------------------------------------------------

Future<Uint8List> prescriptionPdf(HospitalStore s, Prescription rx) {
  final c = s.consultationById(rx.consultationId);
  final patient = s.patientById(rx.patientId);
  final doctor = s.userById(rx.doctorId);
  return _document(
    s,
    title: 'Prescription',
    reference: _d(rx.createdAt),
    body: () => [
      _patientBlock(
        s,
        rx.patientId,
        extra: [
          if (patient != null && patient.allergies.isNotEmpty)
            ('ALLERGIES', patient.allergies),
          if (c != null && c.diagnosis.isNotEmpty) ('Diagnosis', c.diagnosis),
        ],
      ),
      pw.SizedBox(height: 10),
      _text('Rx', size: 20, bold: true, color: _accent),
      _table(
        ['Medicine', 'Dose', 'Frequency', 'Days', 'Qty', 'Instructions'],
        [
          for (final i in rx.items)
            [
              i.medicineName,
              i.dosage,
              i.frequency,
              '${i.durationDays}',
              '${i.quantity}',
              i.instructions,
            ],
        ],
        rightAligned: {3, 4},
      ),
      _signature(
        '${doctor?.name ?? ''}'
        '${doctor?.specialization == null ? '' : ', ${doctor!.specialization}'}',
      ),
    ],
  );
}

/// Results of the completed tests among [orders] (usually one visit's).
Future<Uint8List> labReportPdf(HospitalStore s, List<LabOrder> orders) {
  final done = orders
      .where((o) => o.status == LabOrderStatus.completed)
      .toList();
  final first = done.isEmpty ? orders.first : done.first;
  final techs = {
    for (final o in done)
      if (o.technicianId != null) s.userName(o.technicianId!),
  };
  return _document(
    s,
    title: 'Laboratory report',
    reference: _d(first.completedAt ?? first.orderedAt),
    body: () => [
      _patientBlock(
        s,
        first.patientId,
        extra: [
          ('Requested by', s.userName(first.doctorId)),
          ('Requested', _dt(first.orderedAt)),
        ],
      ),
      pw.SizedBox(height: 10),
      _table(
        ['Test', 'Result', 'Reference range', 'Flag', 'Reported'],
        [
          for (final o in done)
            [
              o.testName,
              '${o.result}${o.resultRemarks.isEmpty ? '' : ' (${o.resultRemarks})'}',
              '${s.labTestById(o.testId)?.referenceRange ?? ''} '
                  '${s.labTestById(o.testId)?.unit ?? ''}',
              o.abnormal ? 'ABNORMAL' : '',
              _dt(o.completedAt),
            ],
        ],
      ),
      if (done.length < orders.length)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: _text(
            '${orders.length - done.length} test(s) still pending.',
            size: 9,
            color: _grey,
          ),
        ),
      _signature('Laboratory: ${techs.join(', ')}'),
    ],
  );
}

Future<Uint8List> dischargeSummaryPdf(HospitalStore s, Admission a) {
  final end = a.dischargedAt ?? DateTime.now();
  final days = a.billableDays(end);
  final ops = s
      .surgeriesFor(a.patientId)
      .where(
        (x) => x.admissionId == a.id && x.status == SurgeryStatus.completed,
      )
      .toList();
  return _document(
    s,
    title: 'Discharge summary',
    reference: _d(a.dischargedAt),
    body: () => [
      _patientBlock(
        s,
        a.patientId,
        extra: [
          ('Admitted', _dt(a.admittedAt)),
          ('Discharged', _dt(a.dischargedAt)),
          ('Consultant', s.userName(a.doctorId)),
          ('Reason', a.reason),
        ],
      ),
      _section('Stay'),
      _table(
        ['Room', 'From', 'To', 'Days'],
        [
          for (final (i, st) in a.stays.indexed)
            [st.roomName, _dt(st.from), _dt(st.to), '${days[i]}'],
        ],
        rightAligned: {3},
      ),
      if (ops.isNotEmpty) ...[
        _section('Procedures'),
        _table(
          ['Date', 'Procedure', 'Surgeon', 'Notes'],
          [
            for (final o in ops)
              [_d(o.startedAt), o.procedure, s.userName(o.surgeonId), o.notes],
          ],
        ),
      ],
      _section('Summary and advice'),
      _text(a.dischargeSummary.isEmpty ? '-' : a.dischargeSummary),
      _signature(s.userName(a.doctorId)),
    ],
  );
}

// -----------------------------------------------------------------------------
// HR and purchasing
// -----------------------------------------------------------------------------

Future<Uint8List> payslipPdf(HospitalStore s, Payslip p) {
  final u = s.userById(p.staffId);
  final bank = s.salaryFor(p.staffId)?.bankAccount ?? '';
  return _document(
    s,
    title: 'Payslip',
    reference: _month.format(p.month),
    body: () => [
      _info([
        ('Employee', u?.name ?? ''),
        (
          'Role',
          [
            u?.role.label ?? '',
            u?.designation ?? '',
          ].where((x) => x.isNotEmpty).join(', '),
        ),
        if ((u?.department ?? '').isNotEmpty) ('Department', u!.department),
        if (bank.isNotEmpty) ('Bank account', bank),
        (
          'Status',
          p.status == PayslipStatus.paid
              ? 'Paid ${_d(p.paidAt)} (${p.paymentMethod})'
              : 'Not yet paid',
        ),
      ]),
      pw.SizedBox(height: 12),
      _table(
        ['Earnings', 'Amount', 'Deductions', 'Amount'],
        [
          [
            'Basic salary',
            _m(p.basic),
            'Tax, pension and others',
            _m(p.deductions),
          ],
          [
            'Allowances',
            _m(p.allowances),
            p.unpaidLeaveDays > 0
                ? 'Unpaid leave (${p.unpaidLeaveDays} days)'
                : '',
            p.unpaidLeaveDays > 0 ? _m(p.leaveDeduction) : '',
          ],
          [
            'Gross pay',
            _m(p.gross),
            'Total deductions',
            _m(p.deductions + p.leaveDeduction),
          ],
        ],
        rightAligned: {1, 3},
      ),
      pw.SizedBox(height: 10),
      _totals([('Net pay', p.net, true)]),
    ],
  );
}

Future<Uint8List> purchaseOrderPdf(HospitalStore s, PurchaseOrder po) {
  final sup = s.supplierById(po.supplierId);
  return _document(
    s,
    title: 'Purchase order',
    reference: po.number,
    body: () => [
      _info([
        ('Supplier', sup?.name ?? ''),
        if ((sup?.contactPerson ?? '').isNotEmpty)
          ('Attention', sup!.contactPerson),
        if ((sup?.phone ?? '').isNotEmpty) ('Phone', sup!.phone),
        if ((sup?.email ?? '').isNotEmpty) ('Email', sup!.email),
        ('Order date', _d(po.orderedAt ?? po.createdAt)),
        if (po.expectedOn != null) ('Deliver by', _d(po.expectedOn)),
        ('Status', po.status.label),
      ]),
      pw.SizedBox(height: 10),
      _table(
        ['Item', 'Qty ordered', 'Received', 'Unit cost', 'Amount'],
        [
          for (final i in po.items)
            [
              i.medicineName,
              '${i.quantity}',
              '${i.receivedQuantity}',
              _m(i.unitCost),
              _m(i.total),
            ],
        ],
        rightAligned: {1, 2, 3, 4},
      ),
      pw.SizedBox(height: 8),
      _totals([
        ('Order total', po.total, true),
        if (po.receivedValue > 0) ('Value received', po.receivedValue, false),
      ]),
      if (po.notes.isNotEmpty) ...[_section('Notes'), _text(po.notes)],
      _signature('Authorised by'),
    ],
  );
}
