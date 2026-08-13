import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';

void main() {
  test('Arabic catalog covers Home and Dashboard operational labels', () {
    final l10n = AppLocalizations(const Locale('ar'));

    const labels = {
      'Last audit': 'آخر زيارة',
      'Active flocks': 'القطعان النشطة',
      'Audits this month': 'زيارات هذا الشهر',
      'Quick Actions': 'إجراءات سريعة',
      'New Audit': 'زيارة جديدة',
      'Recent Audits': 'آخر الزيارات',
      'Active visit': 'زيارة نشطة',
      'Completed visit': 'زيارة مكتملة',
      "Today's Focus": 'تركيز اليوم',
      'Continue': 'متابعة',
      'active audits': 'زيارات نشطة',
      'Attention': 'تنبيه',
      'items to check': 'بنود تحتاج مراجعة',
      'Ready': 'جاهز',
      'All customers': 'كل العملاء',
      'All flocks': 'كل القطعان',
      'Egg Storage & Handling': 'تخزين وتداول البيض',
      'Storage temps · EST · shell · turning · 9-point':
          'حرارة التخزين · حرارة سطح البيض · القشرة · التقليب · 9 نقاط',
      'Storage checklist': 'قائمة التخزين',
      'Upside score': 'درجة البيض المقلوب',
      'Shell UV': 'فحص القشرة بالأشعة',
      'Egg Quality': 'جودة البيض',
      'Cumulative': 'تراكمي',
      'Incremental': 'آخر زيارة',
      'CRITICAL — ACTION REQUIRED': 'حرج — مطلوب إجراء',
      'WATCH — NEAR THRESHOLD': 'متابعة — قريب من الحد',
      'EST Average': 'متوسط حرارة سطح البيض',
      'CRITICAL': 'حرج',
      'Pooled': 'إجمالي',
      'Target 19-21°C': 'المستهدف 19-21°C',
      'Below target band — warm storage toward range.':
          'أقل من المستهدف — ارفع حرارة التخزين تدريجيًا للنطاق المناسب.',
      '%Egg CV': 'معامل اختلاف وزن البيض %',
      'Limit ≤ 8.0%': 'الحد ≤ 8.0%',
      'Weight spread high — review grading.':
          'تفاوت الوزن مرتفع — راجع فرز وتدريج البيض.',
      'EGG QUALITY': 'جودة البيض',
      '3 in target': '3 ضمن المستهدف',
    };

    for (final entry in labels.entries) {
      expect(l10n.translate(entry.key), entry.value, reason: entry.key);
    }
  });

  test('Arabic catalog covers fixed app-wide screen copy', () {
    final l10n = AppLocalizations(const Locale('ar'));

    const labels = {
      'User Access': 'صلاحيات المستخدمين',
      'No users found.': 'لا يوجد مستخدمون.',
      'Role': 'الدور',
      'Status': 'الحالة',
      'Belongs to customer': 'تابع للعميل',
      'Select Customer': 'اختر العميل',
      'Select Stations': 'اختر المحطات',
      'Visit order': 'ترتيب الزيارة',
      'Filter visits': 'تصفية الزيارات',
      'Search customer, hatchery, flock, breed…':
          'ابحث بالعميل أو معمل التفريخ أو القطيع أو السلالة…',
      'Clear all': 'مسح الكل',
      'Clear station?': 'مسح بيانات المحطة؟',
      'Fields and saved rows will be removed.':
          'سيتم حذف الحقول والصفوف المحفوظة.',
      'Chick quality': 'جودة الكتاكيت',
      'House scope': 'نطاق العنابر',
      'Machine scope': 'نطاق الماكينات',
      'Tray scope': 'نطاق الصواني',
      'Setpoint (°F)': 'درجة الضبط (°F)',
      'Incubation Age (days)': 'عمر التحضين (أيام)',
      'Govee device settings': 'إعدادات جهاز Govee',
      'Search customer, hatchery, place…':
          'ابحث بالعميل أو معمل التفريخ أو المكان…',
      'Sync & Offline': 'المزامنة والعمل بدون اتصال',
      'Dismiss all': 'إخفاء الكل',
      'Synced from another device': 'تمت المزامنة من جهاز آخر',
      'That audit is no longer available.': 'هذه الزيارة لم تعد متاحة.',
      'Mark all reviewed': 'تمييز الكل كمراجع',
      'All clear': 'كل شيء تمام',
      'Cloud not configured': 'المزامنة السحابية غير مفعلة',
      'Local database ready': 'قاعدة البيانات المحلية جاهزة',
      'Syncing with cloud': 'جاري المزامنة مع السحابة',
      'Sync error — tap Retry': 'خطأ في المزامنة — اضغط إعادة المحاولة',
      'Checking cloud connection': 'جارٍ التحقق من الاتصال بالسحابة',
      'Home data could not be loaded.': 'تعذر تحميل بيانات الصفحة الرئيسية.',
      'No open conflicts': 'لا توجد تعارضات مفتوحة',
      'Local edits won over cloud on these rows. Confirm or restore.':
          'التعديلات المحلية أحدث من السحابة في هذه الصفوف. راجعها أو استرجعها.',
      'These rows were edited on this device after the cloud copy. Local edits were kept. Mark reviewed once confirmed.':
          'تم تعديل هذه الصفوف على هذا الجهاز بعد نسخة السحابة. تم الاحتفاظ بالتعديلات المحلية. حددها كمراجعة بعد التأكد.',
      'All': 'الكل',
      'Clear': 'مسح',
      'Parameter': 'البند',
      'Actual': 'الفعلي',
      'Eggs': 'بيض',
      'Egg Storage': 'تخزين البيض',
      'Chick Weights': 'أوزان الكتاكيت',
      'Fresh Breakout': 'فحص البيض الطازج',
      'Candled Breakout': 'فحص البيض بعد التحضين',
      'Residue Breakout': 'فحص متبقيات الفقس',
      'Setter Optimizing': 'ضبط ماكينة التحضين',
      'Hatcher Optimizing': 'ضبط ماكينة الفقس',
      'Govee Environmental Readings': 'قراءات البيئة من Govee',
      'Continuous temp & RH · monitored places · 24h captures':
          'حرارة ورطوبة مستمرة · أماكن متابعة · تسجيلات 24 ساعة',
      'No saved Govee readings yet': 'لا توجد قراءات Govee محفوظة بعد',
      'No Govee captures to chart yet.':
          'لا توجد تسجيلات Govee كافية للرسم بعد.',
      'Nothing to chart for this metric.': 'لا توجد بيانات كافية لهذا المؤشر.',
      'House': 'العنبر',
      'Machine': 'الماكينة',
      'Trolley': 'العربة',
      'Tray': 'الصينية',
      'Sample': 'العينة',
      'Review': 'مراجعة',
      'Clear old logs': 'مسح السجلات القديمة',
      'Add new customer': 'إضافة عميل جديد',
      'Add new hatchery': 'إضافة معمل تفريخ جديد',
    };

    for (final entry in labels.entries) {
      expect(l10n.translate(entry.key), entry.value, reason: entry.key);
    }
  });

  test('Arabic catalog preserves entered values in dynamic fixed copy', () {
    final l10n = AppLocalizations(const Locale('ar'));

    expect(
      l10n.translate('Add a flock before starting audits for Cairo Farm.'),
      'أضف قطيعًا قبل بدء الزيارات لـ Cairo Farm.',
    );
    expect(
      l10n.translate('Saved 9 CVT readings.'),
      'تم حفظ 9 قراءة حرارة جسم الكتكوت.',
    );
    expect(
      l10n.translate('Sync could not finish: timeout'),
      'تعذر إكمال المزامنة: timeout',
    );
    expect(
      l10n.translate('3 customer setup incomplete'),
      'إعداد 3 عملاء غير مكتمل',
    );
    expect(
      l10n.translate('2 hatchery record missing'),
      'بيانات معمل التفريخ ناقصة لـ 2 عميل',
    );
    expect(
      l10n.translate('4 estimated flock age'),
      'عمر القطيع تقديري لـ 4 عملاء',
    );
    expect(l10n.translate('5 sync conflict'), '5 تعارضات مزامنة');
    expect(l10n.translate('No Hatch data yet'), 'لا توجد بيانات فقس بعد');
    expect(l10n.translate('12 eggs'), '12 بيضة');
    expect(l10n.translate('7 records'), '7 سجلات');
    expect(
      l10n.translate('Delete flock "Flock A"? This cannot be undone.'),
      'هل تريد حذف القطيع "Flock A"؟ لا يمكن التراجع عن ذلك.',
    );
    expect(
      l10n.translate(
        'Remove hatchery "Hatchery One"? Existing audits will keep their saved hatchery reference.',
      ),
      'هل تريد إزالة معمل التفريخ "Hatchery One"؟ ستحتفظ الزيارات السابقة بمرجع المعمل المحفوظ.',
    );
    expect(
      l10n.translate(
        'Add separate samples and compare their results side by side.\n'
        'Each sample is entered and saved separately.',
      ),
      'أضف عينات مستقلة وقارن نتائجها جنبًا إلى جنب.\n'
      'تُدخل كل عينة وتُحفظ بصورة مستقلة.',
    );
    expect(l10n.translate('Visit 3 July 2026'), 'زيارة 3 July 2026');
    expect(l10n.translate('3 of 5 stations completed'), 'اكتملت 3 من 5 محطة');
    expect(l10n.translate('12 weeks'), '12 أسبوعًا');
    expect(l10n.translate('7m ago'), 'منذ 7 دقيقة');
    expect(l10n.translate('Tray 2'), 'الصينية 2');
    expect(l10n.translate('Pool 1'), 'العينة الإجمالية 1');
    expect(
      l10n.translate('Add a hatchery for Cairo Farm to start recording.'),
      'أضف معمل تفريخ لـ Cairo Farm لبدء التسجيل.',
    );
    expect(
      l10n.translate('Saved 9 EST readings.'),
      'تم حفظ 9 قراءة حرارة سطح البيض.',
    );
    expect(
      l10n.translate('Affected: 12 eggs (8.0%)'),
      'المتأثر: 12 بيضة (8.0%)',
    );
    expect(l10n.translate('Flock: Cairo Farm A'), 'القطيع: Cairo Farm A');
  });

  test('Arabic catalog covers dashboard intelligence and quality labels', () {
    final l10n = AppLocalizations(const Locale('ar'));

    expect(l10n.translate('What needs attention'), 'ما يحتاج إلى تدخل');
    expect(
      l10n.translate('Ratio of totals'),
      'نسبة مجموع البسط إلى مجموع المقام',
    );
    expect(l10n.translate('Sample-weighted average'), 'متوسط مرجح بحجم العينة');
    expect(l10n.translate('85% data coverage'), 'اكتمال البيانات 85%');
    expect(
      l10n.translate('75% photo coverage (3/4)'),
      'اكتمال توثيق الصور 75% (3/4)',
    );
    expect(l10n.translate('4 missing measurements'), '4 قياسًا ناقصًا');
    expect(l10n.translate('Latest capture 3 h ago'), 'أحدث تسجيل منذ 3 ساعة');
    expect(
      l10n.translate(
        '2 stale environmental captures are shown as history and excluded from active alerts.',
      ),
      'توجد 2 تسجيلات بيئية قديمة؛ تُعرض كسجل تاريخي ولا تدخل ضمن التنبيهات النشطة.',
    );
  });
}
