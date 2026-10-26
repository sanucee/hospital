part of 'hospital_store.dart';

/// The patient portal: patients register, book and cancel their own
/// appointments online, and see their released results, prescriptions
/// and bills.
extension PortalOperations on HospitalStore {
  /// Online bookings must be at least this far ahead.
  static const minimumNotice = Duration(minutes: 30);

  /// At most this many upcoming appointments booked per patient.
  static const maxUpcoming = 3;

  // ---------------------------------------------------------------------------
  // Signing in
  // ---------------------------------------------------------------------------

  /// Local mode: a patient signs in with their MRN and date of birth.
  /// (With Firebase, patients sign in with email and password through
  /// [login], and the session arrives from the backend.)
  Future<void> portalSignIn({
    required String mrn,
    required DateTime dateOfBirth,
  }) async {
    if (isRemote) {
      throw HospitalException('Sign in with your email and password');
    }
    final p = _find(
      patients,
      (p) =>
          p.mrn.toLowerCase() == mrn.trim().toLowerCase() &&
          HospitalStore._sameDay(p.dateOfBirth, dateOfBirth),
    );
    if (p == null) {
      throw HospitalException('No patient matches that MRN and date of birth');
    }
    _currentUserId = null;
    _portalPatientId = p.id;
    _changed();
    await _logEvent('signed in to the patient portal');
  }

  Future<void> portalSignOut() async {
    if (!isRemote) await _logEvent('signed out of the patient portal');
    _portalPatientId = null;
    _changed();
    if (isRemote) await backend.signOut();
  }

  /// A new patient registers online and is signed in. With Firebase this
  /// also creates their portal account ([email] and [password]).
  Future<void> portalRegister({
    required String name,
    required DateTime dateOfBirth,
    required String gender,
    required String phone,
    String email = '',
    String password = '',
  }) async {
    if (name.trim().isEmpty) throw HospitalException('Enter your full name');
    if (phone.trim().isEmpty) {
      throw HospitalException('Enter your phone number');
    }
    if (dateOfBirth.isAfter(DateTime.now())) {
      throw HospitalException('Check your date of birth');
    }
    if (!isRemote) {
      final dup = _find(
        patients,
        (p) =>
            HospitalStore._sameDay(p.dateOfBirth, dateOfBirth) &&
            internationalPhone(p.phone) == internationalPhone(phone),
      );
      if (dup != null) {
        throw HospitalException(
          'You are already registered (${dup.mrn}). Sign in with your MRN '
          'and date of birth.',
        );
      }
      final p = await registerPatient(
        name: name.trim(),
        dateOfBirth: dateOfBirth,
        gender: gender,
        phone: phone.trim(),
        email: email.trim(),
      );
      _currentUserId = null;
      _portalPatientId = p.id;
      _notifyReception(
        'New online registration',
        '${p.name} (${p.mrn}) registered through the patient portal',
        p.id,
      );
      await _commit();
      return;
    }
    if (!email.contains('@')) throw HospitalException('Enter a valid email');
    if (password.length < 6) {
      throw HospitalException('Password must be at least 6 characters');
    }
    // The patient can't reserve a number from the shared sequence; the
    // timestamp-based number is unique without it.
    final p = Patient(
      id: newId('PAT'),
      mrn: 'MRN-W${_offlineNumber()}',
      name: name.trim(),
      dateOfBirth: dateOfBirth,
      gender: gender,
      phone: phone.trim(),
      email: email.trim(),
      registeredAt: DateTime.now(),
      portalEmail: email.trim(),
    );
    await backend.registerPortalAccount(
      email: email.trim(),
      password: password,
      patientId: p.id,
      patient: p.toJson(),
    );
  }

  // ---------------------------------------------------------------------------
  // Reception: portal accounts (Firebase mode)
  // ---------------------------------------------------------------------------

  Future<void> createPortalLogin(
    String patientId, {
    required String email,
    required String password,
  }) async {
    if (!isRemote) {
      throw HospitalException(
        'In local mode patients sign in with their MRN and date of birth',
      );
    }
    _requireFrontDesk();
    final uid = await backend.createPortalLogin(
      email: email.trim(),
      password: password,
      patientId: patientId,
    );
    patientById(patientId)!
      ..portalUid = uid
      ..portalEmail = email.trim();
    await _commit();
  }

  Future<void> revokePortalLogin(String patientId) async {
    _requireFrontDesk();
    final p = patientById(patientId)!;
    if (isRemote && p.portalUid != null) {
      await backend.revokeLogin(p.portalUid!);
    }
    p
      ..portalUid = null
      ..portalEmail = '';
    await _commit();
  }

  void _requireFrontDesk() {
    final role = currentUser?.role;
    if (role != UserRole.admin && role != UserRole.receptionist) {
      throw HospitalException('Only reception can manage portal accounts');
    }
  }

  // ---------------------------------------------------------------------------
  // The patient's own records
  // ---------------------------------------------------------------------------

  Patient _me() =>
      currentPatient ?? (throw HospitalException('Sign in to the portal'));

  List<Appointment> get myAppointments {
    final id = currentPatient?.id;
    return appointments.where((a) => a.patientId == id).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
  }

  List<Appointment> get myUpcomingAppointments {
    final now = DateTime.now();
    return myAppointments
        .where(
          (a) =>
              a.status == AppointmentStatus.scheduled &&
              a.scheduledAt.isAfter(now),
        )
        .toList()
        .reversed
        .toList();
  }

  /// Results the doctor has reviewed; others aren't released to the
  /// patient (and with Firebase aren't even sent to their device).
  List<LabOrder> get myResults {
    final id = currentPatient?.id;
    return labOrders
        .where(
          (o) =>
              o.patientId == id &&
              o.status == LabOrderStatus.completed &&
              o.reviewedByDoctor,
        )
        .toList()
      ..sort(
        (a, b) => (b.completedAt ?? b.orderedAt).compareTo(
          a.completedAt ?? a.orderedAt,
        ),
      );
  }

  List<Prescription> get myPrescriptions {
    final id = currentPatient?.id;
    return prescriptions.where((p) => p.patientId == id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<Invoice> get myInvoices {
    final id = currentPatient?.id;
    return invoices.where((i) => i.patientId == id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// For reception: appointments patients booked online today.
  List<Appointment> get onlineBookingsToday => appointments
      .where(
        (a) =>
            a.channel == BookingChannel.online &&
            HospitalStore._sameDay(a.bookedAt, DateTime.now()),
      )
      .toList();

  /// Doctors who take online bookings: active, with working hours set.
  List<StaffUser> get bookableDoctors => doctors
      .where((d) => d.active && !(scheduleFor(d.id)?.isEmpty ?? true))
      .toList();

  // ---------------------------------------------------------------------------
  // Online booking
  // ---------------------------------------------------------------------------

  Future<Appointment> portalBook({
    required String doctorId,
    required DateTime at,
    String reason = '',
  }) async {
    final me = _me();
    if (!bookableDoctors.any((d) => d.id == doctorId)) {
      throw HospitalException(
        '${userName(doctorId)} does not take online bookings. '
        'Please call ${profile.phone.isEmpty ? 'the hospital' : profile.phone}.',
      );
    }
    if (at.isBefore(DateTime.now().add(minimumNotice))) {
      throw HospitalException(
        'Online bookings must be at least '
        '${minimumNotice.inMinutes} minutes ahead',
      );
    }
    final upcoming = myUpcomingAppointments;
    if (upcoming.length >= maxUpcoming) {
      throw HospitalException(
        'You already have $maxUpcoming upcoming appointments. Cancel one '
        'or call the hospital.',
      );
    }
    if (upcoming.any(
      (a) =>
          a.doctorId == doctorId && HospitalStore._sameDay(a.scheduledAt, at),
    )) {
      throw HospitalException(
        'You already have an appointment with ${userName(doctorId)} that day',
      );
    }
    final a = await bookAppointment(
      patientId: me.id,
      doctorId: doctorId,
      scheduledAt: at,
      reason: reason.trim(),
      channel: BookingChannel.online,
      sendConfirmation: true,
    );
    _notifyReception(
      'Online booking',
      '${me.name} booked ${userName(doctorId)} for '
          '${SchedulingOperations._fmtDay(at)} '
          '${SchedulingOperations._fmtTime(at)}',
      me.id,
    );
    await _commit();
    return a;
  }

  Future<void> portalCancel(String appointmentId) async {
    final me = _me();
    final a = appointmentById(appointmentId);
    if (a == null || a.patientId != me.id) {
      throw HospitalException('Appointment not found');
    }
    if (a.status != AppointmentStatus.scheduled) {
      throw HospitalException('This appointment can no longer be cancelled');
    }
    a.status = AppointmentStatus.cancelled;
    _cancelReminders(a.id);
    _releaseSlot(a.id);
    _notifyReception(
      'Online cancellation',
      '${me.name} cancelled ${userName(a.doctorId)} on '
          '${SchedulingOperations._fmtDay(a.scheduledAt)} '
          '${SchedulingOperations._fmtTime(a.scheduledAt)}',
      me.id,
    );
    await _commit();
  }

  /// The patient keeps their contact details up to date.
  Future<void> portalUpdateContact({
    required String phone,
    required String email,
    required String address,
  }) async {
    final me = _me();
    if (phone.trim().isEmpty) throw HospitalException('Enter a phone number');
    if (email.trim().isNotEmpty && !email.contains('@')) {
      throw HospitalException('Enter a valid email');
    }
    me
      ..phone = phone.trim()
      ..email = email.trim()
      ..address = address.trim();
    await _commit();
  }

  void _notifyReception(String title, String body, String patientId) => _notify(
    title: title,
    body: body,
    role: UserRole.receptionist,
    patientId: patientId,
  );
}
