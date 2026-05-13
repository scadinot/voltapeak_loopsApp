//
//  VoltapeakLoopsViewModel.swift
//  voltapeak_loops
//
//  Orchestration de l'analyse batch :
//  - paramètres saisis depuis la GUI,
//  - parallélisme via TaskGroup (un Task par fichier) ou Task détachée
//    séquentielle (utile au débogage, équivalent du bouton de la GUI Python),
//  - exports par-fichier (PNG/CSV/XLSX) sur le MainActor après chaque calcul,
//  - agrégation finale puis génération du .xlsx final.
//

import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class VoltapeakLoopsViewModel {

    var inputFolder: URL?
    var config = SWVFileConfiguration()
    var exportProcessed: BatchOptions.ProcessedExport = .none
    var exportGraph: Bool = false
    var useMultiThread: Bool = true

    var logLines: [LogLine] = []
    var progressCurrent: Int = 0
    var progressTotal: Int = 0
    var isRunning: Bool = false
    var canOpenResults: Bool = false

    private var lastOutputFolder: URL?

    struct LogLine: Identifiable, Sendable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    // MARK: - GUI actions

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Sélectionnez le dossier contenant les fichiers .txt"
        if let last = inputFolder { panel.directoryURL = last }
        if panel.runModal() == .OK, let url = panel.url {
            inputFolder = url
        }
    }

    func openResultsFolder() {
        guard let url = lastOutputFolder else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Batch

    func run() async {
        guard let input = inputFolder else {
            appendLog("Veuillez sélectionner un dossier valide.", isError: true)
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDir), isDir.boolValue else {
            appendLog("Le dossier sélectionné n'existe pas ou n'est pas un répertoire.", isError: true)
            return
        }

        isRunning = true
        canOpenResults = false
        clearLog()
        progressCurrent = 0

        let folderName = input.lastPathComponent
        let outputFolder = input.deletingLastPathComponent()
            .appendingPathComponent("\(folderName) (results)")

        appendLog("Nettoyage du dossier de sortie...")
        LoopsBatchProcessor.cleanOutputFolder(outputFolder)

        let files = LoopsBatchProcessor.enumerateInputFiles(in: input)
        progressTotal = files.count

        guard !files.isEmpty else {
            appendLog("Aucun fichier .txt trouvé dans le dossier sélectionné.", isError: true)
            isRunning = false
            return
        }

        let options = BatchOptions(
            inputFolder: input,
            outputFolder: outputFolder,
            config: config,
            exportProcessed: exportProcessed,
            exportGraph: exportGraph,
            useMultiThread: useMultiThread
        )

        let start = Date()
        var results: [BatchFileResult] = []

        if useMultiThread {
            results = await withTaskGroup(
                of: BatchFileResult.self,
                returning: [BatchFileResult].self
            ) { group in
                for url in files {
                    group.addTask(priority: .utility) {
                        LoopsBatchProcessor.processOne(url: url, options: options)
                    }
                }
                var collected: [BatchFileResult] = []
                collected.reserveCapacity(files.count)
                for await r in group {
                    collected.append(r)
                    didFinish(file: r, options: options)
                }
                return collected
            }
        } else {
            // Mode séquentiel : on garde une Task détachée par fichier pour
            // exécuter le calcul hors MainActor, sans bloquer l'UI ni le journal
            // entre les fichiers (l'UI peut se rafraîchir entre chaque itération).
            for url in files {
                let r = await Task.detached(priority: .utility) {
                    LoopsBatchProcessor.processOne(url: url, options: options)
                }.value
                results.append(r)
                didFinish(file: r, options: options)
            }
        }

        let elapsed = Date().timeIntervalSince(start)

        let okResults = results.compactMap { r -> (BatchFileResult, SWVFileMetadata, Double, Double)? in
            if case let .ok(meta, pV, pC) = r.status {
                return (r, meta, pV, pC)
            }
            return nil
        }

        if !okResults.isEmpty {
            let formats = Set(okResults.map { $0.1.format })
            if formats.count > 1 {
                let names = formats.map(\.rawValue).joined(separator: ", ")
                appendLog(
                    "Erreur : le dossier mélange plusieurs formats de fichiers (\(names)). " +
                    "Export annulé pour préserver la cohérence du tableau récapitulatif.",
                    isError: true
                )
            } else if let format = formats.first {
                var rowsByIter: [String: AggregatedXLSXWriter.Row] = [:]
                for (_, meta, pV, pC) in okResults {
                    let key = AggregatedXLSXWriter.Key(canal: meta.canal, variante: meta.variante)
                    let measurement = AggregatedXLSXWriter.Measurement(tension: pV, courant: pC)
                    if var existing = rowsByIter[meta.iterationLabel] {
                        if existing.measurements[key] == nil {
                            existing.measurements[key] = measurement
                            rowsByIter[meta.iterationLabel] = existing
                        } else {
                            appendLog(
                                "Avertissement : doublon (canal=\(meta.canal), variante=\(meta.variante)) pour l'itération \(meta.iterationLabel). Seule la première occurrence est conservée.",
                                isError: true
                            )
                        }
                    } else {
                        rowsByIter[meta.iterationLabel] = AggregatedXLSXWriter.Row(
                            iterationLabel: meta.iterationLabel,
                            iterationKey: meta.iterationKey,
                            measurements: [key: measurement]
                        )
                    }
                }

                let xlsxData = AggregatedXLSXWriter.build(
                    rows: Array(rowsByIter.values),
                    format: format
                )
                let xlsxURL = outputFolder.appendingPathComponent("\(folderName).xlsx")
                do {
                    try xlsxData.write(to: xlsxURL)
                    lastOutputFolder = outputFolder
                    canOpenResults = true
                } catch {
                    appendLog("Erreur à l'écriture du classeur final : \(error.localizedDescription)",
                              isError: true)
                }
            }
        }

        appendLog("")
        appendLog("Traitement terminé.")
        appendLog("Fichiers traités : \(okResults.count) / \(files.count)")
        appendLog(String(format: "Temps écoulé : %.2f secondes.", elapsed))

        isRunning = false
    }

    // MARK: - Helpers

    func appendLog(_ message: String, isError: Bool = false) {
        logLines.append(LogLine(message: message, isError: isError))
    }

    func clearLog() {
        logLines.removeAll()
    }

    private func didFinish(file r: BatchFileResult, options: BatchOptions) {
        progressCurrent += 1
        switch r.status {
        case .ok:
            appendLog("Traitement : \(r.fileName)")
            if let analysis = r.analysis {
                performPerFileExports(analysis: analysis, options: options)
            }
        case .skipped:
            appendLog("Fichier ignoré (nom non reconnu) : \(r.fileName)")
        case .error(let msg):
            appendLog("Erreur dans \(r.fileName) : \(msg)", isError: true)
        }
    }

    /// Exports par-fichier exécutés sur le MainActor (ImageRenderer y oblige).
    /// Les échecs d'écriture sont logués en rouge mais ne bloquent pas la suite.
    private func performPerFileExports(analysis: VoltammetryAnalysis, options: BatchOptions) {
        let baseName = (analysis.fileName as NSString).deletingPathExtension

        if options.exportGraph {
            let (potentials, currents) = SWVFileReader.processData(analysis.rawData)
            let pngURL = options.outputFolder.appendingPathComponent(baseName + ".png")
            do {
                try ChartPNGRenderer.renderPNG(
                    analysis: analysis,
                    potentials: potentials,
                    rawCurrents: currents,
                    to: pngURL
                )
            } catch {
                appendLog("Avertissement (\(analysis.fileName)) : échec export PNG : \(error.localizedDescription)",
                          isError: true)
            }
        }

        switch options.exportProcessed {
        case .none:
            break
        case .csv:
            let (cleanedP, cleanedC) = SWVFileReader.cleanedSignedData(analysis.rawData)
            let csvURL = options.outputFolder.appendingPathComponent(baseName + ".csv")
            do {
                try PerFileExporters.writeCleanedCSV(
                    potentials: cleanedP, currents: cleanedC, to: csvURL
                )
            } catch {
                appendLog("Avertissement (\(analysis.fileName)) : échec export CSV : \(error.localizedDescription)",
                          isError: true)
            }
        case .xlsx:
            let (cleanedP, cleanedC) = SWVFileReader.cleanedSignedData(analysis.rawData)
            let xlsxURL = options.outputFolder.appendingPathComponent(baseName + ".xlsx")
            do {
                try PerFileExporters.writeCleanedXLSX(
                    potentials: cleanedP, currents: cleanedC, to: xlsxURL
                )
            } catch {
                appendLog("Avertissement (\(analysis.fileName)) : échec export XLSX : \(error.localizedDescription)",
                          isError: true)
            }
        }
    }
}
