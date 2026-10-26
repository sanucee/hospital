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

  StaffUser staff(String id, String name, String username, UserRole role,
          {String? specialization, double fee = 0}) =>
      StaffUser(
        id: id,
        name: name,
        username: username,
        // With Firebase, demo staff get logins from the Staff screen instead.
        password: s.isRemote ? '' : '1234',
        role: role,
        specialization: specialization,
        consultationFee: fee,
      );

  s.users.add(
      admin ?? staff('USR-admin', 'Hospital Admin', 'admin', UserRole.admin));
  if (demo) {
    s.users.addAll([
      staff('USR-rec', 'Grace Reception', 'reception', UserRole.receptionist),
      staff('USR-doc1', 'Dr. Amaka Obi', 'doctor', UserRole.doctor,
          specialization: 'General Medicine', fee: 50),
      staff('USR-doc2', 'Dr. Rahul Mehta', 'cardio', UserRole.doctor,
          specialization: 'Cardiology', fee: 80),
      staff('USR-doc3', 'Dr. Sofia Lindqvist', 'peds', UserRole.doctor,
          specialization: 'Paediatrics', fee: 60),
      staff('USR-lab', 'Kwame Mensah', 'lab', UserRole.labTechnician),
      staff('USR-pha', 'Fatima Bello', 'pharmacy', UserRole.pharmacist),
    ]);
  }

  LabTest test(String id, String name, String cat, double price,
          {String unit = '', String range = '', String sample = 'Blood'}) =>
      LabTest(
        id: id,
        name: name,
        category: cat,
        price: price,
        unit: unit,
        referenceRange: range,
        sampleType: sample,
      );

  s.labTests.addAll([
    test('LT-cbc', 'Complete Blood Count (CBC)', 'Haematology', 15,
        range: 'See report'),
    test('LT-hb', 'Haemoglobin', 'Haematology', 5,
        unit: 'g/dL', range: '12 – 17'),
    test('LT-esr', 'ESR', 'Haematology', 5, unit: 'mm/hr', range: '0 – 20'),
    test('LT-fbs', 'Fasting Blood Sugar', 'Biochemistry', 6,
        unit: 'mg/dL', range: '70 – 100'),
    test('LT-hba1c', 'HbA1c', 'Biochemistry', 20, unit: '%', range: '< 5.7'),
    test('LT-lipid', 'Lipid Profile', 'Biochemistry', 25, range: 'See report'),
    test('LT-lft', 'Liver Function Test', 'Biochemistry', 25,
        range: 'See report'),
    test('LT-rft', 'Renal Function Test', 'Biochemistry', 22,
        range: 'See report'),
    test('LT-tsh', 'TSH', 'Endocrinology', 18,
        unit: 'mIU/L', range: '0.4 – 4.0'),
    test('LT-mp', 'Malaria Parasite (MP)', 'Microbiology', 8,
        range: 'Not seen'),
    test('LT-widal', 'Widal Test', 'Serology', 10, range: '< 1:80'),
    test('LT-urine', 'Urinalysis', 'Clinical Pathology', 8,
        range: 'See report', sample: 'Urine'),
    test('LT-ecg', 'ECG', 'Cardiology', 30, range: 'Normal sinus rhythm',
        sample: 'None'),
    test('LT-xray', 'Chest X-Ray', 'Radiology', 40, range: 'Normal',
        sample: 'None'),
  ]);

  Medicine med(String id, String name, String form, String strength,
          double price, int stock,
          {int reorder = 20, int expiryMonths = 18, String mfr = ''}) =>
      Medicine(
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
    med('MED-cipro', 'Ciprofloxacin', 'Tablet', '500 mg', 0.60, 15,
        reorder: 30),
    med('MED-metf', 'Metformin', 'Tablet', '500 mg', 0.12, 800),
    med('MED-amlo', 'Amlodipine', 'Tablet', '5 mg', 0.20, 400),
    med('MED-ator', 'Atorvastatin', 'Tablet', '20 mg', 0.35, 250),
    med('MED-omep', 'Omeprazole', 'Capsule', '20 mg', 0.25, 350),
    med('MED-cetz', 'Cetirizine', 'Tablet', '10 mg', 0.08, 500),
    med('MED-al', 'Artemether/Lumefantrine', 'Tablet', '20/120 mg', 0.50, 240),
    med('MED-ors', 'ORS Sachet', 'Powder', '20.5 g', 0.30, 18, reorder: 25),
    med('MED-salb', 'Salbutamol Inhaler', 'Inhaler', '100 mcg', 4.50, 40,
        reorder: 10),
    med('MED-pcsy', 'Paracetamol Syrup', 'Syrup', '120 mg/5 ml', 1.80, 60,
        expiryMonths: 2),
    med('MED-ctrx', 'Ceftriaxone', 'Injection', '1 g', 3.00, 80),
  ]);

  if (!demo) return;

  Patient patient(String name, int age, String gender, String phone,
      {String blood = '', String allergies = '', int daysAgo = 30}) {
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

  final john = patient('John Adeyemi', 45, 'Male', '0803 111 2233',
      blood: 'O+', allergies: 'Penicillin', daysAgo: 40);
  final mary = patient('Mary Johnson', 32, 'Female', '0802 444 5566',
      blood: 'A+', daysAgo: 20);
  final ali = patient('Ali Hassan', 61, 'Male', '0809 777 8899',
      blood: 'B+', daysAgo: 10);
  final chloe = patient('Chloe Martin', 6, 'Female', '0805 222 3344',
      daysAgo: 5);
  patient('Peter Okafor', 28, 'Male', '0807 555 1212', daysAgo: 2);

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
        temperature: '38.6', bloodPressure: '128/84', pulse: '96', weight: '82'),
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
  s.invoices.add(Invoice(
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
          sourceId: pastCon.id),
      InvoiceLine(
          id: s.newId('LINE'),
          department: BillingDepartment.laboratory,
          description: 'Lab: Malaria Parasite (MP)',
          quantity: 1,
          unitPrice: 8,
          sourceId: mp.id),
      InvoiceLine(
          id: s.newId('LINE'),
          department: BillingDepartment.pharmacy,
          description: 'Artemether/Lumefantrine 20/120 mg (Tablet)',
          quantity: 24,
          unitPrice: 0.50,
          sourceId: pastRx.id),
      InvoiceLine(
          id: s.newId('LINE'),
          department: BillingDepartment.pharmacy,
          description: 'Paracetamol 500 mg (Tablet)',
          quantity: 18,
          unitPrice: 0.10,
          sourceId: pastRx.id),
    ],
  ));

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
}

