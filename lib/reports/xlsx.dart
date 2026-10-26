import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A number shown with two decimals (money). Plain `num`s are shown as is.
class Money {
  const Money(this.value);
  final num value;
}

class XlsxSheet {
  XlsxSheet({
    required this.name,
    required this.headers,
    required this.rows,
    this.totals,
    this.widths,
  });

  final String name;
  final List<String> headers;

  /// Cells may be String, num, [Money], bool (shown Yes/No), DateTime or
  /// null.
  final List<List<Object?>> rows;

  /// Optional bold last row.
  final List<Object?>? totals;

  /// Column widths in characters; guessed from the content when omitted.
  final List<double>? widths;
}

/// Builds an .xlsx workbook (Office Open XML) without external tools.
///
/// Header rows are bold, shaded, frozen and filterable; dates are real
/// Excel dates and [Money] cells use a two-decimal number format, so
/// totals and pivots work in Excel, LibreOffice and Google Sheets.
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  if (sheets.isEmpty) throw ArgumentError('A workbook needs a sheet');
  final names = _uniqueNames(sheets.map((s) => s.name));
  final archive = Archive();
  void add(String path, String xml) =>
      archive.addFile(ArchiveFile.bytes(path, utf8.encode(xml)));

  add(
    '[Content_Types].xml',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join('\n')}
</Types>''',
  );
  add('_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');
  add(
    'xl/workbook.xml',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join('\n')}
</sheets>
<definedNames>
${[for (var i = 0; i < sheets.length; i++)
      if (sheets[i].rows.isNotEmpty) '<definedName name="_xlnm._FilterDatabase" localSheetId="$i" hidden="1">\'${_esc(names[i].replaceAll("'", "''"))}\'!\$A\$1:\$${_col(sheets[i].headers.length - 1)}\$${sheets[i].rows.length + 1}</definedName>'].join('\n')}
</definedNames>
</workbook>''',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join('\n')}
<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''',
  );
  add('xl/styles.xml', _styles);
  for (var i = 0; i < sheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', _sheet(sheets[i]));
  }
  return ZipEncoder().encodeBytes(archive);
}

// Style indexes in [_styles].
const _sText = 0;
const _sHeader = 1;
const _sDate = 2;
const _sMoney = 3;
const _sMoneyBold = 4;
const _sBold = 5;
const _sNumberBold = 6;

const _styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="2"><numFmt numFmtId="164" formatCode="#,##0.00"/><numFmt numFmtId="165" formatCode="d mmm yyyy hh:mm"/></numFmts>
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFDDEFEC"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="7">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''';

String _sheet(XlsxSheet s) {
  final cols = s.headers.length;
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
    ..write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    )
    ..write(
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" '
      'topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
      '</sheetView></sheetViews>',
    );
  final widths = s.widths ?? _guessWidths(s);
  b.write('<cols>');
  for (var c = 0; c < cols; c++) {
    b.write(
      '<col min="${c + 1}" max="${c + 1}" '
      'width="${widths[c].toStringAsFixed(1)}" customWidth="1"/>',
    );
  }
  b.write('</cols><sheetData>');
  var r = 1;
  void row(List<Object?> cells, {bool header = false, bool bold = false}) {
    b.write('<row r="$r">');
    for (var c = 0; c < cells.length && c < cols; c++) {
      b.write(_cell('${_col(c)}$r', cells[c], header: header, bold: bold));
    }
    b.write('</row>');
    r++;
  }

  row(s.headers, header: true);
  for (final cells in s.rows) {
    row(cells);
  }
  if (s.totals != null) row(s.totals!, bold: true);
  b.write('</sheetData>');
  if (s.rows.isNotEmpty) {
    b.write('<autoFilter ref="A1:${_col(cols - 1)}${s.rows.length + 1}"/>');
  }
  b.write('</worksheet>');
  return b.toString();
}

String _cell(String ref, Object? v, {bool header = false, bool bold = false}) {
  if (v == null) return '';
  if (header) return _text(ref, v.toString(), _sHeader);
  return switch (v) {
    Money(:final value) =>
      '<c r="$ref" s="${bold ? _sMoneyBold : _sMoney}"><v>$value</v></c>',
    num() => '<c r="$ref"${bold ? ' s="$_sNumberBold"' : ''}><v>$v</v></c>',
    // Yes/No reads better than TRUE/FALSE and still filters.
    bool() => _text(ref, v ? 'Yes' : 'No', bold ? _sBold : _sText),
    DateTime() => '<c r="$ref" s="$_sDate"><v>${_serial(v)}</v></c>',
    _ => _text(ref, v.toString(), bold ? _sBold : _sText),
  };
}

String _text(String ref, String t, int style) =>
    '<c r="$ref" t="inlineStr"${style == _sText ? '' : ' s="$style"'}>'
    '<is><t xml:space="preserve">${_esc(t)}</t></is></c>';

/// Excel stores dates as days since 30 Dec 1899 (local time).
String _serial(DateTime d) {
  final local = d.toLocal();
  final epoch = DateTime(1899, 12, 30);
  final days = DateTime(
    local.year,
    local.month,
    local.day,
  ).difference(epoch).inDays;
  final secs = local.hour * 3600 + local.minute * 60 + local.second;
  return (days + secs / 86400).toStringAsFixed(6);
}

/// 0 → A, 25 → Z, 26 → AA.
String _col(int i) {
  var n = i + 1;
  final b = StringBuffer();
  while (n > 0) {
    final rem = (n - 1) % 26;
    b.write(String.fromCharCode(65 + rem));
    n = (n - 1) ~/ 26;
  }
  return b.toString().split('').reversed.join();
}

String _esc(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    // XML 1.0 forbids most control characters.
    if (r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) continue;
    switch (r) {
      case 0x26:
        b.write('&amp;');
      case 0x3C:
        b.write('&lt;');
      case 0x3E:
        b.write('&gt;');
      case 0x22:
        b.write('&quot;');
      default:
        b.writeCharCode(r);
    }
  }
  return b.toString();
}

List<double> _guessWidths(XlsxSheet s) => [
  for (var c = 0; c < s.headers.length; c++)
    [
      s.headers[c].length + 2,
      for (final row in s.rows.take(200))
        if (c < row.length)
          switch (row[c]) {
            DateTime() => 17,
            Money() => 12,
            num() => 9,
            null => 4,
            final v => v.toString().length + 1,
          },
    ].fold<int>(6, (a, b) => b > a ? b : a).clamp(6, 60).toDouble(),
];

/// Sheet names: at most 31 characters, no []:*?/\, and unique.
List<String> _uniqueNames(Iterable<String> names) {
  final used = <String>{};
  return [
    for (final n in names)
      () {
        var base = n.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
        if (base.isEmpty) base = 'Sheet';
        if (base.length > 31) base = base.substring(0, 31);
        var name = base;
        var i = 2;
        while (!used.add(name.toLowerCase())) {
          final suffix = ' ($i)';
          name =
              '${base.substring(0, (31 - suffix.length).clamp(0, base.length))}$suffix';
          i++;
        }
        return name;
      }(),
  ];
}
