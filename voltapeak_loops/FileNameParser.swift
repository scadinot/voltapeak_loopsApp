//
//  FileNameParser.swift
//  voltapeak_loops
//
//  Détection des deux formats de noms supportés par voltapeak_loops :
//    * loops  : *_XX_SWV_CYY_loopZZ.txt   (variante XX, canal CYY, itération ZZ)
//    * dosage : ZZ_<concentration>_XX_SWV_CYY.txt   (ordre ZZ, concentration libre)
//
//  Les expressions régulières sont reprises à l'identique du script Python.
//  Le format loops est testé en premier (plus restrictif), dosage sert de fallback.
//  Les regex sont insensibles à la casse, en cohérence avec l'énumération des
//  fichiers d'entrée qui accepte déjà `.TXT`/`.Txt`.
//

import Foundation

enum FileNameFormat: String, Sendable {
    case loops
    case dosage
}

struct SWVFileMetadata: Sendable {
    let format: FileNameFormat
    let iterationKey: Int
    let iterationLabel: String
    let variante: String
    let canal: String
}

enum FileNameParser {

    private static let loopsRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #".*?_([0-9]{2})_SWV_(C[0-9]{2})_loop([0-9]+)\.txt$"#,
            options: [.caseInsensitive]
        )
    }()

    private static let dosageRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"^([0-9]+)_([^_]+)_([0-9]{2})_SWV_(C[0-9]{2})\.txt$"#,
            options: [.caseInsensitive]
        )
    }()

    static func parse(_ fileName: String) -> SWVFileMetadata? {
        let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)

        if let m = loopsRegex.firstMatch(in: fileName, range: range),
           let variante = capture(m, at: 1, in: fileName),
           let canal    = capture(m, at: 2, in: fileName),
           let loop     = capture(m, at: 3, in: fileName),
           let loopKey  = Int(loop) {
            return SWVFileMetadata(
                format: .loops,
                iterationKey: loopKey,
                iterationLabel: "loop\(loop)",
                variante: variante,
                canal: canal
            )
        }

        if let m = dosageRegex.firstMatch(in: fileName, range: range),
           let ordre         = capture(m, at: 1, in: fileName),
           let concentration = capture(m, at: 2, in: fileName),
           let variante      = capture(m, at: 3, in: fileName),
           let canal         = capture(m, at: 4, in: fileName),
           let ordreKey      = Int(ordre) {
            return SWVFileMetadata(
                format: .dosage,
                iterationKey: ordreKey,
                iterationLabel: concentration,
                variante: variante,
                canal: canal
            )
        }

        return nil
    }

    private static func capture(_ m: NSTextCheckingResult, at idx: Int, in s: String) -> String? {
        let r = m.range(at: idx)
        guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
        return String(s[range])
    }
}
