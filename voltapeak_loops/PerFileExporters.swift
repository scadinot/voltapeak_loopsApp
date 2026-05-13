//
//  PerFileExporters.swift
//  voltapeak_loops
//
//  Exports optionnels par-fichier du dataframe nettoyé (Potential, Current),
//  reproduisant le comportement de `cleaned_df.to_csv` / `to_excel` côté Python.
//  Le signe du courant est CELUI DU FICHIER D'ORIGINE (l'inversion ne s'applique
//  qu'à la pipeline d'analyse, pas au dataframe exporté).
//

import Foundation

enum PerFileExporters {

    static func writeCleanedCSV(
        potentials: [Double],
        currents: [Double],
        to url: URL
    ) throws {
        var s = "Potential,Current\n"
        for i in 0..<potentials.count {
            s += "\(potentials[i]),\(currents[i])\n"
        }
        try s.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeCleanedXLSX(
        potentials: [Double],
        currents: [Double],
        to url: URL
    ) throws {
        var rows = ""
        rows += "<row r=\"1\">"
              + "<c r=\"A1\" t=\"inlineStr\"><is><t>Potential</t></is></c>"
              + "<c r=\"B1\" t=\"inlineStr\"><is><t>Current</t></is></c>"
              + "</row>"
        for i in 0..<potentials.count {
            let r = i + 2
            rows += "<row r=\"\(r)\">"
                  + "<c r=\"A\(r)\"><v>\(potentials[i])</v></c>"
                  + "<c r=\"B\(r)\"><v>\(currents[i])</v></c>"
                  + "</row>"
        }
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
