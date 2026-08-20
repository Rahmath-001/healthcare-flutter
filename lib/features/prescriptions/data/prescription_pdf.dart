import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../shared/formatters.dart';
import '../domain/prescription.dart';

/// Renders a prescription to PDF (FR-RX-003).
///
/// IMPORTANT: this is a stand-in. In production the PDF is generated
/// **server-side** and stored WORM, because a prescription is a legal document:
/// it must be byte-identical for everyone who views it, server-attested, and
/// verifiable by a pharmacy against the issuing record. A device-generated file
/// is none of those things.
///
/// This exists so the download-and-share path is real and testable before the
/// API is deployed. When `GET /v1/prescriptions/{id}/pdf` lands, this class is
/// replaced by a download, not extended.
abstract final class PrescriptionPdf {
  static Future<List<int>> build(Prescription p) async {
    final doc = pw.Document(
      title: 'Prescription ${p.verificationCode}',
      author: p.providerName,
      theme: await _theme(),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(p),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 12),
            _patientRow(p),
            pw.SizedBox(height: 20),
            if (p.diagnosis != null) ...[
              _sectionTitle('Diagnosis'),
              pw.Text(p.diagnosis!),
              pw.SizedBox(height: 16),
            ],
            _sectionTitle('Rx'),
            pw.SizedBox(height: 6),
            _medicinesTable(p),
            if (p.advice != null) ...[
              pw.SizedBox(height: 16),
              _sectionTitle('Advice'),
              pw.Text(p.advice!),
            ],
            pw.Spacer(),
            _footer(p),
          ],
        ),
      ),
    );

    return doc.save();
  }

  /// The PDF built-ins (Helvetica) are Latin-1 only, so an Indian patient name
  /// in Devanagari, Tamil or Bengali would render as blank boxes. Noto Sans
  /// covers those scripts.
  ///
  /// The font is fetched and cached by the printing package. If that fails —
  /// offline, most likely — the document still renders with the built-in font
  /// rather than failing outright; a Latin-only prescription beats no
  /// prescription.
  static Future<pw.ThemeData?> _theme() async {
    try {
      return pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Falling back to built-in PDF font: $e');
      }
      return null;
    }
  }

  static pw.Widget _header(Prescription p) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                p.providerName,
                style: const pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(p.providerQualification,
                  style: const pw.TextStyle(fontSize: 10)),
              // The council registration number is mandatory on every
              // prescription under NMC rules.
              pw.Text(
                'Reg. No. ${p.providerRegistrationNumber}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('MiDoctor',
                  style: const pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal700,
                  )),
              pw.Text('Teleconsultation',
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ],
      );

  static pw.Widget _patientRow(Prescription p) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Patient', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(p.patientName,
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('${p.patientAge} / ${p.patientGender}',
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Issued', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(Fmt.date(p.issuedAt),
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(p.verificationCode,
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ],
      );

  static pw.Widget _sectionTitle(String text) => pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      );

  static pw.Widget _medicinesTable(Prescription p) =>
      pw.TableHelper.fromTextArray(
        headers: const ['#', 'Medicine', 'Dosage', 'Duration', 'Instructions'],
        cellStyle: const pw.TextStyle(fontSize: 10),
        headerStyle: const pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellAlignment: pw.Alignment.centerLeft,
        columnWidths: {
          0: const pw.FixedColumnWidth(20),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(2),
          4: const pw.FlexColumnWidth(3),
        },
        data: [
          for (var i = 0; i < p.items.length; i++)
            [
              '${i + 1}',
              '${p.items[i].drugName} ${p.items[i].strength}\n'
                  '(${p.items[i].genericName})',
              p.items[i].frequency,
              '${p.items[i].durationDays} day'
                  '${p.items[i].durationDays == 1 ? '' : 's'}',
              p.items[i].instructions ?? '-',
            ],
        ],
      );

  static pw.Widget _footer(Prescription p) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Divider(),
          pw.SizedBox(height: 6),
          pw.Text(
            'Verification code: ${p.verificationCode}',
            style:
                const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'A pharmacist can confirm this prescription with the code above. '
            'Retained until ${Fmt.date(p.retainedUntil)}.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Issued via a MiDoctor teleconsultation. This consultation was not '
            'recorded.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      );
}
