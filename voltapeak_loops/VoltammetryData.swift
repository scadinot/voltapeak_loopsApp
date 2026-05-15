//
//  VoltammetryData.swift
//  voltapeak_loops
//
//  Modèles partagés. Le coeur (VoltammetryPoint, VoltammetryAnalysis,
//  SWVFileConfiguration) est repris à l'identique de scadinot/voltapeakApp,
//  enrichi des conformances Sendable indispensables pour traverser TaskGroup.
//

import Foundation

/// Un point d'un voltampérogramme (Potentiel, Courant)
struct VoltammetryPoint: Identifiable, Sendable {
    let id = UUID()
    let potential: Double  // V
    let current: Double    // A
}

/// Résultat d'analyse complet d'un fichier SWV
struct VoltammetryAnalysis: Sendable {
    let rawData: [VoltammetryPoint]
    let smoothedSignal: [Double]
    let baseline: [Double]
    let correctedSignal: [Double]
    let peakPotential: Double
    let peakCurrent: Double
    let fileName: String
}

/// Configuration de lecture
struct SWVFileConfiguration: Sendable {
    enum ColumnSeparator: String, CaseIterable, Sendable {
        case tab = "\t"
        case comma = ","
        case semicolon = ";"
        case space = " "

        var displayName: String {
            switch self {
            case .tab: return "Tabulation"
            case .comma: return "Virgule"
            case .semicolon: return "Point-virgule"
            case .space: return "Espace"
            }
        }
    }

    enum DecimalSeparator: String, CaseIterable, Sendable {
        case point = "."
        case comma = ","

        var displayName: String {
            switch self {
            case .point: return "Point"
            case .comma: return "Virgule"
            }
        }
    }

    var columnSeparator: ColumnSeparator = .tab
    var decimalSeparator: DecimalSeparator = .point
    var encoding: String.Encoding = .isoLatin1
}
