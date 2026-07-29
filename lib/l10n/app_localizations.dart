import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('ar')];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    return localizations ?? AppLocalizations(const Locale('en'));
  }

  bool get isArabic => locale.languageCode == 'ar';

  String translate(String value) {
    if (!isArabic || value.isEmpty) return value;
    final direct = _ar[value];
    if (direct != null) return direct;
    for (final pattern in _patterns) {
      final translated = pattern(value);
      if (translated != null) return translated;
    }
    return value;
  }
}

typedef _PatternTranslator = String? Function(String value);

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    final resolved = isSupported(locale) ? locale : const Locale('en');
    return SynchronousFuture<AppLocalizations>(AppLocalizations(resolved));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String tr(String value) => l10n.translate(value);
}

final List<_PatternTranslator> _patterns = [
  (value) {
    final match = RegExp(r'^Schema v(\d+)$').firstMatch(value);
    if (match == null) return null;
    return 'إصدار المخطط ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^(\d+) messages$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} رسائل';
  },
  (value) {
    final match = RegExp(r'^Edit (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'تعديل ${_ar[match.group(1)] ?? match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Last synced: (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'آخر مزامنة: ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Sync failed: (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'فشلت المزامنة: ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Sync complete · ↑(.+) ↓(.+)$').firstMatch(value);
    if (match == null) return null;
    return 'اكتملت المزامنة · رفع ${match.group(1)} تنزيل ${match.group(2)}';
  },
  (value) {
    final match = RegExp(r'^Could not save (.+): (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'تعذر حفظ ${_ar[match.group(1)] ?? match.group(1)}: ${match.group(2)}';
  },
  (value) {
    final match = RegExp(
      r'^Could not save lab result: (.+)$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'تعذر حفظ نتيجة المعمل: ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Target (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'المستهدف ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Limit (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'الحد ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Target: (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'المستهدف: ${match.group(1)}';
  },
  (value) {
    final match = RegExp(
      r'^All (\d+) monitored readings are within target\.$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'كل القراءات المتابعة (${match.group(1)}) ضمن المستهدف.';
  },
  (value) {
    final match = RegExp(r'^(\d+) in target$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} ضمن المستهدف';
  },
  (value) {
    final match = RegExp(
      r'^Add a flock before starting audits for (.+)\.$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'أضف قطيعًا قبل بدء الزيارات لـ ${match.group(1)}.';
  },
  (value) {
    final match = RegExp(
      r'^Register hatchery details for (.+)\.$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'سجل بيانات معمل التفريخ لـ ${match.group(1)}.';
  },
  (value) {
    final match = RegExp(
      r'^Confirm entry dates when you have records for (.+)\.$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'أكد تواريخ الإدخال عند توفر سجلات لـ ${match.group(1)}.';
  },
  (value) {
    final match = RegExp(r'^Saved (\d+) CVT readings\.$').firstMatch(value);
    if (match == null) return null;
    return 'تم حفظ ${match.group(1)} قراءة حرارة جسم الكتكوت.';
  },
  (value) {
    final match = RegExp(r'^Sync could not finish: (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'تعذر إكمال المزامنة: ${match.group(1)}';
  },
  (value) {
    final match = RegExp(
      r'^(\d+) customer setup incomplete$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'إعداد ${match.group(1)} عملاء غير مكتمل';
  },
  (value) {
    final match = RegExp(r'^(\d+) hatchery record missing$').firstMatch(value);
    if (match == null) return null;
    return 'بيانات معمل التفريخ ناقصة لـ ${match.group(1)} عميل';
  },
  (value) {
    final match = RegExp(r'^(\d+) estimated flock age$').firstMatch(value);
    if (match == null) return null;
    return 'عمر القطيع تقديري لـ ${match.group(1)} عملاء';
  },
  (value) {
    final match = RegExp(r'^(\d+) sync conflict$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} تعارضات مزامنة';
  },
  (value) {
    final match = RegExp(r'^No (.+) data yet$').firstMatch(value);
    if (match == null) return null;
    final label = match.group(1)!;
    return 'لا توجد بيانات ${_ar[label] ?? label} بعد';
  },
  (value) {
    final match = RegExp(r'^(\d+) eggs$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} بيضة';
  },
  (value) {
    final match = RegExp(r'^(\d+) records$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} سجلات';
  },
  (value) {
    final match = RegExp(r'^(\d+) record$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} سجل';
  },
  (value) {
    final match = RegExp(r'^(.+) deleted$').firstMatch(value);
    if (match == null) return null;
    return 'تم حذف ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^(.+) deleted and synchronized$').firstMatch(value);
    if (match == null) return null;
    return 'تم حذف ${match.group(1)} ومزامنته';
  },
  (value) {
    final match = RegExp(
      r'^(.+) deleted locally; cloud deletion is pending sync$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'تم حذف ${match.group(1)} محليًا؛ حذف البيانات من السحابة بانتظار المزامنة';
  },
  (value) {
    final match = RegExp(
      r'^Could not delete customer: (.+)$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'تعذر حذف العميل: ${match.group(1)}';
  },
  (value) {
    final match = RegExp(
      r'^Delete flock "(.+)"\? This cannot be undone\.$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'هل تريد حذف القطيع "${match.group(1)}"؟ لا يمكن التراجع عن ذلك.';
  },
  (value) {
    final match = RegExp(
      r'^Remove flock "(.+)"\? Existing audits will keep their saved flock reference\.$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'هل تريد إزالة القطيع "${match.group(1)}"؟ ستحتفظ الزيارات السابقة بمرجع القطيع المحفوظ.';
  },
  (value) {
    final match = RegExp(
      r'^Remove hatchery "(.+)"\? Existing audits will keep their saved hatchery reference\.$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'هل تريد إزالة معمل التفريخ "${match.group(1)}"؟ ستحتفظ الزيارات السابقة بمرجع المعمل المحفوظ.';
  },
  (value) {
    final match = RegExp(
      r'^This permanently removes "(.+)", including its flocks, hatcheries, visits, station data, Govee captures, and linked photos\. The deletion will also be synced to the cloud\. This cannot be undone\.$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'سيؤدي هذا إلى حذف "${match.group(1)}" نهائيًا، بما في ذلك القطعان ومعامل التفريخ والزيارات وبيانات المحطات وتسجيلات Govee والصور المرتبطة. ستتم مزامنة الحذف مع السحابة أيضًا، ولا يمكن التراجع عنه.';
  },
  (value) {
    final match = RegExp(r'^Sync: (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'المزامنة: ${_ar[match.group(1)] ?? match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Decrease (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'تقليل ${_ar[match.group(1)] ?? match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Increase (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'زيادة ${_ar[match.group(1)] ?? match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Photo recorded for (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'تم تسجيل صورة لـ ${_ar[match.group(1)] ?? match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Depletes (.+)$').firstMatch(value);
    if (match == null) return null;
    final weeks = RegExp(r'^(\d+(?:\.\d+)?)w$').firstMatch(match.group(1)!);
    return weeks == null
        ? 'ينتهي عند ${match.group(1)}'
        : 'ينتهي عند ${weeks.group(1)} أسبوعًا';
  },
  (value) {
    final match = RegExp(r'^(.+) · (.+) · (\d+(?:\.\d+)?)w$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} · ${match.group(2)} · ${match.group(3)} أسبوعًا';
  },
  (value) {
    final match = RegExp(
      r'^(.+)\s+·\s+(\d+(?:\.\d+)?)w\s+·\s+Entry (.+)$',
    ).firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} · ${match.group(2)} أسبوعًا · تاريخ الإدخال ${match.group(3)}';
  },
  (value) {
    final match = RegExp(r'^(.+): (.+)$').firstMatch(value);
    if (match == null) return null;
    if (match.group(1) == 'Affected' || match.group(1) == 'Upside Down') {
      final eggCount = RegExp(
        r'^(\d+) eggs \((.+)\)$',
      ).firstMatch(match.group(2)!);
      if (eggCount != null) {
        final label = match.group(1) == 'Affected'
            ? 'المتأثر'
            : 'البيض المقلوب';
        return '$label: ${eggCount.group(1)} بيضة (${eggCount.group(2)})';
      }
    }
    final label = _ar[match.group(1)];
    if (label == null) return null;
    return '$label: ${match.group(2)}';
  },
  (value) {
    final match = RegExp(r'^Telegram user (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'مستخدم تيليجرام ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Row (\d+)$').firstMatch(value);
    if (match == null) return null;
    return 'الصف ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^(\d+) rows$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} صفوف';
  },
  (value) {
    final match = RegExp(r'^(\d+) requests?$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} طلب';
  },
  (value) {
    final match = RegExp(r'^(\d+) (weeks|wks)$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} أسبوعًا';
  },
  (value) {
    final match = RegExp(r'^(\d+)w$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} أسبوع';
  },
  (value) {
    final match = RegExp(r'^(\d+) days$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} يومًا';
  },
  (value) {
    final match = RegExp(r'^(\d+) readings$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} قراءة';
  },
  (value) {
    final match = RegExp(r'^(\d+) live readings$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} قراءة مباشرة';
  },
  (value) {
    final match = RegExp(r'^(\d+) stations$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} محطات';
  },
  (value) {
    final match = RegExp(r'^(\d+)/(\d+) stations$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)}/${match.group(2)} محطة';
  },
  (value) {
    final match = RegExp(
      r'^(\d+) of (\d+) stations completed$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'اكتملت ${match.group(1)} من ${match.group(2)} محطة';
  },
  (value) {
    final match = RegExp(r'^(\d+) (flock|flocks)$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} قطيع';
  },
  (value) {
    final match = RegExp(r'^(.+) \((\d+)\)$').firstMatch(value);
    if (match == null) return null;
    final label = _ar[match.group(1)];
    if (label == null) return null;
    return '$label (${match.group(2)})';
  },
  (value) {
    final match = RegExp(r'^(\d+)m ago$').firstMatch(value);
    if (match == null) return null;
    return 'منذ ${match.group(1)} دقيقة';
  },
  (value) {
    final match = RegExp(r'^(\d+)h ago$').firstMatch(value);
    if (match == null) return null;
    return 'منذ ${match.group(1)} ساعة';
  },
  (value) {
    final match = RegExp(r'^(\d+)d ago$').firstMatch(value);
    if (match == null) return null;
    return 'منذ ${match.group(1)} يوم';
  },
  (value) {
    final match = RegExp(r'^Synced (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'تمت المزامنة ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Updated (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'آخر تحديث ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^(.+)\s+·\s+updated (.+)$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} · تم التحديث ${match.group(2)}';
  },
  (value) {
    final match = RegExp(r'^(.+) avg$').firstMatch(value);
    if (match == null) return null;
    return 'المتوسط ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^SD (.+) / CV (.+)%$').firstMatch(value);
    if (match == null) return null;
    return 'الانحراف المعياري ${match.group(1)} / معامل الاختلاف ${match.group(2)}%';
  },
  (value) {
    final match = RegExp(
      r'^Drifting on (temperature|humidity) — monitor the trend\.$',
    ).firstMatch(value);
    if (match == null) return null;
    final metric = match.group(1) == 'temperature' ? 'الحرارة' : 'الرطوبة';
    return 'يوجد انحراف في $metric — تابع الاتجاه.';
  },
  (value) {
    final match = RegExp(r'^Band (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'النطاق ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Visit (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'زيارة ${match.group(1)}';
  },
  (value) {
    final match = RegExp(
      r'^(\d{2}-\d{2}-\d{4}) to (\d{2}-\d{2}-\d{4})$',
    ).firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} إلى ${match.group(2)}';
  },
  (value) {
    final match = RegExp(r'^Day (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'اليوم ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Tray (\d+)$').firstMatch(value);
    if (match == null) return null;
    return 'الصينية ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Pool (\d+)$').firstMatch(value);
    if (match == null) return null;
    return 'العينة الإجمالية ${match.group(1)}';
  },
  (value) {
    final match = RegExp(
      r'^(House|Setter|Hatcher|Trolley|Tray|Pool) (.+)$',
    ).firstMatch(value);
    if (match == null) return null;
    return '${_ar[match.group(1)] ?? match.group(1)} ${match.group(2)}';
  },
  (value) {
    final match = RegExp(
      r'^Add a hatchery for (.+) to start recording\.$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'أضف معمل تفريخ لـ ${match.group(1)} لبدء التسجيل.';
  },
  (value) {
    final match = RegExp(
      r'^Could not (save|remove|clear) (.+): (.+)$',
    ).firstMatch(value);
    if (match == null) return null;
    final action = switch (match.group(1)) {
      'save' => 'حفظ',
      'remove' => 'حذف',
      _ => 'مسح',
    };
    final subject = _ar[match.group(2)] ?? match.group(2);
    return 'تعذر $action $subject: ${match.group(3)}';
  },
  (value) {
    final match = RegExp(r'^Saved (\d+) EST readings\.$').firstMatch(value);
    if (match == null) return null;
    return 'تم حفظ ${match.group(1)} قراءة حرارة سطح البيض.';
  },
  (value) {
    final match = RegExp(r'^(.+) Chick Weight Sheet$').firstMatch(value);
    if (match == null) return null;
    return 'سجل أوزان كتاكيت ${_ar[match.group(1)] ?? match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^(.+) Egg Weight Sheet$').firstMatch(value);
    if (match == null) return null;
    return 'سجل أوزان بيض ${_ar[match.group(1)] ?? match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^(View|Enter) Weights \((.+)\)$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1) == 'View' ? 'عرض' : 'إدخال'} الأوزان (${match.group(2)})';
  },
  (value) {
    final match = RegExp(r'^Affected: (\d+) eggs \((.+)\)$').firstMatch(value);
    if (match == null) return null;
    return 'المتأثر: ${match.group(1)} بيضة (${match.group(2)})';
  },
  (value) {
    final match = RegExp(
      r'^Upside Down: (\d+) eggs \((.+)\)$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'البيض المقلوب: ${match.group(1)} بيضة (${match.group(2)})';
  },
  (value) {
    final match = RegExp(r'^(\d+) photo\(s\) attached$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} صورة مرفقة';
  },
  (value) {
    final match = RegExp(r'^(\d+) YFBM rows entered$').firstMatch(value);
    if (match == null) return null;
    return 'تم إدخال ${match.group(1)} صف من قياسات كيس المح';
  },
  (value) {
    final match = RegExp(r'^(.+)% of egg set$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)}% من البيض المحضن';
  },
  (value) {
    final match = RegExp(r'^Total set eggs: (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'إجمالي البيض المحضن: ${match.group(1)}';
  },
  (value) {
    final match = RegExp(
      r'^This removes all saved data for (.+) in this visit\.$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'سيؤدي هذا إلى حذف كل البيانات المحفوظة لمحطة ${_ar[match.group(1)] ?? match.group(1)} في هذه الزيارة.';
  },
  (value) {
    final match = RegExp(
      r'^(\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)$',
    ).firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} ${_ar[match.group(2)]}';
  },
  (value) {
    final match = RegExp(r'^(\d+) customers$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} عملاء';
  },
  (value) {
    final match = RegExp(r'^(\d+) hatcheries$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} معامل تفريخ';
  },
  (value) {
    final match = RegExp(r'^(\d+)% data coverage$').firstMatch(value);
    if (match == null) return null;
    return 'اكتمال البيانات ${match.group(1)}%';
  },
  (value) {
    final match = RegExp(
      r'^(\d+)% photo coverage \((\d+)/(\d+)\)$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'اكتمال توثيق الصور ${match.group(1)}% (${match.group(2)}/${match.group(3)})';
  },
  (value) {
    final match = RegExp(r'^(\d+) source rows$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} صف مصدر';
  },
  (value) {
    final match = RegExp(r'^(\d+) samples$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} عينة';
  },
  (value) {
    final match = RegExp(r'^(\d+) missing measurements$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} قياسًا ناقصًا';
  },
  (value) {
    final match = RegExp(r'^(\d+) pending sync$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} بانتظار المزامنة';
  },
  (value) {
    final match = RegExp(r'^(\d+) sync failed$').firstMatch(value);
    if (match == null) return null;
    return 'فشلت مزامنة ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^(\d+) (critical|watch)$').firstMatch(value);
    if (match == null) return null;
    final label = match.group(2) == 'critical' ? 'حرج' : 'للمتابعة';
    return '${match.group(1)} $label';
  },
  (value) {
    final match = RegExp(
      r'^(\d+) stale environmental captures are shown as history and excluded from active alerts\.$',
    ).firstMatch(value);
    if (match == null) return null;
    return 'توجد ${match.group(1)} تسجيلات بيئية قديمة؛ تُعرض كسجل تاريخي ولا تدخل ضمن التنبيهات النشطة.';
  },
  (value) {
    final match = RegExp(r'^Latest capture (.+)$').firstMatch(value);
    if (match == null) return null;
    final elapsed = match.group(1)!;
    final age = RegExp(r'^(\d+) (min|h|d) ago$').firstMatch(elapsed);
    if (age == null) return 'أحدث تسجيل $elapsed';
    final unit = switch (age.group(2)) {
      'min' => 'دقيقة',
      'h' => 'ساعة',
      _ => 'يوم',
    };
    return 'أحدث تسجيل منذ ${age.group(1)} $unit';
  },
  (value) {
    final match = RegExp(r'^(\d+) environmental captures$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} تسجيلات بيئية';
  },
  (value) {
    final match = RegExp(r'^(\d+) environmental readings$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} قراءات بيئية';
  },
  (value) {
    final match = RegExp(r'^(\d+) current captures$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} تسجيلات حديثة';
  },
  (value) {
    final match = RegExp(r'^Latest vs previous: (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'الأحدث مقارنة بالسابق: ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^Due (.+)$').firstMatch(value);
    if (match == null) return null;
    return 'الاستحقاق ${match.group(1)}';
  },
  (value) {
    final match = RegExp(r'^(\d+) (min|h|d) ago$').firstMatch(value);
    if (match == null) return null;
    final unit = switch (match.group(2)) {
      'min' => 'دقيقة',
      'h' => 'ساعة',
      _ => 'يوم',
    };
    return 'منذ ${match.group(1)} $unit';
  },
  (value) {
    final match = RegExp(
      r'^(Calculation|Overall: equal-age average)\:?[ ·]*(.+)$',
    ).firstMatch(value);
    if (match == null) return null;
    final policies = match
        .group(2)!
        .split(' / ')
        .map((part) => _ar[part] ?? part)
        .join(' / ');
    return match.group(1) == 'Calculation'
        ? 'طريقة الحساب: $policies'
        : 'الإجمالي: متوسط متساوي الأوزان بين الأعمار · $policies';
  },
];

const Map<String, String> _ar = {
  'ChickMark': 'ChickMark',
  'Add customer': 'إضافة عميل',
  'Incomplete Visits': 'زيارات غير مكتملة',
  'Incomplete visit': 'زيارة غير مكتملة',
  'Please complete this visit soon.': 'يرجى إكمال هذه الزيارة قريبًا.',
  'Complete now': 'أكمل الآن',
  'Home': 'الرئيسية',
  'Dashboard': 'لوحة المتابعة',
  'Agent': 'الوكيل',
  'Agent Monitor': 'مراقبة الوكيل',
  'Administrator access is required.': 'يتطلب الوصول صلاحية المدير.',
  'Refresh': 'تحديث',
  'Pause Telegram agent': 'إيقاف وكيل تيليجرام مؤقتًا',
  'Resume Telegram agent': 'استئناف وكيل تيليجرام',
  'Telegram running': 'تيليجرام يعمل',
  'Telegram paused': 'تم إيقاف تيليجرام مؤقتًا',
  'New submissions are accepted': 'يتم استقبال الإرسالات الجديدة',
  'New submissions paused': 'تم إيقاف الإرسالات الجديدة مؤقتًا',
  'Pending Telegram access': 'طلبات وصول تيليجرام المعلقة',
  'Approve new Telegram staff before they can send hatchery data.':
      'اعتمد موظفي تيليجرام الجدد قبل أن يتمكنوا من إرسال بيانات التفريخ.',
  'Assign Telegram access': 'تعيين وصول تيليجرام',
  'Telegram users': 'مستخدمو تيليجرام',
  'Customer access': 'وصول عميل',
  'Agent admin access': 'وصول مدير الوكيل',
  'Agent admin access · All customers': 'وصول مدير الوكيل · كل العملاء',
  'The agent can read and collect data for one customer.':
      'يمكن للوكيل قراءة البيانات وجمعها لعميل واحد.',
  'The agent can read and collect data for all customers.':
      'يمكن للوكيل قراءة البيانات وجمعها لكل العملاء.',
  'Allow access': 'السماح بالوصول',
  'Change scope': 'تغيير نطاق الوصول',
  'Revoke access': 'إلغاء الوصول',
  'Unknown customer': 'عميل غير معروف',
  'Select a customer before allowing access.':
      'اختر عميلًا قبل السماح بالوصول.',
  'Admin access cannot be limited to one customer.':
      'لا يمكن تقييد وصول المدير بعميل واحد.',
  'Telegram ID': 'معرّف تيليجرام',
  'Chat ID': 'معرّف المحادثة',
  'Requested': 'وقت الطلب',
  'Unable to load agent data. Please try again.':
      'تعذر تحميل بيانات الوكيل. حاول مرة أخرى.',
  'Unable to update Telegram agent. Please try again.':
      'تعذر تحديث وكيل تيليجرام. حاول مرة أخرى.',
  'Unable to update Telegram staff access. Please try again.':
      'تعذر تحديث وصول موظف تيليجرام. حاول مرة أخرى.',
  'Unable to load this draft. Please try again.':
      'تعذر تحميل هذه المسودة. حاول مرة أخرى.',
  'Unable to approve this row. Please try again.':
      'تعذر اعتماد هذا الصف. حاول مرة أخرى.',
  'Unable to reject this row. Please try again.':
      'تعذر رفض هذا الصف. حاول مرة أخرى.',
  'Unable to save this row. Please try again.':
      'تعذر حفظ هذا الصف. حاول مرة أخرى.',
  'Unable to load conversational Pasgar data. Please try again.':
      'تعذر تحميل بيانات باسجار بالمحادثة. حاول مرة أخرى.',
  'Unable to load this Pasgar intake. Please try again.':
      'تعذر تحميل إدخال باسجار هذا. حاول مرة أخرى.',
  'Unable to save this Pasgar value. Please try again.':
      'تعذر حفظ قيمة باسجار. حاول مرة أخرى.',
  'Unable to approve this Pasgar intake. Please try again.':
      'تعذر اعتماد إدخال باسجار. حاول مرة أخرى.',
  'Unable to reject this Pasgar intake. Please try again.':
      'تعذر رفض إدخال باسجار. حاول مرة أخرى.',
  'Enter a rejection reason.': 'أدخل سبب الرفض.',
  'Conversational Pasgar': 'باسجار بالمحادثة',
  'Confirmed Pasgar review': 'مراجعة باسجار المؤكدة',
  'Select a Pasgar intake to review': 'اختر إدخال باسجار لمراجعته',
  'Conversational station intakes': 'إدخالات المحطات بالمحادثة',
  'Select an intake to review': 'اختر إدخالًا لمراجعته',
  'Conversation language': 'لغة المحادثة',
  'Date': 'التاريخ',
  'Scope': 'النطاق',
  'Confirmed final summary': 'الملخص النهائي المؤكد',
  'The confirmed summary is unavailable.': 'الملخص المؤكد غير متاح.',
  'The customer-confirmed summary is unavailable.':
      'الملخص المؤكد من العميل غير متاح.',
  'Conversation evidence': 'سجل المحادثة',
  'No messages': 'لا توجد رسائل',
  'Calculated results': 'النتائج المحسوبة',
  'Approve as new visit': 'اعتماد كزيارة جديدة',
  'Attach to visit': 'إرفاق بزيارة',
  'Attach to matching visit': 'إرفاق بزيارة مطابقة',
  'Reject Pasgar intake': 'رفض إدخال باسجار',
  'Reject intake': 'رفض الإدخال',
  'Rejection reason': 'سبب الرفض',
  'Value': 'القيمة',
  'Reflex': 'الاستجابة',
  'Feather development': 'تطور الريش',
  'Pool sample': 'عينة المجمع',
  'Arabic and English': 'العربية والإنجليزية',
  'Not available': 'غير متاح',
  'Select a submission to review': 'اختر إرسالًا لمراجعته',
  'Extracted rows': 'الصفوف المستخرجة',
  'Staff submitter': 'الموظف المرسل',
  'Source type': 'نوع المصدر',
  'Submitted': 'وقت الإرسال',
  'Original source': 'المصدر الأصلي',
  'Original Telegram source': 'مصدر تيليجرام الأصلي',
  'Questions and answers': 'الأسئلة والإجابات',
  'Admin action history': 'سجل إجراءات المدير',
  'No admin actions yet': 'لا توجد إجراءات للمدير بعد',
  'No agent submissions': 'لا توجد إرسالات للوكيل',
  'Telegram submissions will appear here for review.':
      'ستظهر إرسالات تيليجرام هنا للمراجعة.',
  'Text': 'نص',
  'Image': 'صورة',
  'PDF': 'PDF',
  'Spreadsheet': 'جدول بيانات',
  'File': 'ملف',
  'Agent event': 'حدث للوكيل',
  'Row extracted': 'تم استخراج الصف',
  'Received': 'تم الاستلام',
  'Processing': 'قيد المعالجة',
  'Waiting for staff answer': 'بانتظار رد الموظف',
  'Draft ready': 'المسودة جاهزة',
  'Needs admin review': 'تحتاج مراجعة المدير',
  'Partially approved': 'معتمدة جزئيًا',
  'Rejected': 'مرفوض',
  'Telegram submission': 'إرسال تيليجرام',
  'Unknown staff': 'موظف غير معروف',
  'Needs review': 'تحتاج مراجعة',
  'Confidence': 'الثقة',
  'Warnings': 'تنبيهات',
  'No warnings': 'لا توجد تنبيهات',
  'Extracted': 'المستخرج',
  'No hatchery selected': 'لم يتم اختيار مفرخ',
  'Unavailable locally': 'غير متاح محليًا',
  'Existing customer': 'العميل الحالي',
  'Existing flock': 'القطيع الحالي',
  'Existing hatchery': 'المفرخ الحالي',
  'Info': 'معلومة',
  'Approve': 'اعتماد',
  'Reject': 'رفض',
  'Edit row': 'تعديل الصف',
  'Reject row': 'رفض الصف',
  'Rejection reason (optional)': 'سبب الرفض (اختياري)',
  'Customer ID': 'معرّف العميل',
  'Flock ID': 'معرّف القطيع',
  'Hatchery ID': 'معرّف المفرخ',
  'Use YYYY-MM-DD for dates.': 'استخدم YYYY-MM-DD للتواريخ.',
  'Enter a valid value': 'أدخل قيمة صحيحة',
  'Row actions will be available in the approval stage.':
      'ستتوفر إجراءات الصف في مرحلة الاعتماد.',
  'Station': 'المحطة',
  'Eggs placed': 'البيض الموضوع',
  'Production date': 'تاريخ الإنتاج',
  'Placement date': 'تاريخ الوضع',
  'Transfer weight': 'وزن النقل',
  'Hatch date': 'تاريخ الفقس',
  'Healthy chicks': 'الكتاكيت السليمة',
  'Second grade': 'درجة ثانية',
  'Condemned': 'النافق أو المعدوم',
  'Total production': 'إجمالي الإنتاج',
  'Proposed flock age': 'عمر القطيع المقترح',
  'Source unavailable': 'المصدر غير متاح',
  'Waiting for answer': 'بانتظار الإجابة',
  'Loading customer…': 'جارٍ تحميل العميل…',
  'Username or email': 'اسم المستخدم أو البريد الإلكتروني',
  'Please enter your username or email':
      'يرجى إدخال اسم المستخدم أو البريد الإلكتروني',
  'Enter your email to reset your password.':
      'أدخل بريدك الإلكتروني لإعادة تعيين كلمة المرور.',
  'Customer password resets are handled by your ChickMark admin.':
      'يتولى مسؤول ChickMark إعادة تعيين كلمات مرور العملاء.',
  'Customer account': 'حساب عميل',
  'Create customer account': 'إنشاء حساب عميل',
  'This account can only read the assigned customer dashboard.':
      'يمكن لهذا الحساب عرض لوحة متابعة العميل المعيّن فقط.',
  'Display name': 'اسم العرض',
  'Username': 'اسم المستخدم',
  'Example: Ghareeb': 'مثال: Ghareeb',
  '12+ characters with upper/lowercase, number, and symbol':
      '12 حرفًا أو أكثر مع أحرف كبيرة وصغيرة ورقم ورمز',
  'Copy password': 'نسخ كلمة المرور',
  'Create account': 'إنشاء الحساب',
  'Reset customer password': 'إعادة تعيين كلمة مرور العميل',
  'New password': 'كلمة المرور الجديدة',
  'Reset password': 'إعادة تعيين كلمة المرور',
  'All customers': 'كل العملاء',
  'All flocks': 'كل القطعان',
  'Customer sectors': 'قطاعات العميل',
  'A customer can use multiple sectors. Each farm belongs to exactly one enabled sector.':
      'يمكن للعميل استخدام عدة قطاعات، وتنتمي كل مزرعة إلى قطاع مفعّل واحد فقط.',
  'Hatcheries belong to Breeder customers and are available when Breeder is enabled.':
      'ترتبط معامل التفريخ بقطاع الأمهات، وتتوفر عند تفعيل هذا القطاع.',
  'Save sectors': 'حفظ القطاعات',
  'Breeder': 'أمهات',
  'Broiler': 'تسمين',
  'Layer': 'بيّاض',
  'Structure': 'الهيكل',
  'No sectors enabled': 'لا توجد قطاعات مفعّلة',
  'Enable Breeder, Broiler, or Layer before adding farms.':
      'فعّل قطاع الأمهات أو التسمين أو البيّاض قبل إضافة المزارع.',
  'Manage sectors': 'إدارة القطاعات',
  'Farm hierarchy': 'هيكل المزارع',
  'Farm and house hierarchy': 'هيكل المزارع والعنابر',
  'No farms added': 'لم تتم إضافة مزارع',
  'Farm name': 'اسم المزرعة',
  'Sector': 'القطاع',
  'Enable a customer sector before adding a farm.':
      'فعّل قطاعًا للعميل قبل إضافة مزرعة.',
  'Add farm': 'إضافة مزرعة',
  'houses': 'عنابر',
  'No houses added': 'لم تتم إضافة عنابر',
  'House name': 'اسم العنبر',
  'bird capacity': 'طائر (السعة الاستيعابية)',
  'Breeder sector required': 'قطاع الأمهات مطلوب',
  'Hatcheries belong to Breeder customers. Enable Breeder in Structure to manage hatcheries.':
      'ترتبط معامل التفريخ بعملاء الأمهات. فعّل قطاع الأمهات من الهيكل لإدارة معامل التفريخ.',
  'Portfolio summary': 'ملخص نطاق العملاء',
  'Portfolio overview': 'نظرة عامة على نطاق العملاء',
  'Select a hatchery to view operational analysis and corrective actions.':
      'اختر معمل التفريخ لعرض التحليل التشغيلي والإجراءات التصحيحية.',
  'Select a customer and hatchery to view operational analysis and corrective actions.':
      'اختر العميل ومعمل التفريخ لعرض التحليل التشغيلي والإجراءات التصحيحية.',
  'What needs attention': 'ما يحتاج إلى تدخل',
  'Ranked by severity, persistence, freshness, and data confidence.':
      'مرتبة حسب شدة الحالة واستمرارها وحداثة البيانات ودرجة موثوقيتها.',
  'No current critical or watch findings in this operational scope.':
      'لا توجد حاليًا حالات حرجة أو بنود للمتابعة في هذا النطاق التشغيلي.',
  'View source': 'عرض المصدر',
  'New issue': 'حالة جديدة',
  'Persistent': 'مستمرة',
  'Improving': 'تتحسن',
  'Worsening': 'تتدهور',
  'Resolved': 'تم الحل',
  'Stable': 'مستقرة',
  'First comparable result': 'أول نتيجة قابلة للمقارنة',
  'Action open': 'الإجراء مفتوح',
  'Action in progress': 'الإجراء قيد التنفيذ',
  'Action resolved': 'تم إغلاق الإجراء',
  'Action reopened': 'أُعيد فتح الإجراء',
  'Create action': 'إنشاء إجراء',
  'Update action': 'تحديث الإجراء',
  'Save action': 'حفظ الإجراء',
  'In progress': 'قيد التنفيذ',
  'Reopened': 'أُعيد فتحه',
  'Set due date': 'تحديد موعد الاستحقاق',
  'Resolution notes': 'ملاحظات الإغلاق',
  'Action notes': 'ملاحظات الإجراء',
  'Raw and summary values need review':
      'تحتاج القراءات الخام والقيم الملخصة إلى مراجعة',
  'Section could not refresh': 'تعذر تحديث هذا القسم',
  'Environmental readings could not refresh.': 'تعذر تحديث القراءات البيئية.',
  'No observation date': 'لا يوجد تاريخ للقراءة',
  'at an invalid future time': 'بتاريخ مستقبلي غير صالح',
  'expanded': 'موسّع',
  'collapsed': 'مطوي',
  'Ratio of totals': 'نسبة مجموع البسط إلى مجموع المقام',
  'Sample-weighted average': 'متوسط مرجح بحجم العينة',
  'Equal-group average': 'متوسط متساوي الأوزان بين المجموعات',
  'Total': 'الإجمالي',
  'Latest recorded value': 'أحدث قيمة مسجلة',
  'Customers': 'العملاء',
  'Audits': 'الزيارات',
  'Audit': 'زيارة / تقييم',
  'Govee': 'Govee',
  'Govee Records': 'سجلات Govee',
  'BMK': 'BMK',
  'EST': 'حرارة سطح البيض',
  'CVT': 'حرارة جسم الكتكوت',
  'EPEF': 'مؤشر كفاءة الإنتاج الأوروبي',
  'RH': 'الرطوبة النسبية',
  'CV': 'معامل الاختلاف',
  'C.V': 'معامل الاختلاف',
  'HOF': 'الفقس من البيض المخصب',
  'YFBM': 'نسبة وزن كيس المح',
  'PM': 'تشريح النافق',
  'STD': 'المعيار',
  'Settings': 'الإعدادات',
  'Sign In': 'تسجيل الدخول',
  'Create Account': 'إنشاء حساب',
  'Forgot password?': 'نسيت كلمة المرور؟',
  'Cancel': 'إلغاء',
  'Save': 'حفظ',
  'Saving': 'جار الحفظ',
  'Retry': 'إعادة المحاولة',
  'Reset': 'إعادة ضبط',
  'Close': 'إغلاق',
  'Edit': 'تعديل',
  'Add': 'إضافة',
  'Use': 'استخدام',
  'Remove': 'إزالة',
  'Delete': 'حذف',
  'Back': 'رجوع',
  'Next': 'التالي',
  'Continue': 'متابعة',
  'Done': 'تم',
  'All': 'الكل',
  'Clear': 'مسح',
  'Clear all': 'مسح الكل',
  'Sign Out': 'تسجيل الخروج',
  'Account': 'الحساب',
  'Unknown': 'غير معروف',
  'No email': 'لا يوجد بريد إلكتروني',
  'Preferences': 'التفضيلات',
  'Language': 'اللغة',
  'English': 'الإنجليزية',
  'Arabic': 'العربية',
  'العربية': 'العربية',
  'Temperature Unit': 'وحدة الحرارة',
  'Pasgar Sample Size': 'حجم عينة Pasgar',
  'Weights Sample Size': 'حجم عينة الأوزان',
  'Tray Size': 'حجم الصينية',
  'Storage Days': 'أيام التخزين',
  'Sync': 'المزامنة',
  'Syncing…': 'جار المزامنة…',
  'Syncing...': 'جار المزامنة...',
  'Last sync failed': 'آخر مزامنة فشلت',
  'Not synced yet': 'لم تتم المزامنة بعد',
  'Offline — using local data': 'بدون اتصال — يتم استخدام البيانات المحلية',
  'Offline - using local data': 'بدون اتصال - يتم استخدام البيانات المحلية',
  'Connected': 'متصل',
  'Uploaded': 'المرفوع',
  'Downloaded': 'المنزل',
  'No sync yet': 'لم تتم أي مزامنة بعد',
  'Sync Now': 'زامن الآن',
  'Sync complete': 'اكتملت المزامنة',
  'App': 'التطبيق',
  'Version: 1.0.0+1': 'الإصدار: 1.0.0+1',
  'ChickMark - Hatchery Audit': 'ChickMark - زيارات معمل التفريخ',
  'Admin Tools': 'أدوات الإدارة',
  'User access': 'صلاحيات المستخدمين',
  'User Access': 'صلاحيات المستخدمين',
  'Roles, approval & customer assignments': 'الأدوار، الموافقات، وربط العملاء',
  'Activity Log': 'سجل النشاط',
  'Backup database': 'نسخ قاعدة البيانات',
  'Restore from backup': 'استعادة من نسخة احتياطية',
  'This will replace ALL current data': 'سيتم استبدال كل البيانات الحالية',
  'Replace All Data': 'استبدال كل البيانات',
  'Are you sure you want to sign out?': 'هل تريد تسجيل الخروج؟',
  'This will permanently replace all current data with the backup. This cannot be undone. Are you sure?':
      'سيتم استبدال كل البيانات الحالية بالنسخة الاحتياطية بشكل نهائي، ولا يمكن التراجع عن ذلك. هل أنت متأكد؟',
  'Open navigation': 'فتح التنقل',
  'Close navigation': 'إغلاق التنقل',
  'Offline mode available when Remember me is enabled':
      'يمكن العمل بدون اتصال عند تفعيل تذكرني',
  'An error occurred. Please try again.': 'حدث خطأ. حاول مرة أخرى.',
  'New Visit': 'زيارة جديدة',
  'New Audit': 'زيارة جديدة',
  'Hatchery Visit': 'زيارة معمل التفريخ',
  'All 5 stations in one session': 'كل المحطات الخمس في زيارة واحدة',
  'Select a customer and flock to begin. You will move through Egg, Chicks, Hatch Analysis & Egg Breakouts, Setters, and Hatchers stations with progress saved between each.':
      'اختر العميل والقطيع للبدء. ستنتقل بين محطات البيض، الكتاكيت، تحليل الفقس وفحص البيض غير الفاقس، ماكينات التحضين، وماكينات الفقس مع حفظ التقدم بين كل محطة.',
  'Start Visit': 'بدء الزيارة',
  'Complete Visit': 'إنهاء الزيارة',
  'Active visit': 'زيارة نشطة',
  'Completed visit': 'زيارة مكتملة',
  'Next Station': 'المحطة التالية',
  'Start monitoring': 'بدء المتابعة',
  'Select Customer': 'اختر العميل',
  'Select customer': 'اختر العميل',
  'Select customer first': 'اختر العميل أولًا',
  'Select hatchery': 'اختر معمل التفريخ',
  'Select flock': 'اختر القطيع',
  'Select Stations': 'اختر المحطات',
  'Next: Select Stations': 'التالي: اختيار المحطات',
  'Visit order': 'ترتيب الزيارة',
  'Filter visits': 'تصفية الزيارات',
  'Search customer, hatchery, flock, breed…':
      'ابحث بالعميل أو معمل التفريخ أو القطيع أو السلالة…',
  'Clear station?': 'مسح بيانات المحطة؟',
  'Fields and saved rows will be removed.': 'سيتم حذف الحقول والصفوف المحفوظة.',
  'Last audit': 'آخر زيارة',
  'Active flocks': 'القطعان النشطة',
  'Audits this month': 'زيارات هذا الشهر',
  'Quick Actions': 'إجراءات سريعة',
  'Recent Audits': 'آخر الزيارات',
  'No recent audits': 'لا توجد زيارات حديثة',
  'Recent audit activity will appear here.': 'ستظهر هنا آخر أنشطة الزيارات.',
  'Today\'s Focus': 'تركيز اليوم',
  'active audit': 'زيارة نشطة',
  'active audits': 'زيارات نشطة',
  'Attention': 'تنبيه',
  'Attention Needed': 'تنبيهات تحتاج مراجعة',
  'All clear': 'كل شيء تمام',
  'item to check': 'بند يحتاج مراجعة',
  'items to check': 'بنود تحتاج مراجعة',
  'Ready': 'جاهز',
  'customer setup': 'عميل جاهز',
  'customer setups': 'عملاء جاهزون',
  'Add your first customer': 'أضف أول عميل',
  'Start': 'ابدأ',
  'Open': 'فتح',
  'Review': 'مراجعة',
  'Cloud not configured': 'المزامنة السحابية غير مفعلة',
  'Sync & Offline': 'المزامنة والعمل بدون اتصال',
  'Local database ready': 'قاعدة البيانات المحلية جاهزة',
  'Syncing': 'جار المزامنة',
  'Syncing with cloud': 'جاري المزامنة مع السحابة',
  'Sync error — tap Retry': 'خطأ في المزامنة — اضغط إعادة المحاولة',
  'Offline — sync paused. Local data still available.':
      'بدون اتصال — المزامنة متوقفة. البيانات المحلية متاحة.',
  'That audit is no longer available.': 'هذه الزيارة لم تعد متاحة.',
  'Dismiss all': 'إخفاء الكل',
  'Mark all reviewed': 'تمييز الكل كمراجع',
  'No open conflicts': 'لا توجد تعارضات مفتوحة',
  'Synced from another device': 'تمت المزامنة من جهاز آخر',
  'Local edits won over cloud on these rows. Confirm or restore.':
      'التعديلات المحلية أحدث من السحابة في هذه الصفوف. راجعها أو استرجعها.',
  'These rows were edited on this device after the cloud copy. Local edits were kept. Mark reviewed once confirmed.':
      'تم تعديل هذه الصفوف على هذا الجهاز بعد نسخة السحابة. تم الاحتفاظ بالتعديلات المحلية. حددها كمراجعة بعد التأكد.',
  'No photos': 'لا توجد صور',
  'No data': 'لا توجد بيانات',
  'No readings saved': 'لا توجد قراءات محفوظة',
  'Photo preview is not available': 'معاينة الصورة غير متاحة',
  'Invalid link': 'الرابط غير صحيح',
  'Could not open link': 'تعذر فتح الرابط',
  'Source photo deleted': 'تم حذف صورة المصدر',
  'View photo': 'عرض الصورة',
  'Replace photo': 'استبدال الصورة',
  'Add photo': 'إضافة صورة',
  'Delete photo': 'حذف الصورة',
  'Source': 'المصدر',
  'Link': 'الرابط',
  'Notes': 'ملاحظات',
  'Photo': 'صورة',
  'Breed Benchmarks': 'معايير السلالات',
  'Breed BMK Admin': 'إدارة BMK للسلالات',
  'Egg Breakout BMK Admin': 'إدارة BMK لفحص البيض غير الفاقس',
  'Operational BMK Admin': 'إدارة BMK التشغيلية',
  'Egg Breakout BMK': 'BMK فحص البيض غير الفاقس',
  'Operational BMKs': 'معايير BMK التشغيلية',
  'Operational notes': 'ملاحظات تشغيلية',
  'Operational BMK': 'BMK تشغيلي',
  'BMK scope': 'نطاق BMK',
  'Global defaults': 'الإعدادات العامة',
  'Breed BMK saved': 'تم حفظ BMK السلالة',
  'Egg Breakout BMK saved': 'تم حفظ BMK فحص البيض غير الفاقس',
  'Operational BMK saved': 'تم حفظ BMK التشغيلي',
  'Customer': 'العميل',
  'Flock': 'القطيع',
  'Hatchery': 'معمل التفريخ',
  'No users found.': 'لا يوجد مستخدمون.',
  'Role': 'الدور',
  'Status': 'الحالة',
  'Belongs to customer': 'تابع للعميل',
  'Records': 'السجلات',
  'Hatch Result': 'نتائج الفقس',
  'Hatch': 'فقس',
  'Chick Quality': 'جودة الكتكوت',
  'Chick quality': 'جودة الكتاكيت',
  'House scope': 'نطاق العنابر',
  'Machine scope': 'نطاق الماكينات',
  'Tray scope': 'نطاق الصواني',
  'Setpoint (°F)': 'درجة الضبط (°F)',
  'Incubation Age (days)': 'عمر التحضين (أيام)',
  'Egg Breakout': 'فحص البيض غير الفاقس',
  'Egg Storage': 'تخزين البيض',
  'Egg Storage & Handling': 'تخزين وتداول البيض',
  'Storage temps · EST · shell · turning · 9-point':
      'حرارة التخزين · حرارة سطح البيض · القشرة · التقليب · 9 نقاط',
  'Storage checklist': 'قائمة التخزين',
  'Upside score': 'درجة البيض المقلوب',
  'Shell UV': 'فحص القشرة بالأشعة',
  'Egg Quality': 'جودة البيض',
  'Egg quality': 'جودة البيض',
  'EGG QUALITY': 'جودة البيض',
  'Cumulative': 'تراكمي',
  'Incremental': 'آخر زيارة',
  'CRITICAL — ACTION REQUIRED': 'حرج — مطلوب إجراء',
  'WATCH — REVIEW SOON': 'متابعة — راجع قريبًا',
  'WATCH — NEAR THRESHOLD': 'متابعة — قريب من الحد',
  'IN TARGET': 'ضمن المستهدف',
  'In target': 'ضمن المستهدف',
  'All recorded readings are within target.':
      'كل القراءات المسجلة ضمن المستهدف.',
  'EST Average': 'متوسط حرارة سطح البيض',
  'EST CV%': 'معامل اختلاف حرارة سطح البيض %',
  'Egg CV%': 'معامل اختلاف وزن البيض %',
  '%Egg CV': 'معامل اختلاف وزن البيض %',
  'Egg Uniformity': 'تجانس وزن البيض',
  'UV Affected': 'تأثر القشرة بالأشعة',
  'Condensation': 'تكثف',
  'CRITICAL': 'حرج',
  'WATCH': 'متابعة',
  'OK': 'جيد',
  'Pooled': 'إجمالي',
  'Storage': 'التخزين',
  'Present': 'موجود',
  'None': 'لا يوجد',
  'Storage room': 'غرفة التخزين',
  'Parameter': 'البند',
  'Actual': 'الفعلي',
  'Eggs': 'بيض',
  'Chick Weights': 'أوزان الكتاكيت',
  'Fresh Breakout': 'فحص البيض الطازج',
  'Candled Breakout': 'فحص البيض بعد التحضين',
  'Residue Breakout': 'فحص متبقيات الفقس',
  'Setter Optimizing': 'ضبط ماكينة التحضين',
  'Hatcher Optimizing': 'ضبط ماكينة الفقس',
  'House': 'العنبر',
  'Machine': 'الماكينة',
  'Trolley': 'العربة',
  'Tray': 'الصينية',
  'Sample': 'العينة',
  'Below target band — warm storage toward range.':
      'أقل من المستهدف — ارفع حرارة التخزين تدريجيًا للنطاق المناسب.',
  'Above target band — cool storage toward range.':
      'أعلى من المستهدف — اخفض حرارة التخزين تدريجيًا للنطاق المناسب.',
  'Below target — corrective action required.':
      'النتيجة أقل من المستهدف — يلزم اتخاذ إجراء تصحيحي.',
  'Past limit — corrective action required.':
      'النتيجة تجاوزت الحد — يلزم اتخاذ إجراء تصحيحي.',
  'Uneven shell temperature — check grid uniformity.':
      'تفاوت في حرارة سطح البيض — راجع تجانس قراءات الشبكة.',
  'Condensation present — wipe down & verify cooling.':
      'يوجد تكثف — جفف المكان وراجع التبريد.',
  'Below the uniformity target — review flock spread.':
      'أقل من مستهدف التجانس — راجع توزيع أوزان القطيع.',
  'Weight spread high — review grading.':
      'تفاوت الوزن مرتفع — راجع فرز وتدريج البيض.',
  'Shell contamination elevated — review nest hygiene.':
      'اتساخ القشرة مرتفع — راجع نظافة الأعشاش.',
  'Setter': 'ماكينة التحضين',
  'Hatcher': 'ماكينة الفقس',
  'Place': 'المكان',
  'Govee Environmental Readings': 'قراءات البيئة من Govee',
  'Continuous temp & RH · monitored places · 24h captures':
      'حرارة ورطوبة مستمرة · أماكن متابعة · تسجيلات 24 ساعة',
  'No saved Govee readings yet': 'لا توجد قراءات Govee محفوظة بعد',
  'No Govee captures to chart yet.': 'لا توجد تسجيلات Govee كافية للرسم بعد.',
  'Nothing to chart for this metric.': 'لا توجد بيانات كافية لهذا المؤشر.',
  'Govee device settings': 'إعدادات جهاز Govee',
  'Search customer, hatchery, place…':
      'ابحث بالعميل أو معمل التفريخ أو المكان…',
  'Record environment': 'تسجيل البيئة',
  'Room environment': 'بيئة الغرفة',
  'Inside machine': 'داخل الماكينة',
  'Start recording': 'بدء التسجيل',
  'Stop and save': 'إيقاف وحفظ',
  'Bar': 'أعمدة',
  'Line': 'خط',
  'Donut': 'دائري',
  'Temperature': 'الحرارة',
  'Relative Humidity': 'الرطوبة النسبية',
  'Logs older than 90 days cleared': 'تم حذف السجلات الأقدم من 90 يومًا',
  'No activity recorded yet': 'لا يوجد نشاط مسجل حتى الآن',
  'Clear old logs': 'مسح السجلات القديمة',
  'Add new customer': 'إضافة عميل جديد',
  'Add new hatchery': 'إضافة معمل تفريخ جديد',
  'Could not autosave. Press Save to retry.':
      'تعذر الحفظ التلقائي. اضغط حفظ لإعادة المحاولة.',
  'Remove hatchery?': 'إزالة معمل التفريخ؟',
  'Admin': 'مسؤول النظام',
  'Auditor': 'مدقق',
  'Pending': 'قيد الانتظار',
  'Approved': 'معتمد',
  'Disabled': 'معطل',
  'Customers this auditor can access': 'العملاء المتاحون لهذا المدقق',
  'No customers exist yet.': 'لا يوجد عملاء حتى الآن.',
  'Station complete.': 'اكتملت المحطة.',
  'This station has saved data but not enough core data to mark complete.':
      'تحتوي المحطة على بيانات محفوظة، لكن البيانات الأساسية غير كافية لاعتماد اكتمالها.',
  'This station has no core data to mark complete. Blank rows were cleared.':
      'لا تحتوي المحطة على بيانات أساسية لاعتماد اكتمالها. تم حذف الصفوف الفارغة.',
  'Could not save station. Try again.': 'تعذر حفظ المحطة. حاول مرة أخرى.',
  'Continue without completing?': 'هل تريد المتابعة دون إكمال المحطة؟',
  'Stay': 'البقاء',
  'Station not available': 'المحطة غير متاحة',
  'View final results': 'عرض النتائج النهائية',
  'Clear station': 'مسح بيانات المحطة',
  'Could not clear station. Try again.':
      'تعذر مسح بيانات المحطة. حاول مرة أخرى.',
  'Station cleared.': 'تم مسح بيانات المحطة.',
  'Station cleared': 'تم مسح بيانات المحطة',
  'Govee readings': 'قراءات Govee',
  'Station saved without completing the visit.':
      'تم حفظ المحطة دون إنهاء الزيارة.',
  'Station saved.': 'تم حفظ المحطة.',
  'Saved': 'محفوظ',
  'Remove station': 'إزالة المحطة',
  'Tap to add': 'اضغط للإضافة',
  'All visits loaded': 'تم تحميل كل الزيارات',
  'Delete visit?': 'حذف الزيارة؟',
  'This permanently removes the visit, all its station data, and linked photos. This cannot be undone.':
      'سيؤدي هذا إلى حذف الزيارة نهائيًا بكل بيانات محطاتها وصورها المرتبطة. لا يمكن التراجع عن ذلك.',
  'Visit removed': 'تم حذف الزيارة',
  'Add house sample': 'إضافة عينة عنبر',
  'Remove active house sample': 'إزالة عينة العنبر الحالية',
  'Add machine sample': 'إضافة عينة ماكينة',
  'Remove active machine sample': 'إزالة عينة الماكينة الحالية',
  'Add House scope': 'إضافة نطاق عنبر',
  'Add Machine scope': 'إضافة نطاق ماكينة',
  'Add Trolley scope': 'إضافة نطاق عربة',
  'Add Tray scope': 'إضافة نطاق صينية',
  'Add Incubation age scope': 'إضافة نطاق عمر التحضين',
  'A House scope with this identity already exists.':
      'يوجد بالفعل نطاق عنبر بهذه الهوية.',
  'A Machine scope with this identity already exists.':
      'يوجد بالفعل نطاق ماكينة بهذه الهوية.',
  'A Trolley scope with this identity already exists.':
      'يوجد بالفعل نطاق عربة بهذه الهوية.',
  'A Tray scope with this identity already exists.':
      'يوجد بالفعل نطاق صينية بهذه الهوية.',
  'An incubation age scope with this identity already exists.':
      'يوجد بالفعل نطاق عمر تحضين بهذه الهوية.',
  'Incubation age must be a whole number from 1 to 18.':
      'يجب أن يكون عمر التحضين عددًا صحيحًا من 1 إلى 18.',
  'Incubation hours must be a whole number from 0 to 23.':
      'يجب أن تكون ساعات التحضين عددًا صحيحًا من 0 إلى 23.',
  'Remove scope?': 'إزالة النطاق؟',
  'This scope contains entered results. Removing it will permanently discard those results.':
      'يحتوي هذا النطاق على نتائج مُدخلة. ستؤدي إزالته إلى حذف هذه النتائج نهائيًا.',
  'Audit station': 'محطة الزيارة',
  'Enter Weights': 'إدخال الأوزان',
  'Chick Weights & Uniformity': 'أوزان الكتاكيت وتجانسها',
  'Quality Storage Days': 'أيام تخزين عينة الجودة',
  'Assessment Notes': 'ملاحظات التقييم',
  'Delete tray': 'حذف الصينية',
  'Total Eggs': 'إجمالي البيض',
  'Readings': 'القراءات',
  'Capture readings': 'تسجيل القراءات',
  'Add UV Tray': 'إضافة صينية للفحص بالأشعة فوق البنفسجية',
  'UV Summary': 'ملخص فحص الأشعة فوق البنفسجية',
  'Add Tray': 'إضافة صينية',
  'Breakout Type': 'نوع فحص البيض',
  'Benchmark / limit': 'المعيار / الحد',
  'Pool': 'إجمالي العينات',
  'Add tray sample': 'إضافة عينة صينية',
  'Remove active tray sample': 'إزالة عينة الصينية الحالية',
  'Photos': 'الصور',
  'Top': 'أعلى',
  'Mid': 'المنتصف',
  'Bottom': 'أسفل',
  'Random': 'عشوائي',
  'Add house': 'إضافة عنبر',
  'Remove active house': 'إزالة العنبر الحالي',
  'Add machine': 'إضافة ماكينة',
  'Remove active machine': 'إزالة الماكينة الحالية',
  'Add trolley': 'إضافة عربة',
  'Remove active trolley': 'إزالة العربة الحالية',
  'Chick Panting': 'لهاث الكتاكيت',
  'Meconium Assessment': 'تقييم العقي',
  'Hatcher number': 'رقم ماكينة الفقس',
  'Hatcher settings': 'إعدادات ماكينة الفقس',
  'Setpoint RH (%)': 'ضبط الرطوبة النسبية (%)',
  'Incubation Hours': 'ساعات التحضين',
  'CO2 Level (ppm)': 'مستوى ثاني أكسيد الكربون (جزء بالمليون)',
  'Chick Vent Temperature': 'حرارة فتحة مجمع الكتكوت',
  'Add incubation age sample': 'إضافة عينة عمر تحضين',
  'Remove active incubation age sample': 'إزالة عينة عمر التحضين الحالية',
  'Egg Shell Temperature': 'حرارة سطح قشرة البيض',
  'Setter number': 'رقم ماكينة التحضين',
  'Setter type': 'نوع ماكينة التحضين',
  'Batch size': 'حجم الدفعة',
  'Batches (max 6)': 'الدفعات (بحد أقصى 6)',
  'Incubation age samples': 'عينات عمر التحضين',
  'Retake': 'إعادة الالتقاط',
  'Enter reading manually': 'إدخال القراءة يدويًا',
  'Save point': 'حفظ النقطة',
  'Capture': 'التقاط',
  'Auditing': 'تنفيذ الزيارات',
  'Auditing isn\'t available for your account':
      'تنفيذ الزيارات غير متاح لحسابك',
  'Your role has read-only access to dashboards and benchmarks.':
      'صلاحياتك تتيح عرض لوحات المتابعة والمعايير فقط.',
  'Go back': 'العودة',
  'Draft could not be autosaved. Save will retry.':
      'تعذر الحفظ التلقائي للمسودة. سيؤدي الضغط على حفظ إلى إعادة المحاولة.',
  'Saving a local draft': 'جار حفظ مسودة محلية',
  'Draft autosave is queued': 'الحفظ التلقائي للمسودة في قائمة الانتظار',
  'Local draft saved on this device': 'تم حفظ المسودة محليًا على هذا الجهاز',
  'Photo recorded': 'تم تسجيل الصورة',
  'Clear reading and photo': 'مسح القراءة والصورة',
  'Add evidence photo': 'إضافة صورة توثيقية',
  'Evidence photo': 'صورة توثيقية',
  'Resume camera': 'استئناف الكاميرا',
  'Camera paused': 'الكاميرا متوقفة مؤقتًا',
  'Resume when you are ready.': 'استأنف عندما تكون مستعدًا.',
  'Camera': 'الكاميرا',
  'Gallery': 'معرض الصور',
  'Edit photo': 'تعديل الصورة',
  'Remove active sample': 'إزالة العينة الحالية',
  'Add sample': 'إضافة عينة',
  'Understanding Sample Mode': 'فهم وضع العينات',
  'Single Sample': 'عينة واحدة',
  'One sample representing the overall condition.':
      'عينة واحدة تمثل الحالة العامة.',
  'Compare Samples': 'مقارنة العينات',
  'Add separate samples and compare their results side by side.\n':
      'أضف عينات مستقلة وقارن نتائجها جنبًا إلى جنب.\n',
  'Add separate samples and compare their results side by side.\nEach sample is entered and saved separately.':
      'أضف عينات مستقلة وقارن نتائجها جنبًا إلى جنب.\nتُدخل كل عينة وتُحفظ بصورة مستقلة.',
  'Each level represents a deeper level of detail.':
      'يمثل كل مستوى درجة أدق من التفاصيل.',
  'Help: Sample Mode explanation': 'مساعدة: شرح وضع العينات',
  'Visit actions': 'إجراءات الزيارة',
  'Resume visit': 'استئناف الزيارة',
  'Delete visit': 'حذف الزيارة',
  'Station actions': 'إجراءات المحطة',
  'Open / Re-Audit': 'فتح / إعادة التقييم',
  'Apply': 'تطبيق',
  'Filter Visits': 'تصفية الزيارات',
  'Total Egg Set': 'إجمالي البيض المحضن',
  'Decrease count': 'تقليل العدد',
  'Count': 'العدد',
  'Increase count': 'زيادة العدد',
  'CVT Grid': 'شبكة حرارة جسم الكتكوت',
  'Number of chicks sampled': 'عدد الكتاكيت في العينة',
  'PASGAR Score': 'تقييم PASGAR',
  'Sample Metadata': 'بيانات العينة',
  'Sample Size': 'حجم العينة',
  'Collection Point': 'نقطة جمع العينة',
  'Lesion Observations': 'ملاحظات الآفات',
  'Severity': 'درجة الشدة',
  'Others': 'أخرى',
  'Add other': 'إضافة آفة أخرى',
  'Lesion name': 'اسم الآفة',
  'Remove other lesion': 'إزالة الآفة الإضافية',
  'PM Necropsy Photos': 'صور تشريح النافق',
  'PM Summary': 'ملخص تشريح النافق',
  'Auto-Suggested Cause': 'السبب المقترح تلقائيًا',
  'Manual Suspected Cause (override)':
      'السبب المشتبه به يدويًا (يتجاوز المقترح)',
  'Enter YFBM Entries': 'إدخال قياسات كيس المح',
  'YFBM Entries': 'قياسات كيس المح',
  'Add row': 'إضافة صف',
  'Delete row': 'حذف الصف',
  'Send': 'إرسال',
  'Email': 'البريد الإلكتروني',
  'Password': 'كلمة المرور',
  'Remember me': 'تذكرني',
  "don't have an account?": 'ليس لديك حساب؟',
  'Enter your email to receive a password reset link.':
      'أدخل بريدك الإلكتروني لتصلك وصلة إعادة تعيين كلمة المرور.',
  'Send Reset Link': 'إرسال وصلة إعادة التعيين',
  'Use different account': 'استخدام حساب آخر',
  'Awaiting Approval': 'الحساب بانتظار الموافقة',
  'Your account is currently pending approval from an administrator. You will receive an email once your account has been approved.':
      'حسابك بانتظار اعتماد مسؤول النظام. ستصلك رسالة بريد إلكتروني بعد اعتماد الحساب.',
  'Enter your email address to receive a password reset link:':
      'أدخل بريدك الإلكتروني لتصلك وصلة إعادة تعيين كلمة المرور:',
  'Full Name': 'الاسم الكامل',
  'Name': 'الاسم',
  'Confirm Password': 'تأكيد كلمة المرور',
  'Your account will be ready to use after it is created.':
      'سيصبح حسابك جاهزًا للاستخدام فور إنشائه.',
  'Back to Login': 'العودة لتسجيل الدخول',
  'Edit audit': 'تعديل الزيارة',
  'Audit Sections': 'أقسام الزيارة',
  'No summary values have been recorded for this audit yet.':
      'لم تُسجل قيم ملخصة لهذه الزيارة حتى الآن.',
  'No values recorded yet': 'لم تُسجل قيم بعد',
  'Entry date is estimated': 'تاريخ الإدخال تقديري',
  'Edit customer': 'تعديل العميل',
  'Delete customer': 'حذف العميل',
  'Edit flock': 'تعديل القطيع',
  'Delete flock': 'حذف القطيع',
  'Delete customer?': 'حذف العميل؟',
  'Delete Flock': 'حذف القطيع',
  'Station Scorecards': 'بطاقات تقييم المحطات',
  'Findings': 'النتائج والملاحظات',
  'PM Necropsy': 'تشريح النافق',
  'Hatch Budget': 'حصيلة الفقس',
  'Govee Readings': 'قراءات Govee',
  'Station Details': 'تفاصيل المحطة',
  'Search customers...': 'ابحث عن عميل...',
  'One or more flocks need entry date confirmation':
      'يوجد قطيع واحد أو أكثر يحتاج إلى تأكيد تاريخ الإدخال',
  'Full Name *': 'الاسم الكامل *',
  'Enter customer name': 'أدخل اسم العميل',
  'Location': 'الموقع',
  'Enter location': 'أدخل الموقع',
  'Phone': 'الهاتف',
  'Enter phone number': 'أدخل رقم الهاتف',
  'Enter email address': 'أدخل البريد الإلكتروني',
  'Update details, availability, and depletion rules from one place.':
      'حدّث البيانات وحالة الإتاحة وقواعد انتهاء الدورة من مكان واحد.',
  'Flock ID *': 'معرّف القطيع *',
  'Enter flock ID': 'أدخل معرّف القطيع',
  'Breed': 'السلالة',
  'Current age weeks *': 'العمر الحالي بالأسابيع *',
  'Enter current flock age': 'أدخل العمر الحالي للقطيع',
  'This creates an estimated entry date.': 'سيتم حساب تاريخ إدخال تقديري.',
  'Depletion age weeks *': 'عمر انتهاء الدورة بالأسابيع *',
  'Default is 65 weeks': 'القيمة الافتراضية 65 أسبوعًا',
  'Flocks at or beyond this age are hidden from new audits.':
      'لا تظهر القطعان التي بلغت هذا العمر أو تجاوزته عند إنشاء زيارات جديدة.',
  'Active flocks are still hidden from new audits once they reach depletion age.':
      'حتى القطعان النشطة لا تظهر في الزيارات الجديدة بعد بلوغ عمر انتهاء الدورة.',
  'Entry date': 'تاريخ الإدخال',
  'Entrance date': 'تاريخ الدخول',
  'Error: No customer selected': 'خطأ: لم يتم اختيار عميل',
  'Remove flock?': 'إزالة القطيع؟',
  'Flock Management': 'إدارة القطعان',
  'Remove flock': 'إزالة القطيع',
  'Hatchery Management': 'إدارة معامل التفريخ',
  'Edit hatchery': 'تعديل معمل التفريخ',
  'Remove hatchery': 'إزالة معمل التفريخ',
  'Clear filters': 'مسح عوامل التصفية',
  'Add a customer and flock to see dashboard insights.':
      'أضف عميلًا وقطيعًا لعرض مؤشرات لوحة المتابعة.',
  'Excellent chick quality. Maintain current hatchery process.':
      'جودة الكتاكيت ممتازة. حافظ على إجراءات معمل التفريخ الحالية.',
  'Acceptable chick quality. Monitor trends and defect mix.':
      'جودة الكتاكيت مقبولة. تابع الاتجاهات وتوزيع العيوب.',
  'Below 9.0. Review incubation, hatch window, holding, and handling.':
      'أقل من 9.0. راجع التحضين ونافذة الفقس وفترة الانتظار والتداول.',
  'Captured Photos': 'الصور المسجلة',
  '9-point EST evidence': 'توثيق قياسات حرارة سطح البيض ذات 9 نقاط',
  'No age data to chart yet.': 'لا توجد بيانات عمر كافية للرسم بعد.',
  'Nothing to chart for this selection.':
      'لا توجد بيانات كافية للرسم لهذا الاختيار.',
  'Breakout': 'فحص البيض',
  'Pick at least one column to compare.':
      'اختر عمودًا واحدًا على الأقل للمقارنة.',
  'Break down by — add layers to narrow, remove to broaden':
      'قسّم حسب — أضف مستويات لتضييق النتائج أو أزلها لتوسيعها',
  'All BMK Ages': 'جميع أعمار BMK',
  'Pick BMK age': 'اختر عمر BMK',
  'by BMK age': 'حسب عمر BMK',
  'Show table': 'عرض الجدول',
  'Show chart': 'عرض الرسم البياني',
  'Compare performance across BMK ages': 'قارن الأداء عبر أعمار BMK المختلفة',
  'Overall': 'الإجمالي',
  'Overall avg': 'المتوسط العام',
  'AVG': 'المتوسط',
  'PARAM': 'المؤشر',
  'No data for this customer / flock / age yet.':
      'لا توجد بيانات لهذا العميل / القطيع / العمر حتى الآن.',
  'Example data': 'بيانات توضيحية',
  '21-Day Hatch Residue Breakout': 'فحص متبقيات الفقس عند عمر 21 يومًا',
  'Tray size: 750 eggs': 'سعة الصينية: 750 بيضة',
  ' across visits': ' عبر الزيارات',
  '  across visits': '  عبر الزيارات',
  'Hatch Analysis & Egg Breakouts': 'تحليل الفقس وفحص البيض غير الفاقس',
  'Alarm': 'إنذار',
  'Chicks': 'الكتاكيت',
  'Setters': 'ماكينات التحضين',
  'Turning Angle': 'زاوية التقليب',
  'Hatch%': 'نسبة الفقس',
  'Fert%': 'نسبة الإخصاب',
  'HOF%': 'نسبة الفقس من البيض المخصب',
  'EST Comparison': 'مقارنة حرارة سطح البيض',
  'EST (°F)': 'حرارة سطح البيض (°F)',
  'CO₂ Trend (ppm)': 'اتجاه ثاني أكسيد الكربون (جزء بالمليون)',
  'No CO₂ data': 'لا توجد بيانات لثاني أكسيد الكربون',
  'Hatchers': 'ماكينات الفقس',
  'Culled%': 'نسبة المستبعد',
  'CVT CV%': 'معامل اختلاف حرارة جسم الكتكوت %',
  'CV%': 'معامل الاختلاف %',
  'Meconium': 'العقي',
  'Trans. Day': 'يوم النقل',
  'CVT Avg (°F)': 'متوسط حرارة جسم الكتكوت (°F)',
  'Chick Panting Trend': 'اتجاه لهاث الكتاكيت',
  'No panting data': 'لا توجد بيانات لهاث',
  'Weights & uniformity • Shell UV': 'الأوزان والتجانس • فحص القشرة بالأشعة',
  'Delete capture?': 'حذف التسجيل؟',
  'Capture removed': 'تم حذف التسجيل',
  'Capture actions': 'إجراءات التسجيل',
  'Re-record': 'إعادة التسجيل',
  'Govee capture': 'تسجيل Govee',
  'Close Govee': 'إغلاق Govee',
  'Select a customer and hatchery to start recording.':
      'اختر العميل ومعمل التفريخ لبدء التسجيل.',
  'Sync diagnostics': 'تشخيص المزامنة',
  'Locked while recording. Stop and save to switch.':
      'لا يمكن التغيير أثناء التسجيل. أوقف التسجيل واحفظ أولًا.',
  'Diagnostics': 'التشخيص',
  'Govee settings': 'إعدادات Govee',
  'Disconnect': 'قطع الاتصال',
  'Read now': 'قراءة الآن',
  'Available devices': 'الأجهزة المتاحة',
  'Customer, flock, and hatchery setup looks ready.':
      'بيانات العميل والقطيع ومعمل التفريخ مكتملة.',
  'Customers are needed before flocks, hatcheries, and audits.':
      'يجب إضافة العملاء قبل القطعان ومعامل التفريخ والزيارات.',
  'Start a new audit when customer setup is ready.':
      'ابدأ زيارة جديدة بعد استكمال بيانات العميل.',
  'ChickMark logo': 'شعار ChickMark',
  'Open Govee': 'فتح Govee',
  'Govee recording in progress': 'تسجيل Govee قيد التشغيل',
  'Aviagen Hatchery Tips': 'إرشادات Aviagen لمعامل التفريخ',
  'H&N International Chick Quality Guide':
      'دليل H&N International لجودة الكتاكيت',
  'Cobb Hatchery Guide': 'دليل Cobb لمعامل التفريخ',
  'Petersime Chick Quality Control': 'ضبط جودة الكتاكيت من Petersime',
  'CABI chick defects research': 'أبحاث CABI عن عيوب الكتاكيت',
  'ResearchGate chick defects research': 'أبحاث ResearchGate عن عيوب الكتاكيت',
  'Aviagen Ross Pocket Guide': 'دليل Aviagen Ross المختصر',
  'Lohmann Chick Quality': 'جودة الكتاكيت من Lohmann',
  'Aviagen Investigating Hatchery Practice':
      'دليل Aviagen لفحص ممارسات معمل التفريخ',
  'Pas Reform red hocks': 'احمرار مفصل العرقوب وفق Pas Reform',
  'Abnormalities in hatching chicks': 'تشوهات الكتاكيت عند الفقس',
  'Belly not fully closed, wet or inflamed navel':
      'بطن غير مغلق بالكامل أو سرة رطبة أو ملتهبة',
  'Dry yolk/string attached to navel': 'بقايا مح جافة أو خيط متصل بالسرة',
  'Dark dry scab on navel': 'قشرة داكنة وجافة على السرة',
  'Enlarged abdomen with excess yolk': 'تضخم البطن مع زيادة بقايا المح',
  'Sticky glued down feathers': 'ريش لزج وملتصق بالجسم',
  'Dry dark chick with rough legs/hocks':
      'كتكوت جاف داكن مع خشونة الأرجل أو العرقوب',
  'Legs spread sideways, unable to stand properly':
      'أرجل مفلطحة جانبيًا مع صعوبة في الوقوف',
  'Toes curled inward': 'أصابع ملتفة إلى الداخل',
  'Bent or twisted legs/feet': 'أرجل أو أقدام منحنية أو ملتوية',
  'Red swollen hock joints': 'احمرار وتورم مفاصل العرقوب',
  'Upper and lower beak misaligned': 'عدم تطابق الجزأين العلوي والسفلي للمنقار',
  'Eye absent or malformed': 'عين مفقودة أو مشوهة',
  'Skull not closed with exposed brain tissue':
      'عدم انغلاق الجمجمة مع انكشاف نسيج المخ',
  'Head tilted upward, neurological posture':
      'ميل الرأس لأعلى في وضع عصبي غير طبيعي',
  'Twisted neck/spine': 'التواء الرقبة أو العمود الفقري',
  'Chick significantly undersized': 'كتكوت أصغر من الحجم الطبيعي بوضوح',
  'Hair-like sparse down instead of fluffy feathers':
      'زغب خفيف متناثر يشبه الشعر بدلًا من الريش المنتفش',
  'Low Pasgar Score': 'انخفاض تقييم Pasgar',
  'CVT Out of Range': 'حرارة جسم الكتكوت خارج النطاق',
  'Shell Temperature Alert': 'تنبيه حرارة سطح القشرة',
  'Setter ID': 'معرّف ماكينة التحضين',
  'Hatcher ID': 'معرّف ماكينة الفقس',
  'BMK Chick Weight': 'وزن الكتكوت المرجعي BMK',
  'Avg Weight': 'متوسط الوزن',
  'Low Margin': 'الحد الأدنى',
  'High Margin': 'الحد الأعلى',
  'Uniformity': 'التجانس',
  'Pasgar Score': 'تقييم Pasgar',
  'Culled Chicks Analysis': 'تحليل الكتاكيت المستبعدة',
  'BMK Age': 'العمر المرجعي BMK',
  'Egg Weights & Uniformity': 'أوزان البيض وتجانسها',
  'Egg Turning': 'تقليب البيض',
  'Tray Spacing': 'المسافة بين الصواني',
  'Cooler Proximity': 'القرب من وحدة التبريد',
  'Condensation Present': 'وجود تكثف',
  'Cuticle Damage': 'تلف الكيوتيكل',
  'Washed': 'مغسول',
  'Dirty': 'متسخ',
  'Upside Down': 'مقلوب',
  'BMK Egg Weight': 'وزن البيضة المرجعي BMK',
  'Eggshell Temperature': 'حرارة سطح قشرة البيض',
  'shell_temp': 'حرارة سطح القشرة',
  'Short storage': 'تخزين قصير',
  'Medium storage': 'تخزين متوسط',
  'Long storage': 'تخزين طويل',
  'Egg storage room': 'غرفة تخزين البيض',
  'Upside Down Score': 'نسبة البيض المقلوب',
  'Storage Checklist': 'قائمة فحص التخزين',
  'Egg Shell Quality': 'جودة قشرة البيض',
  'Affected': 'متأثر',
  'Storage days': 'أيام التخزين',
  'Candled age': 'العمر عند الفحص الضوئي',
  'Hatch Results': 'نتائج الفقس',
  'Hatch totals': 'إجماليات الفقس',
  'Total eggs set': 'إجمالي البيض المحضن',
  'Hatched chicks': 'الكتاكيت الفاقسة',
  'Culled': 'مستبعد',
  'Dead': 'نافق',
  'Performance': 'الأداء',
  'Hatchability': 'نسبة الفقس',
  'Fertility': 'نسبة الإخصاب',
  'Culled %': 'نسبة المستبعد',
  'Dead %': 'نسبة النافق',
  'Sample size': 'حجم العينة',
  'Tray size': 'سعة الصينية',
  'Trolley scope': 'نطاق العربات',
  'No': 'لا',
  'Yes': 'نعم',
  'setter_est': 'حرارة سطح البيض داخل ماكينة التحضين',
  'Chick holding area': 'منطقة انتظار الكتاكيت',
  'Setter room': 'غرفة ماكينات التحضين',
  'Hatcher room': 'غرفة ماكينات الفقس',
  'Autosave issue': 'مشكلة في الحفظ التلقائي',
  'Saving draft': 'جار حفظ المسودة',
  'Save pending': 'الحفظ قيد الانتظار',
  'Draft saved': 'تم حفظ المسودة',
  'Batch Level:': 'مستوى الدفعة:',
  'Compare different egg batches.': 'قارن بين دفعات البيض المختلفة.',
  'House Level:': 'مستوى العنبر:',
  'Compare houses within the same batch.':
      'قارن بين العنابر داخل الدفعة نفسها.',
  'Machine Level:': 'مستوى الماكينة:',
  'Compare machines (Setter + Hatcher) within the same batch.':
      'قارن بين ماكينات التحضين والفقس داخل الدفعة نفسها.',
  'Tray Level:': 'مستوى الصينية:',
  'Compare trays within the same machine.':
      'قارن بين الصواني داخل الماكينة نفسها.',
  'Total %': 'النسبة الإجمالية',
  'cvt': 'حرارة جسم الكتكوت',
  'Defect Counts': 'أعداد العيوب',
  'Chick': 'الكتكوت',
  'Yolk': 'المح',
  'Rows': 'الصفوف',
  'Average': 'المتوسط',
  'Pending Approval': 'بانتظار الاعتماد',
  'Forgot Password': 'استعادة كلمة المرور',
  'Target': 'المستهدف',
  'Benchmark age': 'العمر المرجعي',
  'Fresh': 'طازج',
  'Candled': 'بعد الفحص الضوئي',
  'Residue': 'متبقيات الفقس',
  'Egg': 'البيض',
  'Reference age': 'العمر المرجعي',
  'Production': 'الإنتاج',
  'Egg weight': 'وزن البيضة',
  'Chick weight': 'وزن الكتكوت',
  'Reference': 'المرجع',
  'Age': 'العمر',
  'Infertile': 'غير مخصب',
  '24 hours': '24 ساعة',
  '48 hours': '48 ساعة',
  'Blood Ring': 'حلقة دموية',
  'Black Eye': 'طور العين السوداء',
  'Early Dead': 'نفوق جنيني مبكر',
  'Mid Dead': 'نفوق جنيني متوسط',
  'Late Dead': 'نفوق جنيني متأخر',
  'External Pip': 'نقر خارجي',
  'Cracked': 'مكسور',
  'Contaminated': 'ملوث',
  'Min': 'الأدنى',
  'Max': 'الأعلى',
  'Visit': 'الزيارة',
  'Weights': 'الأوزان',
  'Setup': 'الإعدادات التشغيلية',
  'Environment': 'البيئة',
  'Egg Shell Temperature (EST)': 'حرارة سطح قشرة البيض (EST)',
  'UV Tray Inspection': 'فحص الصينية بالأشعة فوق البنفسجية',
  'Audit Summary': 'ملخص الزيارة',
  'Flocks': 'القطعان',
  'Manage': 'إدارة',
  'No flocks yet': 'لا توجد قطعان حتى الآن',
  'Manage flocks': 'إدارة القطعان',
  'Hatcheries': 'معامل التفريخ',
  'No hatcheries registered': 'لا توجد معامل تفريخ مسجلة',
  'Add hatchery': 'إضافة معمل تفريخ',
  'Audit history': 'سجل الزيارات',
  'No audits yet': 'لا توجد زيارات حتى الآن',
  'Start a new visit from the Home tab to record audits for this customer.':
      'ابدأ زيارة جديدة من تبويب الرئيسية لتسجيل تقييمات هذا العميل.',
  'Recent visits': 'الزيارات الأخيرة',
  'Flock age': 'عمر القطيع',
  'Lesions': 'الآفات',
  'Set': 'المحضن',
  'Hatched': 'فاقس',
  'Fertility%': 'نسبة الإخصاب',
  'Visit Summary': 'ملخص الزيارة',
  'Age source': 'مصدر العمر',
  'Current age': 'العمر الحالي',
  'Availability': 'حالة الإتاحة',
  'Active': 'نشط',
  'Sold': 'مباع',
  'Hatchery name *': 'اسم معمل التفريخ *',
  'Setpoint vs actual': 'درجة الضبط مقابل الفعلية',
  'CO₂ / turning': 'ثاني أكسيد الكربون / التقليب',
  'Setpoint': 'درجة الضبط',
  'CO₂': 'ثاني أكسيد الكربون',
  'Transfer': 'النقل',
  'Chick weights': 'أوزان الكتاكيت',
  'Hatch result': 'نتيجة الفقس',
  'Fresh breakout': 'فحص البيض الطازج',
  'Candled breakout': 'فحص البيض بعد الفحص الضوئي',
  'Residue breakout': 'فحص متبقيات الفقس',
  'Excellent': 'ممتاز',
  'Acceptable': 'مقبول',
  'Investigate': 'يحتاج فحصًا',
  'Avg': 'المتوسط',
  'Temp': 'الحرارة',
  'On target': 'ضمن المستهدف',
  'Watch': 'متابعة',
  'Below': 'أقل من المستهدف',
  'Hatchability %': 'نسبة الفقس %',
  'Fertility %': 'نسبة الإخصاب %',
  'HOF %': 'نسبة الفقس من البيض المخصب %',
  'Over': 'أعلى من المستهدف',
  'Standard': 'المعيار',
  'ACTION': 'إجراء مطلوب',
  'No egg storage or quality data for this filter yet.':
      'لا توجد بيانات تخزين أو جودة بيض لعوامل التصفية الحالية.',
  'Rate': 'النسبة',
  'Turning': 'التقليب',
  'Tray spacing': 'المسافة بين الصواني',
  'Cooler': 'وحدة التبريد',
  'No egg quality samples for this filter yet.':
      'لا توجد عينات جودة بيض لعوامل التصفية الحالية.',
  'Act': 'الفعلي',
  'Shell Quality UV': 'جودة القشرة بالأشعة فوق البنفسجية',
  'No reading': 'لا توجد قراءة',
  'Low vs target': 'أقل من المستهدف',
  'High vs target': 'أعلى من المستهدف',
  'Within target': 'ضمن المستهدف',
  'Reflexes': 'ردود الفعل',
  'Beak': 'المنقار',
  'Navel': 'السرة',
  'Belly': 'البطن',
  'Leg': 'الأرجل',
  'Feather Development': 'نمو الريش',
  'Upside Down Egg': 'البيض المقلوب',
  'Storage Info': 'بيانات التخزين',
  'Humidity': 'الرطوبة',
  'Connection details': 'تفاصيل الاتصال',
  'Device name': 'اسم الجهاز',
  'Device ID': 'معرّف الجهاز',
  'Battery': 'البطارية',
  'Last update': 'آخر تحديث',
  'Create the first audit': 'أنشئ الزيارة الأولى',
  'Range': 'النطاق',
  'Session-linked': 'مرتبطة بجلسة',
  'Recorded': 'مسجل',
  'Please enter a hatchery name': 'يرجى إدخال اسم معمل التفريخ',
  'Please enter a flock ID': 'يرجى إدخال معرّف القطيع',
  'Enter age between 0 and 120 weeks': 'أدخل عمرًا بين 0 و120 أسبوعًا',
  'Enter depletion age between 1 and 160 weeks':
      'أدخل عمر انتهاء الدورة بين 1 و160 أسبوعًا',
  'Please enter a name': 'يرجى إدخال الاسم',
  'Please enter your email': 'يرجى إدخال بريدك الإلكتروني',
  'Please enter a valid email': 'يرجى إدخال بريد إلكتروني صحيح',
  'Please enter your password': 'يرجى إدخال كلمة المرور',
  'Please enter your full name': 'يرجى إدخال الاسم الكامل',
  'Please enter a password': 'يرجى إدخال كلمة مرور',
  'Password must be at least 12 characters':
      'يجب ألا تقل كلمة المرور عن 12 حرفًا',
  'Password must contain a lowercase letter':
      'يجب أن تحتوي كلمة المرور على حرف إنجليزي صغير',
  'Password must contain an uppercase letter':
      'يجب أن تحتوي كلمة المرور على حرف إنجليزي كبير',
  'Password must contain at least one number':
      'يجب أن تحتوي كلمة المرور على رقم واحد على الأقل',
  'Password must contain at least one symbol':
      'يجب أن تحتوي كلمة المرور على رمز واحد على الأقل',
  'Please confirm your password': 'يرجى تأكيد كلمة المرور',
  'Passwords do not match': 'كلمتا المرور غير متطابقتين',
  'Egg Weight Sheet': 'سجل أوزان البيض',
  'Chick Weight Sheet': 'سجل أوزان الكتاكيت',
  'Low': 'منخفض',
  'High': 'مرتفع',
  'Optimal': 'مثالي',
  'Single': 'فردي',
  'Multi': 'متعدد',
  'This account has read-only access.': 'هذا الحساب للعرض فقط.',
  'Please enter a valid email.': 'يرجى إدخال بريد إلكتروني صحيح.',
  'Reset link could not be sent right now.':
      'تعذر إرسال وصلة إعادة التعيين الآن.',
  'Internet access is required to sign in on this device.':
      'يلزم الاتصال بالإنترنت لتسجيل الدخول على هذا الجهاز.',
  'The email or password is incorrect.':
      'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
  'Please confirm your email before signing in.':
      'يرجى تأكيد بريدك الإلكتروني قبل تسجيل الدخول.',
  'An account with this email already exists.':
      'يوجد حساب مسجل بهذا البريد الإلكتروني.',
  'Account creation is disabled in Supabase. Enable signups to create new accounts.':
      'إنشاء الحسابات معطل في Supabase. فعّل التسجيل لإنشاء حسابات جديدة.',
  'Account creation is blocked by a Supabase database trigger or policy.':
      'إنشاء الحساب محظور بسبب مشغل أو سياسة في قاعدة بيانات Supabase.',
  'Supabase returned unexpected_failure. Check Auth settings, email confirmation, and database triggers for new users.':
      'أعاد Supabase خطأ غير متوقع. راجع إعدادات المصادقة وتأكيد البريد ومشغلات قاعدة البيانات للمستخدمين الجدد.',
  'Supabase credentials are not configured. Run the app with --dart-define-from-file=.env.':
      'بيانات اتصال Supabase غير مضبوطة. شغّل التطبيق باستخدام ملف إعدادات البيئة.',
  'Supabase is still initializing. Try again in a moment.':
      'لا يزال Supabase قيد التهيئة. حاول مرة أخرى بعد قليل.',
  'Sign-in failed': 'فشل تسجيل الدخول',
  'Sign-up failed': 'فشل إنشاء الحساب',
  'Login failed': 'فشل تسجيل الدخول',
  'Registration failed': 'فشل إنشاء الحساب',
  'This station was saved, but it does not have enough core data to complete the visit. Continue saving it as incomplete?':
      'تم حفظ المحطة، لكن بياناتها الأساسية غير كافية لإكمال الزيارة. هل تريد إبقاءها غير مكتملة والمتابعة؟',
  'This station was saved, but it does not have enough core data to mark complete. Continue to the next station without completing it?':
      'تم حفظ المحطة، لكن بياناتها الأساسية غير كافية لاعتماد اكتمالها. هل تريد الانتقال إلى المحطة التالية دون إكمالها؟',
  'This station was saved, but it does not have enough core data to mark complete. Continue to the selected station without completing it?':
      'تم حفظ المحطة، لكن بياناتها الأساسية غير كافية لاعتماد اكتمالها. هل تريد الانتقال إلى المحطة المحددة دون إكمالها؟',
  'This station was saved, but it does not have enough core data to mark complete. Leave it incomplete and continue?':
      'تم حفظ المحطة، لكن بياناتها الأساسية غير كافية لاعتماد اكتمالها. هل تريد إبقاءها غير مكتملة والمتابعة؟',
  'Inline camera is unavailable. Capture will open the camera app.':
      'الكاميرا المضمنة غير متاحة. سيتم فتح تطبيق الكاميرا لالتقاط الصورة.',
  'Camera permission is needed. Use the camera app or enable camera access.':
      'يلزم إذن الكاميرا. استخدم تطبيق الكاميرا أو فعّل الوصول إليها.',
  'No camera found. Use the camera app fallback.':
      'لم يتم العثور على كاميرا. استخدم تطبيق الكاميرا البديل.',
  'Camera took too long to start. Resume camera or use the camera app.':
      'استغرق تشغيل الكاميرا وقتًا طويلًا. استأنف الكاميرا أو استخدم تطبيقها.',
  'Camera capture failed. Try again or use the camera app.':
      'فشل التقاط الصورة. حاول مرة أخرى أو استخدم تطبيق الكاميرا.',
  'Camera unavailable. Capture will open the camera app.':
      'الكاميرا غير متاحة. سيتم فتح تطبيق الكاميرا لالتقاط الصورة.',
  'Required': 'مطلوب',
  'Enter a number': 'أدخل رقمًا',
  'Must be 0 or more': 'يجب ألا تقل القيمة عن 0',
  'Max 100': 'الحد الأقصى 100',
  'Weights · Pasgar · CVT · YFBM':
      'الأوزان · Pasgar · حرارة جسم الكتكوت · نسبة وزن كيس المح',
  'Hatchability · fertility · HOF · residue breakouts':
      'نسبة الفقس · الإخصاب · الفقس من البيض المخصب · فحص متبقيات الفقس',
  'Setpoint vs actual · EST · CO₂ · turning':
      'درجة الضبط مقابل الفعلية · حرارة سطح البيض · ثاني أكسيد الكربون · التقليب',
  'Setpoint · CVT · CO₂ · transfer window':
      'درجة الضبط · حرارة جسم الكتكوت · ثاني أكسيد الكربون · نافذة النقل',
  'No Turning': 'لا يوجد تقليب',
  '1 time': 'مرة واحدة',
  'CV% is above the app limit.': 'معامل الاختلاف أعلى من حد التطبيق.',
  'C.V is above the app limit, and uniformity is below target.':
      'معامل الاختلاف أعلى من حد التطبيق، والتجانس أقل من المستهدف.',
  'C.V is above the app limit.': 'معامل الاختلاف أعلى من حد التطبيق.',
  'Uniformity is below target.': 'التجانس أقل من المستهدف.',
  'Place recording': 'تسجيل المكان',
  'Syncing Govee history': 'جار مزامنة سجل Govee',
  'History sync failed': 'فشلت مزامنة السجل',
  'Saving place capture': 'جار حفظ تسجيل المكان',
  'Save failed': 'فشل الحفظ',
  'Place capture saved': 'تم حفظ تسجيل المكان',
  'Place recorder': 'مسجل المكان',
  'Syncing saved history from the Govee device.':
      'جار مزامنة السجل المحفوظ من جهاز Govee.',
  'Reconnect and retry this place recording.':
      'أعد الاتصال ثم أعد محاولة تسجيل هذا المكان.',
  'Saving LTTB chart points and full summary stats.':
      'جار حفظ نقاط المخطط والإحصاءات الملخصة الكاملة.',
  'Retry save using the synced Govee history already captured.':
      'أعد محاولة الحفظ باستخدام سجل Govee الذي تمت مزامنته.',
  'Saved. Choose another place when ready.':
      'تم الحفظ. اختر مكانًا آخر عندما تكون مستعدًا.',
  'Start once for this place, then stop when the place window is complete.':
      'ابدأ التسجيل مرة واحدة لهذا المكان، ثم أوقفه عند اكتمال فترة التسجيل.',
  'Depleted': 'منتهي الدورة',
  'Depletion age': 'عمر انتهاء الدورة',
  'Mark sold': 'تحديد كمباع',
  'Mark active': 'إعادة تنشيط',
  'Estimated entry': 'تاريخ إدخال تقديري',
  'Sold date': 'تاريخ البيع',
  'Omphalitis': 'التهاب السرة',
  'Gaseous Ceca': 'انتفاخ الأعورين بالغازات',
  'Air Sac Caseations': 'تجبن الأكياس الهوائية',
  'Urolithiasis (Urate Deposits)': 'ترسبات اليورات في الكلى والحالبين',
  'Nephritis': 'التهاب الكلى',
  'General Septicemia': 'تسمم دموي عام',
  'Gizzard Erosions': 'تآكلات القانصة',
  'Out of range — check ventilation / set-point now.':
      'خارج النطاق — افحص التهوية ودرجة الضبط الآن.',
  'Critical': 'حرج',
  'Near the target floor — monitor next visit.':
      'قريب من الحد الأدنى للمستهدف — تابع في الزيارة المقبلة.',
  'Slightly over limit — monitor next visit.':
      'أعلى قليلًا من الحد — تابع في الزيارة المقبلة.',
  'breed BMK': 'BMK السلالة',
  'visit': 'الزيارة',
  'capture': 'التسجيل',
  'just now': 'الآن',
  'Inside setter': 'داخل ماكينة التحضين',
  'Inside hatcher': 'داخل ماكينة الفقس',
  'CVT avg': 'متوسط حرارة جسم الكتكوت',
  'EST avg': 'متوسط حرارة سطح البيض',
  'Eggs set': 'البيض المحضن',
  'CO2': 'ثاني أكسيد الكربون',
  'Offline — last sync failed': 'بدون اتصال — فشلت آخر مزامنة',
  'Sync status': 'حالة المزامنة',
  'Synced': 'تمت المزامنة',
  'Any date': 'أي تاريخ',
  'Failed': 'فشل',
  'Completed': 'مكتملة',
  'In Progress': 'قيد التنفيذ',
  'Completed and in-progress visits will appear here':
      'ستظهر هنا الزيارات المكتملة والجارية',
  'Could not load Govee records': 'تعذر تحميل سجلات Govee',
  'Could not load visits': 'تعذر تحميل الزيارات',
  'Could not load more visits': 'تعذر تحميل المزيد من الزيارات',
  'Lab Analysis': 'تحاليل المعمل',
  'Add lab result': 'إضافة نتيجة معمل',
  'No lab results yet': 'لا توجد نتائج معمل بعد',
  'New lab report': 'تقرير معمل جديد',
  'Report context': 'سياق التقرير',
  'Who performed the test and what flock material was tested.':
      'من أجرى الاختبار وما مادة القطيع التي تم فحصها.',
  'Laboratory': 'المعمل',
  'Source report': 'التقرير الأصلي',
  'Attach the original PDF so every saved result remains auditable.':
      'أرفق ملف PDF الأصلي لضمان إمكانية مراجعة كل نتيجة محفوظة.',
  'Notes / clinical context': 'ملاحظات / سياق سريري',
  'Add ELISA, PCR, HI, bacterial culture, or sensitivity results for the selected flock.':
      'أضف نتائج ELISA أو PCR أو HI أو المزرعة البكتيرية أو اختبار الحساسية للقطيع المحدد.',
  'Lab report': 'تقرير معمل',
  'View PDF': 'عرض PDF',
  'Attach PDF': 'إرفاق PDF',
  'Replace PDF': 'استبدال PDF',
  'No PDF attached': 'لا يوجد PDF مرفق',
  'PDF saved in cloud': 'تم حفظ PDF في السحابة',
  'PDF preview is not available': 'معاينة PDF غير متاحة',
  'Could not open PDF': 'تعذر فتح PDF',
  'Delete lab report?': 'حذف تقرير المعمل؟',
  'This removes the report, result groups, and sample rows.':
      'سيتم حذف التقرير ومجموعات النتائج وصفوف العينات.',
  'Reports': 'التقارير',
  'Test types': 'أنواع الاختبارات',
  'Alerts': 'تنبيهات',
  'Recent findings': 'أحدث النتائج',
  'GMT change': 'التغير في GMT',
  'CV improvement': 'تحسن CV',
  'Latest positive': 'أحدث نسبة إيجابية',
  'Pooled repeat': 'إعادة مجمعة',
  'LATEST SNAPSHOT': 'أحدث لقطة',
  'Average GMT': 'متوسط GMT',
  'Average CV': 'متوسط CV',
  'Breeder farm lab signals from ELISA, PCR, HI, bacterial culture, and sensitivity records.':
      'مؤشرات تحاليل مزارع الأمهات من سجلات ELISA وPCR وHI والمزرعة البكتيرية والحساسية.',
  'No lab analysis records for this filter yet.':
      'لا توجد سجلات تحاليل معمل لعوامل التصفية الحالية.',
  'Lab name': 'اسم المعمل',
  'Sample type': 'نوع العينة',
  'Broiler chicks': 'كتاكيت تسمين',
  'Blood samples': 'عينات دم',
  'Serum / Plasma': 'مصل / بلازما',
  'Tissue samples': 'عينات أنسجة',
  'Swabs': 'مسحات',
  'Tracheal swabs': 'مسحات قصبة هوائية',
  'Cloacal swabs': 'مسحات مجمعية',
  'Organ samples': 'عينات أعضاء',
  'Isolate': 'معزولة',
  'Culture / isolation test': 'اختبار المزرعة / العزل',
  'Culture findings': 'نتائج المزرعة',
  'Bacterial organism': 'نوع البكتيريا',
  'Culture result': 'نتيجة المزرعة',
  'No bacterial organism was isolated in the saved culture rows.':
      'لم يتم عزل أي كائن بكتيري في صفوف المزرعة المحفوظة.',
  'Organism isolated / culture positive.': 'تم عزل الكائن / المزرعة إيجابية.',
  'Organism not isolated / culture negative.':
      'لم يتم عزل الكائن / المزرعة سلبية.',
  'Salmonella isolation': 'عزل سالمونيلا',
  'General bacterial culture': 'مزرعة بكتيرية عامة',
  'Not isolated': 'لم يتم العزل',
  'Isolated': 'تم العزل',
  'No growth': 'لا يوجد نمو',
  'Mixed growth': 'نمو مختلط',
  'House / sample': 'العنبر / العينة',
  'Sample / isolate': 'العينة / المعزولة',
  'OD': 'الكثافة الضوئية',
  'S/P': 'نسبة S/P',
  'S': 'S',
  'I': 'متوسط',
  'R': 'مقاوم',
  'P': 'إيجابي',
  'N': 'سلبي',
  '+VE': 'إيجابي',
  '-VE': 'سلبي',
  'Detected': 'مكتشف',
  'Not detected': 'غير مكتشف',
  'Analyte': 'العامل المراد كشفه',
  'Analyte / antibody': 'المادة المراد تحليلها / الجسم المضاد',
  'Kit': 'الكيت',
  'Assay kit': 'عدة الاختبار',
  'Product code': 'كود المنتج',
  'Product / kit code': 'كود المنتج / العدة',
  'Samples': 'العينات',
  'Summary': 'الملخص',
  'Plate summary': 'ملخص اللوحة',
  'Number of samples': 'عدد العينات',
  'Positive samples': 'العينات الإيجابية',
  'Negative samples': 'العينات السلبية',
  'Mean titer': 'متوسط العيار',
  'Geometric mean titer (GMT)': 'المتوسط الهندسي للعيار (GMT)',
  'Coefficient of variation (CV%)': 'معامل الاختلاف (CV%)',
  'Minimum titer': 'أقل عيار',
  'Maximum titer': 'أعلى عيار',
  'Positive cut-off S/P': 'حد الإيجابية لنسبة S/P',
  'Positive cut-off titer': 'حد العيار الإيجابي',
  'Enter individual sample rows': 'إدخال صفوف العينات الفردية',
  'Optional. Turn this on when OD, S/P, titer, and result are available.':
      'اختياري. فعّل هذا الخيار عند توفر OD وS/P والعيار والنتيجة.',
  'Individual sera': 'عينات المصل الفردية',
  'Number of sera': 'عدد عينات المصل',
  'Geometric mean (log₂)': 'المتوسط الهندسي (log₂)',
  'Titer distribution': 'توزيع العيارات',
  'Group': 'المجموعة',
  'Ct value': 'قيمة Ct',
  'Antimicrobial': 'مضاد ميكروبي',
  'Interpretation': 'التفسير',
  'Positive / Negative': 'إيجابي / سلبي',
  'Protected / Not protected': 'محمي / غير محمي',
  'Sample details': 'تفاصيل العينات',
  'View sample details': 'عرض تفاصيل العينات',
  'Hide sample details': 'إخفاء تفاصيل العينات',
  'Minimum Ct': 'أقل قيمة Ct',
  'Maximum Ct': 'أعلى قيمة Ct',
  'Positive': 'إيجابي',
  'Negative': 'سلبي',
  'Mean': 'المتوسط',
  'GMT': 'المتوسط الهندسي للعيار',
  'G.M.T.': 'المتوسط الهندسي للعيار',
  'CV %': 'معامل الاختلاف %',
  'Minimum': 'الحد الأدنى',
  'Maximum': 'الحد الأقصى',
  'Cut-off S/P': 'حد S/P',
  'Cut-off titer': 'حد العيار',
  'ELISA samples': 'عينات ELISA',
  'Save the plate summary first. Individual sera are optional and useful for distribution analysis.':
      'احفظ ملخص اللوحة أولًا. عينات المصل الفردية اختيارية ومفيدة لتحليل التوزيع.',
  'Record one row per target with the reported detected status and Ct when available.':
      'سجل صفًا واحدًا لكل هدف مع حالة الكشف المبلغ عنها وقيمة Ct عند توفرها.',
  'Record the antigen, geometric mean, and number of sera at each log₂ titer.':
      'سجل المستضد والمتوسط الهندسي وعدد عينات المصل عند كل عيار log₂.',
  'Record the culture or isolation method, each organism tested, and whether it was isolated.':
      'سجل طريقة المزرعة أو العزل وكل كائن تم اختباره وما إذا تم عزله.',
  'Record only the laboratory S / I / R category for each tested antimicrobial.':
      'سجل فقط تصنيف المعمل S / I / R لكل مضاد ميكروبي تم اختباره.',
  'PCR targets': 'أهداف PCR',
  'Antigen': 'المستضد',
  'NDV LASOTA': 'NDV لاسوتا',
  'H5 (RE-14)': 'H5 (RE-14)',
  'H9': 'H9',
  'No. of sera': 'عدد السيرم',
  'G.M.': 'المتوسط الهندسي',
  'HI titer log-2 distribution': 'توزيع عيارات HI لوغ 2',
  'Organism': 'الميكروب',
  'Antibiotics': 'المضادات',
  'Antibiotic': 'المضاد',
  'No.': 'رقم',
  'Result': 'النتيجة',
  'Titer': 'العيار',
  'Grp': 'مجموعة',
  'Ct': 'قيمة Ct',
  'Signal': 'الإشارة',
  'Protected': 'محمي',
  'Threshold': 'الحد',
  'Sera': 'سيرم',
  'Sensitive': 'حساس',
  'Intermediate': 'متوسط الحساسية',
  'Resistant': 'مقاوم',
  'Alert': 'تنبيه',
  'High ELISA CV%: antibody response is non-uniform; review vaccination/exposure history.':
      'معامل اختلاف ELISA مرتفع: استجابة الأجسام المناعية غير متجانسة؛ راجع تاريخ التحصين أو التعرض.',
  'Moderate ELISA CV%: response uniformity needs follow-up against this flock baseline.':
      'معامل اختلاف ELISA متوسط: تجانس الاستجابة يحتاج متابعة مقارنة بخط أساس هذا القطيع.',
  'Seropositive ELISA result: interpret with vaccination history and confirm active infection with PCR/RSA when needed.':
      'نتيجة ELISA مصلية إيجابية: تُفسر مع تاريخ التحصين أو التعرض، ويُؤكد الاشتباه النشط بـ PCR أو RSA عند الحاجة.',
  'ELISA summary is within the saved interpretation guardrails.':
      'ملخص ELISA ضمن ضوابط التفسير المحفوظة.',
  'ELISA positive sample.': 'عينة ELISA إيجابية.',
  'ELISA negative sample.': 'عينة ELISA سلبية.',
  'PCR targets were not detected in the saved rows.':
      'لم تُكتشف أهداف PCR في الصفوف المحفوظة.',
  'PCR positive with low Ct signal; prioritize this flock/house for follow-up.':
      'PCR إيجابي مع Ct منخفض؛ أعطِ هذا القطيع أو العنبر أولوية في المتابعة.',
  'PCR positive; Ct should be interpreted against lab cutoffs and clinical context.':
      'PCR إيجابي؛ يجب تفسير Ct وفق حدود المعمل والسياق الحقلي.',
  'Target not detected.': 'لم يتم اكتشاف الهدف.',
  'PCR target detected.': 'تم اكتشاف هدف PCR.',
  'PCR positive with low Ct signal.': 'PCR إيجابي مع Ct منخفض.',
  'PCR positive; compare with lab cutoff and history.':
      'PCR إيجابي؛ قارنه بحد المعمل وتاريخ القطيع.',
  'Low-level PCR positive; confirm with lab cutoff and repeat/context.':
      'PCR إيجابي منخفض المستوى؛ أكده بحد المعمل وإعادة الفحص أو السياق الحقلي.',
  'HI GMT is below the saved protective threshold.':
      'المتوسط الهندسي HI أقل من حد الحماية المحفوظ.',
  'HI protection distribution is low for this antigen.':
      'توزيع الحماية في HI منخفض لهذا المستضد.',
  'HI protection distribution is borderline; monitor trend.':
      'توزيع الحماية في HI حدّي؛ تابع الاتجاه.',
  'HI distribution is protective by the saved threshold.':
      'توزيع HI محقق للحماية حسب الحد المحفوظ.',
  'HI distribution bin saved.': 'تم حفظ فئة توزيع HI.',
  'No sensitive antibiotic was recorded for this sample.':
      'لم يُسجل أي مضاد حساس لهذه العينة.',
  'Resistance dominates this sensitivity panel.':
      'المقاومة هي الغالبة في لوحة الحساسية.',
  'Sensitivity panel has at least one sensitive option recorded.':
      'تحتوي لوحة الحساسية على خيار حساس واحد على الأقل.',
  'Resistant: high likelihood of treatment failure.':
      'مقاوم: احتمال فشل العلاج مرتفع.',
  'Intermediate: needs veterinary dosing/context.':
      'متوسط الحساسية: يحتاج تقييم الجرعة والسياق البيطري.',
  'Sensitive: recorded as an in-vitro option.':
      'حساس: مسجل كخيار فعال معمليًا.',
  'Add result': 'إضافة نتيجة',
  'Failed to start visit session': 'تعذر بدء جلسة الزيارة',
  'Failed to resume visit session': 'تعذر استئناف جلسة الزيارة',
  'Session not found': 'لم يتم العثور على الجلسة',
  'Failed to update visit stations': 'تعذر تحديث محطات الزيارة',
  'Failed to save station progress': 'تعذر حفظ تقدم المحطة',
  'Failed to save session progress': 'تعذر حفظ تقدم الجلسة',
  'Failed to complete visit session': 'تعذر إكمال جلسة الزيارة',
  'Failed to delete visit session': 'تعذر حذف جلسة الزيارة',
  'Could not load saved Govee captures for this date.':
      'تعذر تحميل تسجيلات Govee المحفوظة لهذا التاريخ.',
  'Could not scan for the Govee sensor': 'تعذر البحث عن مستشعر Govee',
  'Could not request a live Govee reading': 'تعذر طلب قراءة مباشرة من Govee',
  'Could not disconnect the Govee sensor': 'تعذر قطع الاتصال بمستشعر Govee',
  'Could not connect to the selected Govee sensor':
      'تعذر الاتصال بمستشعر Govee المحدد',
  'Choose a customer, hatchery, date, and place first':
      'اختر العميل ومعمل التفريخ والتاريخ والمكان أولًا',
  'Start recording before saving this Govee place capture':
      'ابدأ التسجيل قبل حفظ قراءة Govee لهذا المكان',
  'Reconnect the Govee sensor, then retry this place recording.':
      'أعد توصيل مستشعر Govee ثم أعد محاولة تسجيل هذا المكان.',
  'Broiler daily entry': 'الإدخال اليومي لقطعان التسمين',
  'Broiler performance': 'أداء قطعان التسمين',
  'Broiler farm': 'مزرعة تسمين',
  'Daily quick entry': 'الإدخال اليومي السريع',
  'Current status': 'الحالة الحالية',
  'Trends': 'الاتجاهات',
  'Active concerns': 'المشكلات النشطة',
  'Audits and corrective actions': 'الزيارات والإجراءات التصحيحية',
  'Reported': 'مبلغ عنها',
  'Target source': 'مصدر المستهدف',
  'No daily performance data for this period':
      'لا توجد بيانات أداء يومية لهذه الفترة',
  'No trend data for this period': 'لا توجد بيانات اتجاهات لهذه الفترة',
  'No valid trend values': 'لا توجد قيم اتجاهات صالحة',
  'No active concerns': 'لا توجد مشكلات نشطة',
  'No visits or corrective actions yet':
      'لا توجد زيارات أو إجراءات تصحيحية بعد',
  'Farm visits': 'زيارات المزرعة',
  'Corrective actions': 'الإجراءات التصحيحية',
  'Live population': 'عدد الطيور الحية',
  'Weight versus target': 'الوزن مقارنة بالمستهدف',
  'Daily mortality': 'النافق اليومي',
  'Cumulative mortality': 'النافق التراكمي',
  'Livability': 'الحيوية',
  'Feed per live bird': 'العلف لكل طائر حي',
  'Cumulative feed': 'العلف التراكمي',
  'Feed per placed bird': 'العلف لكل طائر مسكن',
  'Water per live bird': 'الماء لكل طائر حي',
  'Water-to-feed ratio': 'نسبة الماء إلى العلف',
  'Average daily gain': 'متوسط الزيادة اليومية',
  'Expected cumulative feed': 'العلف التراكمي المتوقع',
  'Feed versus target': 'العلف مقارنة بالمستهدف',
  'Estimated FCR': 'معامل التحويل التقديري',
  'Unavailable': 'غير متاح',
  'Current value': 'القيمة الحالية',
  'Latest': 'الأحدث',
  'Daily mortality trend': 'اتجاه النافق اليومي',
  'Cumulative mortality trend': 'اتجاه النافق التراكمي',
  'Daily feed consumption': 'استهلاك العلف اليومي',
  'Daily water consumption': 'استهلاك الماء اليومي',
  'Body weight trend': 'اتجاه وزن الجسم',
  'Uniformity trend': 'اتجاه التجانس',
  'Estimated FCR trend': 'اتجاه معامل التحويل التقديري',
  'Evidence retained for investigation': 'تم حفظ الدليل للتحقيق',
  'Planned': 'مخطط',
  'Cancelled': 'ملغي',
  'Implemented': 'تم التنفيذ',
  'Diagnostic farm visit': 'زيارة تشخيصية للمزرعة',
  'No farm visit selected': 'لم يتم اختيار زيارة مزرعة',
  'Investigations': 'الفحوصات',
  'Add investigation': 'إضافة فحص',
  'No investigations added': 'لم تتم إضافة فحوصات',
  'Probable causes': 'الأسباب المحتملة',
  'Add cause': 'إضافة سبب',
  'No causes assessed': 'لم يتم تقييم أسباب',
  'Start visit': 'بدء الزيارة',
  'Complete visit': 'إكمال الزيارة',
  'Add manual investigation': 'إضافة فحص يدوي',
  'Investigation type': 'نوع الفحص',
  'Instruction': 'التعليمات',
  'Result summary': 'ملخص النتيجة',
  'Add visit finding': 'إضافة نتيجة زيارة',
  'Finding type': 'نوع النتيجة',
  'Measured value': 'القيمة المقاسة',
  'Unit': 'الوحدة',
  'Staff explanation': 'تفسير العاملين',
  'Performance concern': 'مشكلة الأداء',
  'Suspected cause': 'السبب المشتبه به',
  'Visit briefing': 'ملخص ما قبل الزيارة',
  'Target version': 'إصدار المستهدف',
  'Rule version': 'إصدار القاعدة',
  'Daily performance evidence': 'أدلة الأداء اليومية',
  'No daily evidence in this briefing': 'لا توجد أدلة يومية في هذا الملخص',
  'Daily facts are read-only here; record only visit evidence.':
      'الحقائق اليومية للقراءة فقط هنا؛ سجل أدلة الزيارة فقط.',
  'Suggested': 'مقترح',
  'Manual': 'يدوي',
  'attachments': 'مرفقات',
  'Complete investigation': 'إكمال الفحص',
  'Add finding': 'إضافة نتيجة',
  'Not applicable': 'غير منطبق',
  'Concern': 'المشكلة',
  'supporting evidence items': 'عناصر أدلة داعمة',
  'Cause status': 'حالة السبب',
  'Suspected': 'مشتبه به',
  'Probable': 'محتمل',
  'Confirmed': 'مؤكد',
  'Ruled out': 'مستبعد',
  'Corrective action': 'إجراء تصحيحي',
  'No corrective action selected': 'لم يتم اختيار إجراء تصحيحي',
  'KPI effectiveness': 'فعالية مؤشر الأداء',
  'Confirm implementation': 'تأكيد التنفيذ',
  'Record evaluation decision': 'تسجيل قرار التقييم',
  'Effectiveness': 'الفعالية',
  'Observed value': 'القيمة المرصودة',
  'Evaluation reason': 'سبب التقييم',
  'Owner': 'المسؤول',
  'Due': 'موعد الاستحقاق',
  'Implementation confirmed by': 'تم تأكيد التنفيذ بواسطة',
  'Corrective action instruction': 'تعليمات الإجراء التصحيحي',
  'Target KPI': 'مؤشر الأداء المستهدف',
  'Baseline value': 'قيمة خط الأساس',
  'Target value': 'القيمة المستهدفة',
  'Issue corrective action': 'إصدار الإجراء التصحيحي',
  'Enter a valid number': 'أدخل رقمًا صحيحًا',
  'Effective': 'فعال',
  'Partially effective': 'فعال جزئيًا',
  'Ineffective': 'غير فعال',
  'Not evaluated': 'لم يتم تقييمه',
  'Before': 'قبل',
  'After': 'بعد',
  'Select a customer, farm, flock, and date':
      'اختر العميل والمزرعة والقطيع والتاريخ',
  'No active house placements': 'لا توجد عنابر نشطة لهذا القطيع',
  'Review and save valid houses': 'مراجعة وحفظ العنابر الصحيحة',
  'Pending entry': 'بانتظار الإدخال',
  'Entered': 'تم الإدخال',
  'Reviewed': 'تمت المراجعة',
  'Verified': 'تم التحقق',
  'Requires clarification': 'يحتاج توضيحًا',
  'Corrected': 'تم التصحيح',
  'Correction reason': 'سبب التصحيح',
  'Population': 'القطيع',
  'Opening birds': 'عدد الطيور أول اليوم',
  'Mortality': 'النافق',
  'Culls': 'المستبعد',
  'Closing live birds': 'عدد الطيور الحية آخر اليوم',
  'Feed and water': 'العلف والماء',
  'Feed consumed (kg)': 'العلف المستهلك (كجم)',
  'Water consumed (L)': 'الماء المستهلك (لتر)',
  'Body weight and uniformity': 'وزن الجسم والتجانس',
  'Average body weight (g)': 'متوسط وزن الجسم (جم)',
  'Birds weighed': 'عدد الطيور الموزونة',
  'Uniformity (%)': 'التجانس (%)',
  'CV (%)': 'معامل الاختلاف (%)',
  'Minimum temperature (°C)': 'أدنى درجة حرارة (°م)',
  'Maximum temperature (°C)': 'أعلى درجة حرارة (°م)',
  'Relative humidity (%)': 'الرطوبة النسبية (%)',
  'CO₂ (ppm)': 'ثاني أكسيد الكربون (جزء بالمليون)',
  'Events, causes, and sources': 'الأحداث والأسباب والمصادر',
  'No source documents attached': 'لا توجد مستندات مصدر مرفقة',
  'Add source': 'إضافة مصدر',
  'Jan': 'يناير',
  'Feb': 'فبراير',
  'Mar': 'مارس',
  'Apr': 'أبريل',
  'May': 'مايو',
  'Jun': 'يونيو',
  'Jul': 'يوليو',
  'Aug': 'أغسطس',
  'Sep': 'سبتمبر',
  'Oct': 'أكتوبر',
  'Nov': 'نوفمبر',
  'Dec': 'ديسمبر',
};
