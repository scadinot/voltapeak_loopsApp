//
//  SWVFileReader.swift
//  voltapeak_loops
//
//  Lecteur de fichiers SWV (deux colonnes : Potentiel, Courant).
//  Repris à l'identique de scadinot/voltapeakApp + helper `cleanedSignedData`
//  pour l'export par fichier qui doit conserver le signe original du courant
//  (l'inversion ne s'applique qu'à la pipeline d'analyse).
//

import Foundation

enum SWVFileReader {

    enum FileError: LocalizedError {
        case fileNotFound
        case invalidFormat
        case insufficientData
        case permissionDenied
        case encodingError

        var errorDescription: String? {
            switch self {
            case .fileNotFound: return "Fichier introuvable"
            case .invalidFormat: return "Format invalide : deux colonnes (Potentiel, Courant) attendues."
            case .insufficientData: return "Moins de 5 points de données."
            case .permissionDenied: return "Permissions insuffisantes pour accéder au fichier."
            case .encodingError: return "Erreur d'encodage (latin1 attendu)."
            }
        }
    }

    /// Lit un fichier SWV, ignore la 1ère ligne (entête), garde les 2 premières colonnes.
    static func readFile(at url: URL, config: SWVFileConfiguration) throws -> [VoltammetryPoint] {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw FileError.permissionDenied
        }

        let content: String
        do {
            content = try String(contentsOf: url, encoding: config.encoding)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == 257 { throw FileError.permissionDenied }
            if error.domain == NSCocoaErrorDomain && error.code == 261 { throw FileError.encodingError }
            throw error
        }

        let lines = content.components(separatedBy: .newlines)
        guard lines.count > 1 else { throw FileError.invalidFormat }

        let dataLines = lines.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var points: [VoltammetryPoint] = []
        for line in dataLines {
            let cols = line.components(separatedBy: config.columnSeparator.rawValue)
            guard cols.count >= 2 else { continue }
            let pStr = cols[0].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: config.decimalSeparator.rawValue, with: ".")
            let cStr = cols[1].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: config.decimalSeparator.rawValue, with: ".")
            if let p = Double(pStr), let c = Double(cStr), c != 0 {
                points.append(VoltammetryPoint(potential: p, current: c))
            }
        }

        guard points.count >= 5 else { throw FileError.insufficientData }
        return points
    }

    /// Tri par potentiel croissant + INVERSION du signe du courant (convention métier).
    /// Reproduit `processData` côté Python : signalValues = -dataFrame["Current"].values.
    static func processData(_ points: [VoltammetryPoint]) -> (potentials: [Double], currents: [Double]) {
        let sorted = points.sorted { $0.potential < $1.potential }
        let potentials = sorted.map { $0.potential }
        let currents = sorted.map { -$0.current }
        return (potentials, currents)
    }

    /// Variante sans inversion du signe : pour l'export par-fichier du dataframe
    /// nettoyé (Python : cleaned_df.to_csv / to_excel) qui conserve le signe original.
    static func cleanedSignedData(_ points: [VoltammetryPoint]) -> (potentials: [Double], currents: [Double]) {
        let sorted = points.sorted { $0.potential < $1.potential }
        return (sorted.map { $0.potential }, sorted.map { $0.current })
    }
}
