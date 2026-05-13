//
//  AggregatedXLSXWriter.swift
//  voltapeak_loops
//
//  Classeur final : un onglet hiérarchique (Canal / Variante / Mesure) avec
//  une ligne par itération (loops) ou par concentration (dosage).
//  Les deux premières lignes d'en-tête (Canal et Variante) sont fusionnées
//  sur les deux colonnes (Tension, Courant) qui suivent.
//

import Foundation

enum AggregatedXLSXWriter {

    struct Key: Hashable, Sendable {
        let canal: String      // "C09"
        let variante: String   // "05"
    }
    struct Measurement: Sendable {
        let tension: Double
        let courant: Double
    }
    struct Row: Sendable {
        let iterationLabel: String
        let iterationKey: Int
        var measurements: [Key: Measurement]
    }

    /// Construit le .xlsx final et renvoie ses octets.
    static func build(rows: [Row], format: FileNameFormat) -> Data {
        // Clés (canal, variante) triées : canal numérique d'abord, puis variante.
        var keysSet = Set<Key>()
        for r in rows { keysSet.formUnion(r.measurements.keys) }
        let sortedKeys = keysSet.sorted { a, b in
            let ca = Int(a.canal.dropFirst()) ?? .max
            let cb = Int(b.canal.dropFirst()) ?? .max
            if ca != cb { return ca < cb }
            let va = Int(a.variante) ?? .max
            let vb = Int(b.variante) ?? .max
            return va < vb
        }

        let indexLabel = (format == .dosage) ? "Concentration" : "Itération"
        let sortedRows = rows.sorted { $0.iterationKey < $1.iterationKey }

        let sheet = buildSheet(
            indexLabel: indexLabel,
            sortedKeys: sortedKeys,
            rows: sortedRows
        )
        return XLSXBoilerplate.packageSheet(sheet)
    }

    private static func buildSheet(
        indexLabel: String,
        sortedKeys: [Key],
        rows: [Row]
    ) -> String {
        let col = XLSXBoilerplate.columnLetter
        let esc = XLSXBoilerplate.xmlEscape

        // Ligne 1 : canal sur la cellule de gauche de chaque paire
        var row1 = "<row r=\"1\">"
        row1 += "<c r=\"A1\" t=\"inlineStr\"><is><t></t></is></c>"
        for (i, k) in sortedKeys.enumerated() {
            let l = col(1 + i * 2)
            row1 += "<c r=\"\(l)1\" t=\"inlineStr\"><is><t>\(esc(k.canal))</t></is></c>"
        }
        row1 += "</row>"

        // Ligne 2 : variante sur la cellule de gauche de chaque paire
        var row2 = "<row r=\"2\">"
        row2 += "<c r=\"A2\" t=\"inlineStr\"><is><t></t></is></c>"
        for (i, k) in sortedKeys.enumerated() {
            let l = col(1 + i * 2)
            row2 += "<c r=\"\(l)2\" t=\"inlineStr\"><is><t>\(esc(k.variante))</t></is></c>"
        }
        row2 += "</row>"

        // Ligne 3 : index_label puis alternance Tension / Courant
        var row3 = "<row r=\"3\">"
        row3 += "<c r=\"A3\" t=\"inlineStr\"><is><t>\(esc(indexLabel))</t></is></c>"
        for i in 0..<sortedKeys.count {
            let l = col(1 + i * 2)
            let r = col(2 + i * 2)
            row3 += "<c r=\"\(l)3\" t=\"inlineStr\"><is><t>Tension (V)</t></is></c>"
            row3 += "<c r=\"\(r)3\" t=\"inlineStr\"><is><t>Courant (A)</t></is></c>"
        }
        row3 += "</row>"

        // Lignes de données : on accumule chaque <row> dans un tableau puis on
        // assemble avec joined(), pour éviter les copies répétées d'une grande
        // String quand le nombre de fichiers/itérations devient important.
        var dataRowParts: [String] = []
        dataRowParts.reserveCapacity(rows.count)
        for (idx, r) in rows.enumerated() {
            let n = idx + 4
            var rowXML = "<row r=\"\(n)\">"
            rowXML += "<c r=\"A\(n)\" t=\"inlineStr\"><is><t>\(esc(r.iterationLabel))</t></is></c>"
            for (i, k) in sortedKeys.enumerated() {
                let l = col(1 + i * 2)
                let rc = col(2 + i * 2)
                if let m = r.measurements[k] {
                    rowXML += "<c r=\"\(l)\(n)\"><v>\(m.tension)</v></c>"
                    rowXML += "<c r=\"\(rc)\(n)\"><v>\(m.courant)</v></c>"
                }
            }
            rowXML += "</row>"
            dataRowParts.append(rowXML)
        }
        let dataRows = dataRowParts.joined()

        // Fusion des cellules des lignes 1 et 2 sur chaque paire de colonnes
        var merges = ""
        for i in 0..<sortedKeys.count {
            let l = col(1 + i * 2)
            let r = col(2 + i * 2)
            merges += "<mergeCell ref=\"\(l)1:\(r)1\"/>"
            merges += "<mergeCell ref=\"\(l)2:\(r)2\"/>"
        }
        let mergesXML = sortedKeys.isEmpty
            ? ""
            : "<mergeCells count=\"\(sortedKeys.count * 2)\">\(merges)</mergeCells>"

        // mergeCells doit suivre sheetData dans l'ordre OOXML.
        let body = "<sheetData>\(row1)\(row2)\(row3)\(dataRows)</sheetData>\(mergesXML)"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\(body)</worksheet>
        """
    }
}
