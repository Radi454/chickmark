import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/customer_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/lab_analysis_models.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/customer_repository.dart';
import '../../../data/repositories/flock_repository.dart';
import '../../../data/repositories/lab_analysis_repository.dart';

class LabAnalysisProvider extends ChangeNotifier {
  LabAnalysisProvider({
    CustomerRepository? customerRepository,
    FlockRepository? flockRepository,
    LabAnalysisRepository? labAnalysisRepository,
  }) : _customerRepository = customerRepository ?? CustomerRepository(),
       _flockRepository = flockRepository ?? FlockRepository(),
       _labAnalysisRepository =
           labAnalysisRepository ?? LabAnalysisRepository();

  final CustomerRepository _customerRepository;
  final FlockRepository _flockRepository;
  final LabAnalysisRepository _labAnalysisRepository;
  final Uuid _uuid = const Uuid();

  UserModel? _currentUser;
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _selectedCustomerId;
  String? _selectedFlockId;
  DateTime _selectedDate = DateTime.now();
  List<CustomerModel> _customers = [];
  List<FlockModel> _flocks = [];
  List<LabAnalysisBatch> _batches = [];

  bool get isLoading => _isLoading;
  List<CustomerModel> get customers => _customers;
  List<FlockModel> get flocks => _flocks;
  List<LabAnalysisBatch> get batches => _batches;
  String? get selectedCustomerId => _selectedCustomerId;
  String? get selectedFlockId => _selectedFlockId;
  DateTime get selectedDate => _selectedDate;
  bool get canUseAllCustomers {
    final user = _currentUser;
    return user == null || !user.isCustomer;
  }

  CustomerModel? get selectedCustomer {
    final id = _selectedCustomerId;
    if (id == null) return null;
    for (final customer in _customers) {
      if (customer.id == id) return customer;
    }
    return null;
  }

  FlockModel? get selectedFlock {
    final id = _selectedFlockId;
    if (id == null) return null;
    for (final flock in _flocks) {
      if (flock.id == id) return flock;
    }
    return null;
  }

  Future<void> init({UserModel? currentUser}) async {
    if (currentUser != null) _currentUser = currentUser;
    if (_isInitialized) {
      await reload();
      return;
    }
    _isInitialized = true;
    await reload();
  }

  Future<void> reload() async {
    _isLoading = true;
    notifyListeners();
    try {
      final allCustomers = await _customerRepository.getAllCustomers();
      _customers = _scopeCustomers(allCustomers);
      if (_selectedCustomerId == null && !canUseAllCustomers) {
        _selectedCustomerId = _customers.isEmpty ? null : _customers.first.id;
      }
      if (_selectedCustomerId != null &&
          !_customers.any((customer) => customer.id == _selectedCustomerId)) {
        _selectedCustomerId = null;
        _selectedFlockId = null;
      }
      await _reloadFlocks();
      await _reloadBatches();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setCustomer(String? customerId) async {
    _selectedCustomerId = canUseAllCustomers
        ? customerId
        : _currentUser?.customerId;
    _selectedFlockId = null;
    _isLoading = true;
    notifyListeners();
    try {
      await _reloadFlocks();
      await _reloadBatches();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setFlock(String? flockId) async {
    _selectedFlockId = flockId;
    _isLoading = true;
    notifyListeners();
    try {
      await _reloadBatches();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day);
    notifyListeners();
  }

  Future<void> saveElisa({
    required String labName,
    required String sampleType,
    DateTime? receivedDate,
    required String groupLabel,
    required String analyte,
    String kitName = '',
    String productCode = '',
    int? sampleCount,
    double? meanTiter,
    double? minTiter,
    double? maxTiter,
    double? gmtTiter,
    double? cvPct,
    int? positiveCount,
    int? negativeCount,
    double? cutoffValue,
    double? cutoffTiter,
    List<ElisaSampleInput> samples = const [],
    String? notes,
    String? reportFileName,
    String? reportFilePath,
    String? reportFileRemotePath,
  }) async {
    final context = _saveContext(labName: labName, sampleType: sampleType);
    final now = DateTime.now();
    final report = _reportForContext(
      context,
      receivedDate: receivedDate,
      title: 'ELISA $analyte',
      reportFileName: reportFileName,
      reportFilePath: reportFilePath,
      reportFileRemotePath: reportFileRemotePath,
    );
    final groupId = _uuid.v4();
    final group = LabAnalysisGroupModel(
      id: groupId,
      reportId: report.id,
      customerId: context.customerId,
      flockId: context.flockId,
      reportDate: context.reportDate,
      testType: LabTestType.elisa,
      groupLabel: groupLabel,
      sampleScope: groupLabel,
      analyte: analyte,
      method: 'ELISA',
      kitName: kitName,
      productCode: productCode,
      sampleCount: sampleCount,
      meanTiter: meanTiter,
      minTiter: minTiter,
      maxTiter: maxTiter,
      gmtTiter: gmtTiter,
      cvPct: cvPct,
      positiveCount: positiveCount,
      negativeCount: negativeCount,
      positivePct: _percent(positiveCount, sampleCount),
      cutoffValue: cutoffValue,
      cutoffTiter: cutoffTiter,
      notes: notes,
      sortOrder: _nextSortOrder(report.id),
      createdAt: now,
      updatedAt: now,
    );
    final rows = <LabAnalysisRowModel>[
      for (var i = 0; i < samples.length; i++)
        LabAnalysisRowModel(
          id: _uuid.v4(),
          groupId: groupId,
          reportId: report.id,
          customerId: context.customerId,
          flockId: context.flockId,
          reportDate: context.reportDate,
          testType: LabTestType.elisa,
          rowLabel: samples[i].sampleNo,
          result: samples[i].result,
          resultCategory: samples[i].result,
          odValue: samples[i].od,
          spRatio: samples[i].spRatio,
          titer: samples[i].titer,
          titerGroup: samples[i].titerGroup,
          sortOrder: i,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    await _labAnalysisRepository.saveBatch(
      report: report,
      group: group,
      rows: rows,
    );
    await reload();
  }

  Future<void> savePcr({
    required String labName,
    required String sampleType,
    DateTime? receivedDate,
    required String groupLabel,
    required List<PcrResultInput> results,
    String? notes,
    String? reportFileName,
    String? reportFilePath,
    String? reportFileRemotePath,
  }) async {
    final context = _saveContext(labName: labName, sampleType: sampleType);
    final now = DateTime.now();
    final report = _reportForContext(
      context,
      receivedDate: receivedDate,
      title: 'PCR $groupLabel',
      reportFileName: reportFileName,
      reportFilePath: reportFilePath,
      reportFileRemotePath: reportFileRemotePath,
    );
    final groupId = _uuid.v4();
    final group = LabAnalysisGroupModel(
      id: groupId,
      reportId: report.id,
      customerId: context.customerId,
      flockId: context.flockId,
      reportDate: context.reportDate,
      testType: LabTestType.pcr,
      groupLabel: groupLabel,
      sampleScope: groupLabel,
      method: 'PCR',
      notes: notes,
      sortOrder: _nextSortOrder(report.id),
      createdAt: now,
      updatedAt: now,
    );
    final rows = <LabAnalysisRowModel>[
      for (var i = 0; i < results.length; i++)
        LabAnalysisRowModel(
          id: _uuid.v4(),
          groupId: groupId,
          reportId: report.id,
          customerId: context.customerId,
          flockId: context.flockId,
          reportDate: context.reportDate,
          testType: LabTestType.pcr,
          rowLabel: results[i].analyte,
          analyte: results[i].analyte,
          result: results[i].result,
          resultCategory: results[i].result,
          ctValue: results[i].ctValue,
          sortOrder: i,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    await _labAnalysisRepository.saveBatch(
      report: report,
      group: group,
      rows: rows,
    );
    await reload();
  }

  Future<void> saveHi({
    required String labName,
    required String sampleType,
    DateTime? receivedDate,
    required String groupLabel,
    required String antigen,
    required int seraCount,
    required Map<int, int> distribution,
    double? gmLog2,
    double? protectiveThresholdLog2,
    String? notes,
    String? reportFileName,
    String? reportFilePath,
    String? reportFileRemotePath,
  }) async {
    final context = _saveContext(labName: labName, sampleType: sampleType);
    final now = DateTime.now();
    final report = _reportForContext(
      context,
      receivedDate: receivedDate,
      title: 'HI $antigen',
      reportFileName: reportFileName,
      reportFilePath: reportFilePath,
      reportFileRemotePath: reportFileRemotePath,
    );
    final groupId = _uuid.v4();
    final threshold =
        protectiveThresholdLog2 ??
        LabInterpretationRules.protectiveThresholdForAntigen(antigen);
    final group = LabAnalysisGroupModel(
      id: groupId,
      reportId: report.id,
      customerId: context.customerId,
      flockId: context.flockId,
      reportDate: context.reportDate,
      testType: LabTestType.hi,
      groupLabel: groupLabel,
      sampleScope: groupLabel,
      antigen: antigen,
      method: 'HI',
      sampleCount: seraCount,
      gmLog2: gmLog2,
      protectiveThresholdLog2: threshold,
      notes: notes,
      sortOrder: _nextSortOrder(report.id),
      createdAt: now,
      updatedAt: now,
    );
    final bins = distribution.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final rows = <LabAnalysisRowModel>[
      for (var i = 0; i < bins.length; i++)
        LabAnalysisRowModel(
          id: _uuid.v4(),
          groupId: groupId,
          reportId: report.id,
          customerId: context.customerId,
          flockId: context.flockId,
          reportDate: context.reportDate,
          testType: LabTestType.hi,
          rowLabel: bins[i].key >= 12 ? '>=12' : bins[i].key.toString(),
          hiLog2: bins[i].key,
          count: bins[i].value,
          sortOrder: i,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    await _labAnalysisRepository.saveBatch(
      report: report,
      group: group,
      rows: rows,
    );
    await reload();
  }

  Future<void> saveSensitivity({
    required String labName,
    required String sampleType,
    DateTime? receivedDate,
    required String groupLabel,
    required List<SensitivityInput> antibiotics,
    String? notes,
    String? reportFileName,
    String? reportFilePath,
    String? reportFileRemotePath,
  }) async {
    final context = _saveContext(labName: labName, sampleType: sampleType);
    final now = DateTime.now();
    final report = _reportForContext(
      context,
      receivedDate: receivedDate,
      title: 'Sensitivity $groupLabel',
      reportFileName: reportFileName,
      reportFilePath: reportFilePath,
      reportFileRemotePath: reportFileRemotePath,
    );
    final groupId = _uuid.v4();
    final group = LabAnalysisGroupModel(
      id: groupId,
      reportId: report.id,
      customerId: context.customerId,
      flockId: context.flockId,
      reportDate: context.reportDate,
      testType: LabTestType.sensitivity,
      groupLabel: groupLabel,
      sampleScope: groupLabel,
      method: 'Sensitivity',
      notes: notes,
      sortOrder: _nextSortOrder(report.id),
      createdAt: now,
      updatedAt: now,
    );
    final rows = <LabAnalysisRowModel>[
      for (var i = 0; i < antibiotics.length; i++)
        LabAnalysisRowModel(
          id: _uuid.v4(),
          groupId: groupId,
          reportId: report.id,
          customerId: context.customerId,
          flockId: context.flockId,
          reportDate: context.reportDate,
          testType: LabTestType.sensitivity,
          rowLabel: antibiotics[i].antibiotic,
          antibiotic: antibiotics[i].antibiotic,
          sensitivityCategory: antibiotics[i].category,
          result: antibiotics[i].category,
          resultCategory: antibiotics[i].category,
          sortOrder: i,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    await _labAnalysisRepository.saveBatch(
      report: report,
      group: group,
      rows: rows,
    );
    await reload();
  }

  Future<void> saveCulture({
    required String labName,
    required String sampleType,
    DateTime? receivedDate,
    required String groupLabel,
    required String method,
    required List<CultureResultInput> findings,
    String? notes,
    String? reportFileName,
    String? reportFilePath,
    String? reportFileRemotePath,
  }) async {
    final context = _saveContext(labName: labName, sampleType: sampleType);
    final now = DateTime.now();
    final report = _reportForContext(
      context,
      receivedDate: receivedDate,
      title: 'Bacterial Culture $groupLabel',
      reportFileName: reportFileName,
      reportFilePath: reportFilePath,
      reportFileRemotePath: reportFileRemotePath,
    );
    final groupId = _uuid.v4();
    final group = LabAnalysisGroupModel(
      id: groupId,
      reportId: report.id,
      customerId: context.customerId,
      flockId: context.flockId,
      reportDate: context.reportDate,
      testType: LabTestType.culture,
      groupLabel: groupLabel,
      sampleScope: groupLabel,
      analyte: findings.length == 1 ? findings.first.organism : method,
      method: method,
      createdAt: now,
      updatedAt: now,
      notes: notes,
      sortOrder: _nextSortOrder(report.id),
    );
    final rows = <LabAnalysisRowModel>[
      for (var i = 0; i < findings.length; i++)
        LabAnalysisRowModel(
          id: _uuid.v4(),
          groupId: groupId,
          reportId: report.id,
          customerId: context.customerId,
          flockId: context.flockId,
          reportDate: context.reportDate,
          testType: LabTestType.culture,
          rowLabel: findings[i].organism,
          analyte: findings[i].organism,
          result: findings[i].result,
          resultCategory: findings[i].result,
          sortOrder: i,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    await _labAnalysisRepository.saveBatch(
      report: report,
      group: group,
      rows: rows,
    );
    await reload();
  }

  Future<void> deleteReport(String reportId) async {
    await _labAnalysisRepository.deleteReport(reportId);
    await reload();
  }

  Future<void> _reloadFlocks() async {
    final allFlocks = _selectedCustomerId == null
        ? await _flockRepository.getAllFlocks()
        : await _flockRepository.getFlocksByCustomer(_selectedCustomerId!);
    _flocks = _scopeFlocks(allFlocks);
    if (_selectedFlockId != null &&
        !_flocks.any((flock) => flock.id == _selectedFlockId)) {
      _selectedFlockId = null;
    }
    if (_selectedFlockId == null && _flocks.length == 1) {
      _selectedFlockId = _flocks.first.id;
    }
  }

  Future<void> _reloadBatches() async {
    _batches = await _labAnalysisRepository.getBatches(
      customerId: _selectedCustomerId,
      flockId: _selectedFlockId,
    );
  }

  _SaveContext _saveContext({
    required String labName,
    required String sampleType,
  }) {
    final customerId = _selectedCustomerId;
    final flockId = _selectedFlockId;
    if (customerId == null || flockId == null) {
      throw StateError('Choose a customer and flock first');
    }
    return _SaveContext(
      customerId: customerId,
      flockId: flockId,
      reportDate: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ),
      labName: labName.trim(),
      sampleType: sampleType.trim(),
      flockAgeWeeks: selectedFlock?.currentAgeWeeks.round(),
    );
  }

  LabAnalysisReportModel _reportForContext(
    _SaveContext context, {
    DateTime? receivedDate,
    String? title,
    String? reportFileName,
    String? reportFilePath,
    String? reportFileRemotePath,
  }) {
    final existing = _matchingReport(context);
    final now = DateTime.now();
    if (existing != null) {
      return existing.copyWith(
        receivedDate: receivedDate ?? existing.receivedDate,
        flockAgeWeeks: existing.flockAgeWeeks ?? context.flockAgeWeeks,
        title: existing.title ?? title,
        reportFileName: reportFileName ?? existing.reportFileName,
        reportFilePath: reportFilePath ?? existing.reportFilePath,
        reportFileRemotePath:
            reportFileRemotePath ?? existing.reportFileRemotePath,
        updatedAt: now,
      );
    }
    return LabAnalysisReportModel(
      id: _uuid.v4(),
      customerId: context.customerId,
      flockId: context.flockId,
      reportDate: context.reportDate,
      receivedDate: receivedDate,
      labName: context.labName,
      sampleType: context.sampleType,
      flockAgeWeeks: context.flockAgeWeeks,
      title: title,
      reportFileName: reportFileName,
      reportFilePath: reportFilePath,
      reportFileRemotePath: reportFileRemotePath,
      createdAt: now,
      updatedAt: now,
    );
  }

  LabAnalysisReportModel? _matchingReport(_SaveContext context) {
    for (final batch in _batches) {
      final report = batch.report;
      if (report.customerId == context.customerId &&
          report.flockId == context.flockId &&
          _sameDay(report.reportDate, context.reportDate) &&
          report.labName == context.labName &&
          report.sampleType == context.sampleType) {
        return report;
      }
    }
    return null;
  }

  int _nextSortOrder(String reportId) {
    for (final batch in _batches) {
      if (batch.report.id == reportId) return batch.groups.length;
    }
    return 0;
  }

  double? _percent(int? value, int? total) {
    if (value == null || total == null || total == 0) return null;
    return value * 100 / total;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<CustomerModel> _scopeCustomers(List<CustomerModel> customers) {
    final user = _currentUser;
    if (user == null || !user.isCustomer) return customers;
    final customerId = user.customerId;
    if (customerId == null || customerId.isEmpty) return [];
    return customers.where((customer) => customer.id == customerId).toList();
  }

  List<FlockModel> _scopeFlocks(List<FlockModel> flocks) {
    final user = _currentUser;
    if (user == null || !user.isCustomer) return flocks;
    final customerId = user.customerId;
    if (customerId == null || customerId.isEmpty) return [];
    return flocks.where((flock) => flock.customerId == customerId).toList();
  }
}

class ElisaSampleInput {
  final String sampleNo;
  final double? od;
  final double? spRatio;
  final String result;
  final double? titer;
  final int? titerGroup;

  const ElisaSampleInput({
    required this.sampleNo,
    this.od,
    this.spRatio,
    required this.result,
    this.titer,
    this.titerGroup,
  });
}

class PcrResultInput {
  final String analyte;
  final String result;
  final double? ctValue;

  const PcrResultInput({
    required this.analyte,
    required this.result,
    this.ctValue,
  });
}

class SensitivityInput {
  final String antibiotic;
  final String category;

  const SensitivityInput({required this.antibiotic, required this.category});
}

class CultureResultInput {
  final String organism;
  final String result;

  const CultureResultInput({required this.organism, required this.result});
}

class _SaveContext {
  final String customerId;
  final String flockId;
  final DateTime reportDate;
  final String labName;
  final String sampleType;
  final int? flockAgeWeeks;

  const _SaveContext({
    required this.customerId,
    required this.flockId,
    required this.reportDate,
    required this.labName,
    required this.sampleType,
    this.flockAgeWeeks,
  });
}
