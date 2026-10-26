import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:checkin_app/db/database_helper.dart';
import 'package:checkin_app/repositories/app_state_repository.dart';
import 'package:checkin_app/repositories/attendance_repository.dart';
import 'package:checkin_app/repositories/class_repository.dart';
import 'package:checkin_app/repositories/device_binding_repository.dart';
import 'package:checkin_app/repositories/member_repository.dart';
import 'package:checkin_app/repositories/notification_log_repository.dart';
import 'package:checkin_app/server/checkin_server.dart';
import 'package:checkin_app/services/absence_scheduler.dart';
import 'package:checkin_app/services/attendance_service.dart';
import 'package:checkin_app/services/bind_attempt_throttle.dart';
import 'package:checkin_app/services/checkin_app_controller.dart';
import 'package:checkin_app/services/network_info.dart';
import 'package:checkin_app/services/notification_service.dart';
import 'package:checkin_app/services/qr_token_service.dart';
import 'package:checkin_app/services/verification_session_service.dart';
import 'package:checkin_app/ui/screens/attendance_history_screen.dart';
import 'package:checkin_app/ui/screens/audit_log_screen.dart';
import 'package:checkin_app/ui/screens/class_management_screen.dart';
import 'package:checkin_app/ui/screens/dashboard_screen.dart';
import 'package:checkin_app/ui/screens/member_management_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 데스크톱은 sqflite 가 아니라 sqflite_common_ffi 를 쓴다.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final supportDir = await getApplicationSupportDirectory();
  final dbPath = p.join(supportDir.path, 'checkin_app.db');

  runApp(CheckInApp(dbPath: dbPath));
}

class CheckInApp extends StatefulWidget {
  /// null 이면 인메모리 DB 를 쓴다 (위젯/스모크 테스트용).
  final String? dbPath;

  /// 내장 체크인 서버의 포트. 테스트는 0(임의 포트)을 넘겨 실제 8080 과 다투지 않게 한다.
  final int serverPort;

  const CheckInApp({super.key, required this.dbPath, this.serverPort = 8080});

  @override
  State<CheckInApp> createState() => _CheckInAppState();
}

class _CheckInAppState extends State<CheckInApp> {
  Database? _db;
  MemberRepository? _memberRepository;
  ClassRepository? _classRepository;
  AttendanceRepository? _attendanceRepository;
  DeviceBindingRepository? _deviceBindingRepository;
  NotificationLogRepository? _notificationLogRepository;
  CheckInAppController? _controller;
  AbsenceScheduler? _absenceScheduler;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final db = await DatabaseHelper.open(widget.dbPath ?? inMemoryDatabasePath);
    _db = db;
    final memberRepository = MemberRepository(db);
    final classRepository = ClassRepository(db);
    final attendanceRepository = AttendanceRepository(db);
    final deviceBindingRepository = DeviceBindingRepository(db);
    final notificationLogRepository = NotificationLogRepository(db);
    final attendanceService = AttendanceService(
      memberRepository: memberRepository,
      classRepository: classRepository,
      attendanceRepository: attendanceRepository,
    );
    // 서버와 컨트롤러는 반드시 같은 QrTokenService 를 공유해야 한다. 따로 만들면
    // 화면에 뜬 QR 토큰을 서버가 모르는 토큰으로 판정한다.
    final qrTokenService = QrTokenService();
    final server = CheckInServer(
      memberRepository: memberRepository,
      deviceBindingRepository: deviceBindingRepository,
      attendanceService: attendanceService,
      qrTokenService: qrTokenService,
      verificationSessionService: VerificationSessionService(),
      notificationService: NotificationService(
        memberRepository: memberRepository,
        notifier: RecordingParentNotifier(notificationLogRepository),
      ),
      bindAttemptThrottle: BindAttemptThrottle(),
    );
    final controller = CheckInAppController(
      qrTokenService: qrTokenService,
      server: server,
      networkInfo: NetworkInfo(),
      port: widget.serverPort,
    );
    _controller = controller;
    await controller.start();

    final absenceScheduler = AbsenceScheduler(
      attendanceService: attendanceService,
      appStateRepository: AppStateRepository(db),
    );
    absenceScheduler.start();
    _absenceScheduler = absenceScheduler;

    if (!mounted) return;
    setState(() {
      _memberRepository = memberRepository;
      _classRepository = classRepository;
      _attendanceRepository = attendanceRepository;
      _deviceBindingRepository = deviceBindingRepository;
      _notificationLogRepository = notificationLogRepository;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _absenceScheduler?.stop();
    final controller = _controller;
    final db = _db;
    // 서버를 내린 뒤에 DB 를 닫는다 — 처리 중인 요청이 닫힌 핸들을 만지지 않게.
    if (controller != null) {
      controller.stop().whenComplete(() {
        controller.dispose();
        db?.close();
      });
    } else {
      db?.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memberRepository = _memberRepository;
    final classRepository = _classRepository;
    final attendanceRepository = _attendanceRepository;
    final deviceBindingRepository = _deviceBindingRepository;
    final notificationLogRepository = _notificationLogRepository;
    final controller = _controller;

    if (_disposed ||
        memberRepository == null ||
        classRepository == null ||
        attendanceRepository == null ||
        deviceBindingRepository == null ||
        notificationLogRepository == null ||
        controller == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      title: 'CheckInApp',
      home: _HomeShell(
        controller: controller,
        memberRepository: memberRepository,
        classRepository: classRepository,
        attendanceRepository: attendanceRepository,
        deviceBindingRepository: deviceBindingRepository,
        notificationLogRepository: notificationLogRepository,
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  final CheckInAppController controller;
  final MemberRepository memberRepository;
  final ClassRepository classRepository;
  final AttendanceRepository attendanceRepository;
  final DeviceBindingRepository deviceBindingRepository;
  final NotificationLogRepository notificationLogRepository;

  const _HomeShell({
    required this.controller,
    required this.memberRepository,
    required this.classRepository,
    required this.attendanceRepository,
    required this.deviceBindingRepository,
    required this.notificationLogRepository,
  });

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        controller: widget.controller,
        attendanceRepository: widget.attendanceRepository,
        memberRepository: widget.memberRepository,
      ),
      MemberManagementScreen(
        memberRepository: widget.memberRepository,
        classRepository: widget.classRepository,
      ),
      ClassManagementScreen(classRepository: widget.classRepository),
      AttendanceHistoryScreen(
        memberRepository: widget.memberRepository,
        attendanceRepository: widget.attendanceRepository,
      ),
      AuditLogScreen(
        deviceBindingRepository: widget.deviceBindingRepository,
        notificationLogRepository: widget.notificationLogRepository,
        memberRepository: widget.memberRepository,
      ),
    ];

    return Scaffold(
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: '현황'),
          NavigationDestination(icon: Icon(Icons.people), label: '회원'),
          NavigationDestination(icon: Icon(Icons.class_), label: '반'),
          NavigationDestination(icon: Icon(Icons.history), label: '기록'),
          NavigationDestination(icon: Icon(Icons.fact_check), label: '점검'),
        ],
      ),
    );
  }
}
