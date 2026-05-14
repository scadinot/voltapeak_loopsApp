//
//  XLSXBoilerplate.swift
//  voltapeak_loops
//
//  XML statiques minimaux requis par OOXML (.xlsx) :
//    * [Content_Types].xml
//    * _rels/.rels
//    * xl/workbook.xml
//    * xl/_rels/workbook.xml.rels
//
//  Une seule feuille « Resume » ciblée via rId1.
//

import Foundation

enum XLSXBoilerplate {

    static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
    </Types>
    """

    static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

    static let workbook = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
    <sheets><sheet name="Resume" sheetId="1" r:id="rId1"/></sheets>\
    </workbook>
    """

    static let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
    </Relationships>
    """

    /// Convertit un index 0-based en lettre de colonne Excel (A, B, ..., Z, AA, AB, ...).
    static func columnLetter(_ index: Int) -> String {
        var n = index
        var result = ""
        repeat {
            let r = n % 26
            result = String(UnicodeScalar(65 + r)!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    /// Échappe les caractères réservés XML dans les chaînes (texte inline).
    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Empaquette une feuille (XML déjà construit) avec les quatre fichiers OOXML
    /// communs et renvoie les octets .xlsx prêts à écrire.
    static func packageSheet(_ sheetXML: String) -> Data {
        ZIPStore.archive([
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rootRels.utf8)),
            ("xl/workbook.xml", Data(workbook.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheetXML.utf8))
        ])
    }
}
