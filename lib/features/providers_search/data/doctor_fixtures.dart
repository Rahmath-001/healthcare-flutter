import '../domain/doctor.dart';

/// Sample catalogue used until the API exists.
///
/// Kept in one place so every screen reads the same doctors, and so swapping in
/// the real repository is a single provider override rather than a hunt through
/// widget files.
abstract final class DoctorFixtures {
  static const specialties = <Specialty>[
    Specialty(code: 'GEN', name: 'General Physician'),
    Specialty(code: 'CARD', name: 'Cardiology'),
    Specialty(code: 'DERM', name: 'Dermatology'),
    Specialty(code: 'PED', name: 'Paediatrics'),
    Specialty(code: 'ORTH', name: 'Orthopaedics'),
    Specialty(code: 'GYN', name: 'Gynaecology'),
    Specialty(code: 'PSY', name: 'Psychiatry'),
    Specialty(code: 'ENT', name: 'ENT'),
  ];

  static const cities = <String>[
    'Bengaluru',
    'Hyderabad',
    'Chennai',
    'Mumbai',
    'Delhi',
  ];

  static const _apollo = Hospital(
    id: 'h1',
    name: 'Apollo Hospital',
    city: 'Bengaluru',
    address: 'Bannerghatta Road',
  );
  static const _fortis = Hospital(
    id: 'h2',
    name: 'Fortis Hospital',
    city: 'Bengaluru',
    address: 'Cunningham Road',
  );
  static const _kims = Hospital(
    id: 'h3',
    name: 'KIMS Hospital',
    city: 'Hyderabad',
    address: 'Minister Road',
  );
  static const _manipal = Hospital(
    id: 'h4',
    name: 'Manipal Hospital',
    city: 'Chennai',
    address: 'Old Mahabalipuram Road',
  );

  static const hospitals = <Hospital>[_apollo, _fortis, _kims, _manipal];

  static const all = <Doctor>[
    Doctor(
      id: 'd1',
      name: 'Dr Ananya Sharma',
      specialties: [Specialty(code: 'CARD', name: 'Cardiology')],
      qualification: 'MBBS, MD (Cardiology)',
      registrationNumber: 'KMC-58213',
      yearsExperience: 14,
      consultationFeeInr: 800,
      videoFeeInr: 600,
      rating: 4.8,
      ratingCount: 312,
      hospital: _apollo,
      languages: ['English', 'Hindi', 'Kannada'],
      modes: [
        ConsultationMode.inPerson,
        ConsultationMode.video,
        ConsultationMode.audio,
      ],
      bio: 'Interventional cardiologist with a focus on preventive care and '
          'management of hypertension and heart failure.',
    ),
    Doctor(
      id: 'd2',
      name: 'Dr Rajesh Kumar',
      specialties: [Specialty(code: 'GEN', name: 'General Physician')],
      qualification: 'MBBS, MD (General Medicine)',
      registrationNumber: 'KMC-41902',
      yearsExperience: 9,
      consultationFeeInr: 500,
      videoFeeInr: 350,
      rating: 4.6,
      ratingCount: 528,
      hospital: _fortis,
      languages: ['English', 'Hindi', 'Tamil'],
      modes: [
        ConsultationMode.inPerson,
        ConsultationMode.video,
        ConsultationMode.audio,
      ],
      bio: 'General physician treating everyday illness, diabetes and thyroid '
          'conditions.',
    ),
    Doctor(
      id: 'd3',
      name: 'Dr Meera Iyer',
      specialties: [Specialty(code: 'DERM', name: 'Dermatology')],
      qualification: 'MBBS, MD (Dermatology)',
      registrationNumber: 'TSMC-77410',
      yearsExperience: 7,
      consultationFeeInr: 700,
      videoFeeInr: 500,
      rating: 4.9,
      ratingCount: 204,
      hospital: _kims,
      languages: ['English', 'Telugu', 'Tamil'],
      modes: [ConsultationMode.video, ConsultationMode.audio],
      bio: 'Dermatologist specialising in acne, pigmentation and hair loss.',
    ),
    Doctor(
      id: 'd4',
      name: 'Dr Vikram Nair',
      specialties: [Specialty(code: 'ORTH', name: 'Orthopaedics')],
      qualification: 'MBBS, MS (Orthopaedics)',
      registrationNumber: 'TNMC-30188',
      yearsExperience: 18,
      consultationFeeInr: 900,
      videoFeeInr: 700,
      rating: 4.5,
      ratingCount: 147,
      hospital: _manipal,
      languages: ['English', 'Malayalam', 'Tamil'],
      modes: [ConsultationMode.inPerson, ConsultationMode.video],
      bio: 'Joint replacement and sports injury specialist.',
    ),
    Doctor(
      id: 'd5',
      name: 'Dr Priya Deshpande',
      specialties: [Specialty(code: 'PED', name: 'Paediatrics')],
      qualification: 'MBBS, DCH, MD (Paediatrics)',
      registrationNumber: 'KMC-62054',
      yearsExperience: 11,
      consultationFeeInr: 600,
      videoFeeInr: 450,
      rating: 4.9,
      ratingCount: 441,
      hospital: _apollo,
      languages: ['English', 'Hindi', 'Marathi'],
      modes: [
        ConsultationMode.inPerson,
        ConsultationMode.video,
        ConsultationMode.audio,
      ],
      bio: 'Paediatrician with a focus on newborn care, vaccination schedules '
          'and childhood nutrition.',
    ),
    Doctor(
      id: 'd6',
      name: 'Dr Arjun Menon',
      specialties: [Specialty(code: 'PSY', name: 'Psychiatry')],
      qualification: 'MBBS, MD (Psychiatry)',
      registrationNumber: 'KMC-70932',
      yearsExperience: 6,
      consultationFeeInr: 1200,
      videoFeeInr: 1000,
      rating: 4.7,
      ratingCount: 89,
      hospital: _fortis,
      languages: ['English', 'Malayalam'],
      modes: [ConsultationMode.video, ConsultationMode.audio],
      bio: 'Psychiatrist working with anxiety, depression and sleep disorders.',
    ),
    Doctor(
      id: 'd7',
      name: 'Dr Sunita Rao',
      specialties: [Specialty(code: 'GYN', name: 'Gynaecology')],
      qualification: 'MBBS, MS (Obstetrics and Gynaecology)',
      registrationNumber: 'KMC-33871',
      yearsExperience: 21,
      consultationFeeInr: 850,
      videoFeeInr: 650,
      rating: 4.8,
      ratingCount: 673,
      hospital: _apollo,
      languages: ['English', 'Kannada', 'Hindi'],
      modes: [ConsultationMode.inPerson, ConsultationMode.video],
      bio: 'Obstetrician and gynaecologist with two decades of experience in '
          'high-risk pregnancy care.',
    ),
    Doctor(
      id: 'd8',
      name: 'Dr Kabir Anand',
      specialties: [Specialty(code: 'ENT', name: 'ENT')],
      qualification: 'MBBS, MS (ENT)',
      registrationNumber: 'TSMC-51226',
      yearsExperience: 8,
      consultationFeeInr: 550,
      videoFeeInr: 400,
      rating: 4.4,
      ratingCount: 118,
      hospital: _kims,
      languages: ['English', 'Hindi', 'Telugu'],
      modes: [
        ConsultationMode.inPerson,
        ConsultationMode.video,
        ConsultationMode.audio,
      ],
      bio: 'ENT surgeon treating sinus disease, hearing loss and voice '
          'disorders.',
    ),
  ];

  static Doctor byId(String id) => all.firstWhere((d) => d.id == id);
}
