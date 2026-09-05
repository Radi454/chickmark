/// Renders a [BreederReportComposition] to PDF and hands it to the OS
/// print/share sheet (breeder-flock-performance ticket 19, design section
/// 5.3: "the consolidated review table is the same view used for printing
/// and export"). Nothing here computes a report value — every string
/// printed is already formatted by [buildBreederReportComposition]; this
/// file is purely a rendering backend, the PDF counterpart to the on-screen
/// Flutter `DataTable`s in `BreederDailyReportReviewScreen`.
///
/// Nothing already in this app generates a PDF (the lab-analysis screen
/// only attaches/opens externally-produced PDFs — see
/// `lib/features/lab_analysis/screens/lab_analysis_screen.dart`), so this
/// uses the `pdf`/`printing` packages, the standard Flutter pair for
/// building a document and handing it to the platform print/share sheet.
/// `Printing.layoutPdf` opens the OS print dialog (which itself offers
/// "Save as PDF"/share on every supported platform), covering both
/// "printable" and "exportable" from a single entry point.
///
/// Arabic text needs a font with Arabic glyphs — the default PDF core
/// fonts (Helvetica) have none — so this bundles Noto Naskh Arabic
/// (`assets/fonts/NotoNaskhArabic-Regular.ttf`, SIL Open Font License) as a
/// font fallback, keeping the default Latin font for everything else. This
/// keeps printing fully offline, matching the rest of this offline-first
/// app: no runtime font download.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'breeder_report_composition.dart';

/// Builds the PDF document for [composition]. [rtl] selects Arabic
/// right-to-left layout; [translate] resolves every English translation
/// key used by [BreederReportComposition] (header labels, column headers,
/// state labels) the same way `context.tr` does on screen — this file has
/// no `BuildContext`, so the caller supplies the resolved strings.
class BreederReportPdfExport {
  const BreederReportPdfExport();

  Future<pw.Document> build({
    required BreederReportComposition composition,
    required String flockLabel,
    required String reportDateLabel,
    required bool rtl,
    required String Function(String key) translate,
  }) async {
    final arabicFontData = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final arabicFont = pw.Font.ttf(arabicFontData);
    final direction = rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(fontFallback: [arabicFont]),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: direction,
        build: (context) => [
          pw.Directionality(
            textDirection: direction,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  '$flockLabel — $reportDateLabel',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textDirection: direction,
                ),
                pw.SizedBox(height: 4),
                _statusLine(composition, translate, direction),
                pw.SizedBox(height: 10),
                _headerBlock(composition, translate, direction),
                pw.SizedBox(height: 12),
                _table(composition.femaleMovements, rtl, translate, context),
                pw.SizedBox(height: 10),
                _table(composition.maleMovements, rtl, translate, context),
                if (composition.eggProduction != null) ...[
                  pw.SizedBox(height: 10),
                  _table(composition.eggProduction!, rtl, translate, context),
                ],
                if (composition.eggInventory != null) ...[
                  pw.SizedBox(height: 10),
                  _table(composition.eggInventory!, rtl, translate, context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return doc;
  }

  /// Opens the OS print/export sheet for [composition]. On every supported
  /// platform this dialog itself offers "Save as PDF"/share, so one call
  /// covers both printing and exporting (design section 5.3/11).
  Future<void> printOrShare({
    required BreederReportComposition composition,
    required String flockLabel,
    required String reportDateLabel,
    required bool rtl,
    required String Function(String key) translate,
  }) async {
    final doc = await build(
      composition: composition,
      flockLabel: flockLabel,
      reportDateLabel: reportDateLabel,
      rtl: rtl,
      translate: translate,
    );
    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: 'breeder-daily-report-$reportDateLabel.pdf',
    );
  }

  pw.Widget _statusLine(
    BreederReportComposition composition,
    String Function(String) translate,
    pw.TextDirection direction,
  ) {
    final parts = <String>[
      translate(composition.stateLabel),
      if (composition.isApproved)
        '${translate('Revision')} ${composition.revisionNumber}',
    ];
    return pw.Text(
      parts.join(' · '),
      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      textDirection: direction,
    );
  }

  pw.Widget _headerBlock(
    BreederReportComposition composition,
    String Function(String) translate,
    pw.TextDirection direction,
  ) {
    return pw.Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        for (final field in composition.headerFields)
          pw.Container(
            constraints: const pw.BoxConstraints(minWidth: 110),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  translate(field.label),
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                  textDirection: direction,
                ),
                pw.Text(
                  field.value,
                  style: const pw.TextStyle(fontSize: 10),
                  textDirection: direction,
                ),
              ],
            ),
          ),
      ],
    );
  }

  pw.Widget _table(
    BreederReportTable table,
    bool rtl,
    String Function(String) translate,
    pw.Context context,
  ) {
    final direction = rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final headers = [
      for (final c in table.columnsFor(rtl: rtl)) translate(c),
    ];
    final rows = table.rowsFor(rtl: rtl);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          translate(table.title),
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          textDirection: direction,
        ),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          context: context,
          headers: headers,
          data: rows,
          headerDirection: direction,
          tableDirection: direction,
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          cellAlignment: pw.Alignment.center,
          headerAlignment: pw.Alignment.center,
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 3,
          ),
        ),
      ],
    );
  }
}
