//
//  LoopsBatchProcessor.swift
//  voltapeak_loops
//
//  Pipeline batch pure compute, sans écriture sur disque.
//  Les exports par-fichier (PNG/CSV/XLSX) sont délégués au ViewModel
//  parce que ChartPNGRenderer doit s'exécuter sur le MainActor.
//  Le tri par potentiel est fait UNE SEULE FOIS et toutes les variantes
//  utiles (signe original / signe inversé) sont stockées dans le résultat,
//  pour éviter les retris côté ViewModel.
//

import Foundation

struct BatchOptions: Sendable {
    enum ProcessedExport: String, Sendable { case none, csv, xlsx }

    var inputFolder: URL
    var outputFolder: URL
    var config: SWVFileConfiguration
    var exportProcessed: ProcessedExport = .none
    var exportGraph: Bool = false
    var useMultiThread: Bool = true
}

/// Signaux triés par potentiel croissant, dans les deux conventions de signe :
/// - `processedCurrents` : courant inversé (= pipeline d'analyse) ;
/// - `cleanedSignedCurrents` : courant signe original (= export `cleaned_df`).
struct ProcessedSignals: Sendable {
    let potentials: [Double]
    let processedCurrents: [Double]
    let cleanedSignedCurrents: [Double]
}

struct BatchFileResult: Sendable {
    enum Status: Sendable {
        case ok(metadata: SWVFileMetadata, peakPotential: Double, peakCurrent: Double)
        case skipped
        case error(String)
    }
    let url: URL
    let fileName: String
    let status: Status
    /// Données complètes utiles aux exports par-fichier (PNG/CSV/XLSX).
    /// Présent uniquement quand `status == .ok`.
    let analysis: VoltammetryAnalysis?
    /// Présent uniquement quand `status == .ok`. Permet de réutiliser les
    /// vecteurs déjà triés sans relancer le tri côté ViewModel.
    let signals: ProcessedSignals?
}

enum LoopsBatchProcessor {

    /// Liste les fichiers .txt du dossier d'entrée (tri alphabétique).
    static func enumerateInputFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Crée le dossier de sortie. Supprime au mieux les PNG/CSV/XLSX résiduels.
    /// L'erreur de création du dossier est propagée (permissions, disque plein,
    /// volume non monté, etc.) pour que la GUI puisse la logger en rouge.
    static func cleanOutputFolder(_ folder: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let exts: Set<String> = ["png", "csv", "xlsx"]
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return
        }
        for url in urls where exts.contains(url.pathExtension.lowercased()) {
            try? fm.removeItem(at: url)
        }
    }

    /// Traite un unique fichier : lecture + SG + pic + asPLS + corrigé.
    /// Aucune écriture disque ici — le ViewModel se charge des exports
    /// par-fichier sur le MainActor.
    static func processOne(url: URL, options: BatchOptions) -> BatchFileResult {
        let fileName = url.lastPathComponent

        guard let meta = FileNameParser.parse(fileName) else {
            return BatchFileResult(
                url: url, fileName: fileName,
                status: .skipped, analysis: nil, signals: nil
            )
        }

        do {
            let raw = try SWVFileReader.readFile(at: url, config: options.config)

            // Tri unique partagé par toute la suite (analyse + exports).
            let sorted = raw.sorted { $0.potential < $1.potential }
            let potentials = sorted.map { $0.potential }
            let cleanedCurrents = sorted.map { $0.current }        // signe original
            let processedCurrents = cleanedCurrents.map { -$0 }    // pipeline d'analyse

            // 1. Lissage Savitzky-Golay (scipy : window=11, order=2)
            let smoothed = SavitzkyGolay.filter(processedCurrents, windowLength: 11, polynomialOrder: 2)

            // 2. Pic brut (filtre de pente + marge 10%)
            let (peakV, _) = SignalProcessing.detectPeak(
                signal: smoothed, potentials: potentials,
                marginRatio: 0.10, maxSlope: 500
            )

            // 3. Baseline asPLS avec exclusion 3% autour du pic
            let n = smoothed.count
            let lam = 1e3 * Double(n * n)
            let span = potentials.last! - potentials.first!
            let exclusionWidth = 0.03 * span
            var weights = [Double](repeating: 1.0, count: n)
            for i in 0..<n where potentials[i] > peakV - exclusionWidth
                                && potentials[i] < peakV + exclusionWidth {
                weights[i] = 0.001
            }
            let baseline = WhittakerASPLS.aspls(
                y: smoothed, lam: lam, diffOrder: 2,
                maxIter: 25, tol: 1e-2, weights: weights
            )

            // 4. Signal corrigé + pic final
            let corrected = zip(smoothed, baseline).map { $0 - $1 }
            let (correctedPeakV, correctedPeakC) = SignalProcessing.detectPeak(
                signal: corrected, potentials: potentials,
                marginRatio: 0.10, maxSlope: 500
            )

            let analysis = VoltammetryAnalysis(
                rawData: raw,
                smoothedSignal: smoothed,
                baseline: baseline,
                correctedSignal: corrected,
                peakPotential: correctedPeakV,
                peakCurrent: correctedPeakC,
                fileName: fileName
            )
            let signals = ProcessedSignals(
                potentials: potentials,
                processedCurrents: processedCurrents,
                cleanedSignedCurrents: cleanedCurrents
            )

            return BatchFileResult(
                url: url,
                fileName: fileName,
                status: .ok(metadata: meta,
                            peakPotential: correctedPeakV,
                            peakCurrent: correctedPeakC),
                analysis: analysis,
                signals: signals
            )
        } catch {
            return BatchFileResult(
                url: url, fileName: fileName,
                status: .error(error.localizedDescription),
                analysis: nil, signals: nil
            )
        }
    }
}
