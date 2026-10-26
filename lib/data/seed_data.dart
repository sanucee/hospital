part of 'hospital_store.dart';

/// Initial data so every department has something to work with on first
/// launch.
///
/// [admin] replaces the demo administrator (used when a real hospital is set
/// up on Firebase). Without [demo], only the administrator, the lab test
/// catalogue and the medicine list are created.
void _seedDemoData(HospitalStore s, {bool demo = true, StaffUser? admin}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  StaffUser staff(
    String id,
    String name,
    String username,
    UserRole role, {
    String? specialization,
    double fee = 0,
    String department = '',
    String designation = '',
  }) => StaffUser(
    id: id,
    name: name,
    username: username,
    // With Firebase, demo staff get logins from the Staff screen instead;
    // support staff never sign in.
    password: s.isRemote || !role.canSignIn ? '' : '1234',
    role: role,
    specialization: specialization,
    consultationFee: fee,
    department: department,
    designation: designation,
    joinedOn: DateTime(now.year - 2, 3, 1),
  );

  s.users.add(
    admin ?? staff('USR-admin', 'Hospital Admin', 'admin', UserRole.admin),
  );
  if (demo) {
    s.users.addAll([
      staff(
        'USR-nur',
        'Joy Nwosu',
        'nurse',
        UserRole.nurse,
        department: 'Nursing',
        designation: 'Ward nurse',
      ),
      staff(
        'USR-acc',
        'Daniel Asante',
        'accounts',
        UserRole.accountant,
        department: 'Finance',
        designation: 'Accountant',
      ),
      staff(
        'USR-sup1',
        'Musa Ibrahim',
        '',
        UserRole.supportStaff,
        department: 'Facilities',
        designation: 'Security',
      ),
      staff(
        'USR-sup2',
        'Ada Eze',
        '',
        UserRole.supportStaff,
        department: 'Facilities',
        designation: 'Cleaner',
      ),
      staff('USR-rec', 'Grace Reception', 'reception', UserRole.receptionist),
      staff(
        'USR-doc1',
        'Dr. Amaka Obi',
        'doctor',
        UserRole.doctor,
        specialization: 'General Medicine',
        fee: 50,
      ),
      staff(
        'USR-doc2',
        'Dr. Rahul Mehta',
        'cardio',
        UserRole.doctor,
        specialization: 'Cardiology',
        fee: 80,
      ),
      staff(
        'USR-doc3',
        'Dr. Sofia Lindqvist',
        'peds',
        UserRole.doctor,
        specialization: 'Paediatrics',
        fee: 60,
      ),
      staff('USR-lab', 'Kwame Mensah', 'lab', UserRole.labTechnician),
      staff('USR-pha', 'Fatima Bello', 'pharmacy', UserRole.pharmacist),
    ]);
  }

  LabTest test(
    String id,
    String name,
    String cat,
    double price, {
    String unit = '',
    String range = '',
    String sample = 'Blood',
  }) => LabTest(
    id: id,
    name: name,
    category: cat,
    price: price,
    unit: unit,
    referenceRange: range,
    sampleType: sample,
  );

  s.labTests.addAll([
    test(
      'LT-cbc',
      'Complete Blood Count (CBC)',
      'Haematology',
      15,
      range: 'See report',
    ),
    test(
      'LT-hb',
      'Haemoglobin',
      'Haematology',
      5,
      unit: 'g/dL',
      range: '12 – 17',
    ),
    test('LT-esr', 'ESR', 'Haematology', 5, unit: 'mm/hr', range: '0 – 20'),
    test(
      'LT-fbs',
      'Fasting Blood Sugar',
      'Biochemistry',
      6,
      unit: 'mg/dL',
      range: '70 – 100',
    ),
    test('LT-hba1c', 'HbA1c', 'Biochemistry', 20, unit: '%', range: '< 5.7'),
    test('LT-lipid', 'Lipid Profile', 'Biochemistry', 25, range: 'See report'),
    test(
      'LT-lft',
      'Liver Function Test',
      'Biochemistry',
      25,
      range: 'See report',
    ),
    test(
      'LT-rft',
      'Renal Function Test',
      'Biochemistry',
      22,
      range: 'See report',
    ),
    test(
      'LT-tsh',
      'TSH',
      'Endocrinology',
      18,
      unit: 'mIU/L',
      range: '0.4 – 4.0',
    ),
    test(
      'LT-mp',
      'Malaria Parasite (MP)',
      'Microbiology',
      8,
      range: 'Not seen',
    ),
    test('LT-widal', 'Widal Test', 'Serology', 10, range: '< 1:80'),
    test(
      'LT-urine',
      'Urinalysis',
      'Clinical Pathology',
      8,
      range: 'See report',
      sample: 'Urine',
    ),
    test(
      'LT-ecg',
      'ECG',
      'Cardiology',
      30,
      range: 'Normal sinus rhythm',
      sample: 'None',
    ),
    test(
      'LT-xray',
      'Chest X-Ray',
      'Radiology',
      40,
      range: 'Normal',
      sample: 'None',
    ),
  ]);

  Medicine med(
    String id,
    String name,
    String form,
    String strength,
    double price,
    int stock, {
    int reorder = 20,
    int expiryMonths = 18,
    String mfr = '',
  }) => Medicine(
    id: id,
    name: name,
    form: form,
    strength: strength,
    unitPrice: price,
    stock: stock,
    reorderLevel: reorder,
    expiryDate: DateTime(now.year, now.month + expiryMonths, 1),
    manufacturer: mfr,
  );

  s.medicines.addAll([
    med('MED-para', 'Paracetamol', 'Tablet', '500 mg', 0.10, 1000),
    med('MED-ibu', 'Ibuprofen', 'Tablet', '400 mg', 0.15, 600),
    med('MED-amox', 'Amoxicillin', 'Capsule', '500 mg', 0.40, 300),
    med('MED-azi', 'Azithromycin', 'Tablet', '500 mg', 1.20, 120),
    med(
      'MED-cipro',
      'Ciprofloxacin',
      'Tablet',
      '500 mg',
      0.60,
      15,
      reorder: 30,
    ),
    med('MED-metf', 'Metformin', 'Tablet', '500 mg', 0.12, 800),
    med('MED-amlo', 'Amlodipine', 'Tablet', '5 mg', 0.20, 400),
    med('MED-ator', 'Atorvastatin', 'Tablet', '20 mg', 0.35, 250),
    med('MED-omep', 'Omeprazole', 'Capsule', '20 mg', 0.25, 350),
    med('MED-cetz', 'Cetirizine', 'Tablet', '10 mg', 0.08, 500),
    med('MED-al', 'Artemether/Lumefantrine', 'Tablet', '20/120 mg', 0.50, 240),
    med('MED-ors', 'ORS Sachet', 'Powder', '20.5 g', 0.30, 18, reorder: 25),
    med(
      'MED-salb',
      'Salbutamol Inhaler',
      'Inhaler',
      '100 mcg',
      4.50,
      40,
      reorder: 10,
    ),
    med(
      'MED-pcsy',
      'Paracetamol Syrup',
      'Syrup',
      '120 mg/5 ml',
      1.80,
      60,
      expiryMonths: 2,
    ),
    med('MED-ctrx', 'Ceftriaxone', 'Injection', '1 g', 3.00, 80),
  ]);

  Room room(String id, String name, String type, double rate, int beds) =>
      Room(id: id, name: name, type: type, dailyRate: rate, beds: beds);
  s.rooms.addAll([
    room('RM-gwa', 'General Ward A', 'General ward', 40, 8),
    room('RM-gwb', 'General Ward B', 'General ward', 40, 8),
    room('RM-semi', 'Semi-private 201', 'Semi-private', 80, 2),
    room('RM-101', 'Private 101', 'Private', 150, 1),
    room('RM-102', 'Private 102', 'Private', 150, 1),
    room('RM-icu', 'ICU', 'ICU', 300, 4),
    room('RM-mat', 'Maternity Ward', 'Maternity', 60, 6),
  ]);
  s.theatres.addAll([
    OperationTheatre(id: 'OT-1', name: 'OT 1 (Major)', hourlyRate: 200),
    OperationTheatre(id: 'OT-2', name: 'OT 2 (Minor)', hourlyRate: 120),
  ]);

  if (!demo) return;

  Patient patient(
    String name,
    int age,
    String gender,
    String phone, {
    String blood = '',
    String allergies = '',
    int daysAgo = 30,
  }) {
    final p = Patient(
      id: s.newId('PAT'),
      mrn: 'MRN-${s._bumpLocal('mrn').toString().padLeft(5, '0')}',
      name: name,
      dateOfBirth: DateTime(now.year - age, (age % 12) + 1, (age % 27) + 1),
      gender: gender,
      phone: phone,
      bloodGroup: blood,
      allergies: allergies,
      registeredAt: now.subtract(Duration(days: daysAgo)),
    );
    s.patients.add(p);
    return p;
  }

  final john = patient(
    'John Adeyemi',
    45,
    'Male',
    '0803 111 2233',
    blood: 'O+',
    allergies: 'Penicillin',
    daysAgo: 40,
  );
  final mary = patient(
    'Mary Johnson',
    32,
    'Female',
    '0802 444 5566',
    blood: 'A+',
    daysAgo: 20,
  );
  final ali = patient(
    'Ali Hassan',
    61,
    'Male',
    '0809 777 8899',
    blood: 'B+',
    daysAgo: 10,
  );
  final chloe = patient(
    'Chloe Martin',
    6,
    'Female',
    '0805 222 3344',
    daysAgo: 5,
  );
  final peter = patient(
    'Peter Okafor',
    28,
    'Male',
    '0807 555 1212',
    daysAgo: 2,
  );

  // A completed past visit so records, results and billing have history.
  final past = now.subtract(const Duration(days: 7));
  final pastAppt = Appointment(
    id: s.newId('APT'),
    patientId: john.id,
    doctorId: 'USR-doc1',
    scheduledAt: past,
    reason: 'Fever and body aches',
    status: AppointmentStatus.completed,
    tokenNumber: 1,
  );
  final pastCon = Consultation(
    id: s.newId('CON'),
    patientId: john.id,
    doctorId: 'USR-doc1',
    appointmentId: pastAppt.id,
    startedAt: past,
    completedAt: past.add(const Duration(minutes: 25)),
    vitals: Vitals(
      temperature: '38.6',
      bloodPressure: '128/84',
      pulse: '96',
      weight: '82',
    ),
    complaints: 'Fever for 3 days, headache, body aches',
    diagnosis: 'Uncomplicated malaria',
    notes: 'Advised fluids and rest. Penicillin allergy noted.',
  );
  final mp = LabOrder(
    id: s.newId('LAB'),
    consultationId: pastCon.id,
    patientId: john.id,
    doctorId: 'USR-doc1',
    testId: 'LT-mp',
    testName: 'Malaria Parasite (MP)',
    price: 8,
    orderedAt: past,
    status: LabOrderStatus.completed,
    sampleCollectedAt: past.add(const Duration(minutes: 5)),
    completedAt: past.add(const Duration(minutes: 20)),
    result: 'P. falciparum seen (+)',
    abnormal: true,
    technicianId: 'USR-lab',
    reviewedByDoctor: true,
  );
  final pastRx = Prescription(
    id: s.newId('RX'),
    consultationId: pastCon.id,
    patientId: john.id,
    doctorId: 'USR-doc1',
    createdAt: past.add(const Duration(minutes: 22)),
    status: PrescriptionStatus.dispensed,
    dispensedAt: past.add(const Duration(minutes: 40)),
    pharmacistId: 'USR-pha',
    items: [
      PrescriptionItem(
        medicineId: 'MED-al',
        medicineName: 'Artemether/Lumefantrine 20/120 mg (Tablet)',
        dosage: '4 tablets',
        frequency: 'Twice daily',
        durationDays: 3,
        quantity: 24,
        dispensedQuantity: 24,
        unitPrice: 0.50,
        instructions: 'Take with food',
      ),
      PrescriptionItem(
        medicineId: 'MED-para',
        medicineName: 'Paracetamol 500 mg (Tablet)',
        dosage: '2 tablets',
        frequency: 'Three times daily',
        durationDays: 3,
        quantity: 18,
        dispensedQuantity: 18,
        unitPrice: 0.10,
      ),
    ],
  );
  s.appointments.add(pastAppt);
  s.consultations.add(pastCon);
  s.labOrders.add(mp);
  s.prescriptions.add(pastRx);
  s.invoices.add(
    Invoice(
      id: s.newId('INV'),
      number: 'INV-${s._bumpLocal('invoice').toString().padLeft(5, '0')}',
      patientId: john.id,
      consultationId: pastCon.id,
      createdAt: past,
      amountPaid: 71.80,
      lines: [
        InvoiceLine(
          id: s.newId('LINE'),
          department: BillingDepartment.consultation,
          description: 'Consultation – Dr. Amaka Obi',
          quantity: 1,
          unitPrice: 50,
          sourceId: pastCon.id,
        ),
        InvoiceLine(
          id: s.newId('LINE'),
          department: BillingDepartment.laboratory,
          description: 'Lab: Malaria Parasite (MP)',
          quantity: 1,
          unitPrice: 8,
          sourceId: mp.id,
        ),
        InvoiceLine(
          id: s.newId('LINE'),
          department: BillingDepartment.pharmacy,
          description: 'Artemether/Lumefantrine 20/120 mg (Tablet)',
          quantity: 24,
          unitPrice: 0.50,
          sourceId: pastRx.id,
        ),
        InvoiceLine(
          id: s.newId('LINE'),
          department: BillingDepartment.pharmacy,
          description: 'Paracetamol 500 mg (Tablet)',
          quantity: 18,
          unitPrice: 0.10,
          sourceId: pastRx.id,
        ),
      ],
    ),
  );

  // Today's clinic: two patients already waiting, two booked for later.
  s.appointments.addAll([
    Appointment(
      id: s.newId('APT'),
      patientId: mary.id,
      doctorId: 'USR-doc1',
      scheduledAt: today.add(const Duration(hours: 9)),
      reason: 'Persistent cough for 2 weeks',
      status: AppointmentStatus.checkedIn,
      tokenNumber: 1,
    ),
    Appointment(
      id: s.newId('APT'),
      patientId: ali.id,
      doctorId: 'USR-doc1',
      scheduledAt: today.add(const Duration(hours: 9, minutes: 30)),
      reason: 'Diabetes review',
      status: AppointmentStatus.checkedIn,
      tokenNumber: 2,
    ),
    Appointment(
      id: s.newId('APT'),
      patientId: ali.id,
      doctorId: 'USR-doc2',
      scheduledAt: today.add(const Duration(hours: 14)),
      reason: 'Chest tightness on exertion',
    ),
    Appointment(
      id: s.newId('APT'),
      patientId: chloe.id,
      doctorId: 'USR-doc3',
      scheduledAt: today.add(const Duration(hours: 11)),
      reason: 'Fever and rash',
    ),
  ]);
  // Two patients already hold today's tokens for Dr. Obi.
  s._counters[HospitalStore._tokenCounter('USR-doc1', today)] = 2;

  // The past visit was paid in cash.
  final pastInvoice = s.invoices.single;
  s.payments.add(
    Payment(
      id: s.newId('PMT'),
      invoiceId: pastInvoice.id,
      patientId: john.id,
      amount: pastInvoice.amountPaid,
      method: 'Cash',
      receivedAt: past.add(const Duration(minutes: 45)),
      receivedBy: 'USR-rec',
    ),
  );

  // An inpatient: admitted two days ago, appendectomy booked for tomorrow.
  final admittedAt = now.subtract(const Duration(days: 2));
  final admission = Admission(
    id: s.newId('ADM'),
    patientId: peter.id,
    doctorId: 'USR-doc1',
    admittedAt: admittedAt,
    reason: 'Acute appendicitis',
    stays: [
      RoomStay(
        roomId: 'RM-gwa',
        roomName: 'General Ward A',
        dailyRate: 40,
        from: admittedAt,
      ),
    ],
  );
  s.admissions.add(admission);
  s.invoices.add(
    Invoice(
      id: s.newId('INV'),
      number: 'INV-${s._bumpLocal('invoice').toString().padLeft(5, '0')}',
      patientId: peter.id,
      admissionId: admission.id,
      createdAt: admittedAt,
    ),
  );
  s.surgeries.add(
    Surgery(
      id: s.newId('SUR'),
      patientId: peter.id,
      admissionId: admission.id,
      surgeonId: 'USR-doc1',
      theatreId: 'OT-1',
      procedure: 'Laparoscopic appendectomy',
      scheduledAt: today.add(const Duration(days: 1, hours: 9)),
      estimatedMinutes: 90,
      anaesthetist: 'Dr. K. Boateng',
      surgeonFee: 400,
      anaesthesiaFee: 150,
    ),
  );

  // Salaries, last month's payroll (paid) and some expenses.
  const pay = {
    'USR-admin': (3000.0, 500.0, 450.0),
    'USR-rec': (900.0, 150.0, 120.0),
    'USR-doc1': (5000.0, 800.0, 900.0),
    'USR-doc2': (6000.0, 900.0, 1100.0),
    'USR-doc3': (5500.0, 800.0, 1000.0),
    'USR-lab': (1400.0, 200.0, 200.0),
    'USR-pha': (1500.0, 200.0, 220.0),
    'USR-nur': (1300.0, 250.0, 180.0),
    'USR-acc': (1600.0, 200.0, 240.0),
    'USR-sup1': (600.0, 100.0, 50.0),
    'USR-sup2': (550.0, 100.0, 45.0),
  };
  final lastMonth = DateTime(now.year, now.month - 1);
  for (final MapEntry(key: id, value: (basic, allow, deduct)) in pay.entries) {
    if (s.userById(id) == null) continue;
    s.salaries.add(
      SalaryStructure(
        staffId: id,
        basic: basic,
        allowances: allow,
        deductions: deduct,
      ),
    );
    s.payslips.add(
      Payslip(
        id: s.newId('PAY'),
        staffId: id,
        month: lastMonth,
        basic: basic,
        allowances: allow,
        deductions: deduct,
        status: PayslipStatus.paid,
        paidAt: DateTime(now.year, now.month, 1),
        paymentMethod: 'Bank transfer',
      ),
    );
  }

  Expense expense(
    int daysAgo,
    String category,
    String what,
    double amount, {
    String vendor = '',
  }) => Expense(
    id: s.newId('EXP'),
    date: today.subtract(Duration(days: daysAgo)),
    category: category,
    description: what,
    amount: amount,
    vendor: vendor,
    paymentMethod: 'Bank transfer',
    recordedBy: 'USR-acc',
  );
  s.expenses.addAll([
    expense(now.day - 1, 'Rent', 'Building rent', 4000, vendor: 'Landlord'),
    expense(3, 'Utilities', 'Electricity', 850, vendor: 'Power Co.'),
    expense(
      2,
      'Medical supplies',
      'Gloves, syringes, gauze',
      620,
      vendor: 'MedSupply Ltd',
    ),
    expense(1, 'Maintenance & repairs', 'Generator service', 300),
    expense(now.day + 5, 'Utilities', 'Electricity', 790, vendor: 'Power Co.'),
  ]);

  s.leaves.add(
    LeaveRequest(
      id: s.newId('LV'),
      staffId: 'USR-lab',
      type: LeaveType.annual,
      from: today.add(const Duration(days: 10)),
      to: today.add(const Duration(days: 14)),
      reason: 'Family visit',
      requestedAt: now.subtract(const Duration(days: 1)),
    ),
  );
}
