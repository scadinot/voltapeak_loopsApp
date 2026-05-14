//
//  PerFileExporters.swift
//  voltapeak_loops
//
//  Exports optionnels par-fichier du dataframe nettoyé (Potential, Current),
//  reproduisant le comportement de `cleaned_df.to_csv` / `to_excel` côté Python.
//  Le signe du courant est CELUI DU FICHIER D'ORIGINE (l'inversion ne s'applique
//  qu'à la pipeline d'analyse, pas au dataframe exporté).
//
//  Les fragments XML/CSV sont accumulés dans un tableau de chaînes puis
//  concaténés en une seule passe via `joined()` afin d'éviter les copies
//  successives d'une grande String (O(n²)).
//

import Foundation

enum PerFileExporters {

    static func writeCleanedCSV(
        potentials: [Double],
        currents: [Double],
        to url: URL
    ) throws {
        var lines: [String] = []
        lines.reserveCapacity(potentials.count + 2)
        lines.append("Potential,Current")
        for i in 0..<potentials.count {
            lines.append("\(potentials[i]),\(currents[i])")
        }
        lines.append("")  // newline final
        let csv = lines.joined(separator: "\n")
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeCleanedXLSX(
        potentials: [Double],
        currents: [Double],
        to url: URL
    ) throws {
        var fragments: [String] = []
        fragments.reserveCapacity(potentials.count + 1)
        fragments.append(
            "<row r=\"1\">" +
            "<c r=\"A1\" t=\"inlineStr\"><is><t>Potential</t></is></c>" +
            "<c r=\"B1\" t=\"inlineStr\"><is><t>Current</t></is></c>" +
            "</row>"
        )
        for i in 0..<potentials.count {
            let r = i + 2
            fragments.append(
                "<row r=\"\(r)\">" +
                "<c r=\"A\(r)\"><v>\(potentials[i])</v></c>" +
                "<c r=\"B\(r)\"><v>\(currents[i])</v></c>" +
                "</row>"
            )
        }
        let rows = fragments.joined()
        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <sheetData>\(rows)</sheetData>\
        </worksheet>
        """
        let data = XLSXBoilerplate.packageSheet(sheet)
        try data.write(to: url)
    }
}
