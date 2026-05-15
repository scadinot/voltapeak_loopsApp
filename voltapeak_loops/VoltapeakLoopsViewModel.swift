//
//  VoltapeakLoopsViewModel.swift
//  voltapeak_loops
//
//  Orchestration de l'analyse batch :
//  - paramètres saisis depuis la GUI,
//  - préparation du dossier de sortie hors MainActor (peut bloquer sur disque réseau),
//  - parallélisme via TaskGroup (pool sliding-window borné à
//    `activeProcessorCount`) ou Task détachée séquentielle (utile au
//    débogage, équivalent du bouton de la GUI Python),
//  - exports par-fichier (PNG/CSV/XLSX) sur le MainActor après chaque calcul
//    (les vecteurs triés sont réutilisés tels quels via BatchFileResult.signals),
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

        // Préparation disque hors MainActor : sur un dossier volumineux ou un
        // volume réseau, la création/scan peut bloquer plusieurs centaines de ms.
        let files: [URL]
        do {
            files = try await Task.detached(priority: .utility) { () -> [URL] in
                try LoopsBatchProcessor.cleanOutputFolder(outputFolder)
                return LoopsBatchProcessor.enumerateInputFiles(in: input)
            }.value
        } catch {
            appendLog("Erreur au nettoyage du dossier de sortie : \(error.localizedDescription)",
                      isError: true)
            isRunning = false
            return
        }

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
            // Pool sliding-window borné à `activeProcessorCount` tâches en vol.
            // Évite l'oversubscription GCD (un addTask par fichier
            // immédiatement → N Tasks concurrentes sur un dossier de N
            // fichiers, ce qui dégrade les performances par thrashing dès
            // que N dépasse largement le nombre de cœurs). Aligné sur le
            // pattern utilisé par `BatchViewModel.runParallel` côté
            // voltapeak_batchApp.
            let maxConcurrency = max(1, ProcessInfo.processInfo.activeProcessorCount)

            results = await withTaskGroup(
                of: BatchFileResult.self,
                returning: [BatchFileResult].self
            ) { group in
                var nextIndex = 0

                // Amorce du pool : `maxConcurrency` tâches en vol.
                while nextIndex < files.count && nextIndex < maxConcurrency {
                    let url = files[nextIndex]
                    group.addTask(priority: .utility) {
                        LoopsBatchProcessor.processOne(url: url, options: options)
                    }
                    nextIndex += 1
                }

                // Drain : à chaque tâche terminée, on en lance une nouvelle
                // si la file d'entrée n'est pas épuisée.
                var collected: [BatchFileResult] = []
                collected.reserveCapacity(files.count)
                while let r = await group.next() {
                    collected.append(r)
                    didFinish(file: r, options: options)
                    if nextIndex < files.count {
                        let url = files[nextIndex]
                        group.addTask(priority: .utility) {
                            LoopsBatchProcessor.processOne(url: url, options: options)
                        }
                        nextIndex += 1
                    }
                }
                return collected
            }
        } else {
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
            performPerFileExports(result: r, options: options)
        case .skipped:
            appendLog("Fichier ignoré (nom non reconnu) : \(r.fileName)")
        case .error(let msg):
            appendLog("Erreur dans \(r.fileName) : \(msg)", isError: true)
        }
    }

    /// Exports par-fichier exécutés sur le MainActor (ImageRenderer y oblige).
    /// Réutilise les vecteurs déjà triés du `BatchFileResult` au lieu de relancer
    /// un tri côté ViewModel. Les échecs d'écriture sont logués en rouge mais
    /// ne bloquent pas la suite.
    private func performPerFileExports(result r: BatchFileResult, options: BatchOptions) {
        guard let analysis = r.analysis, let signals = r.signals else { return }
        let baseName = (r.fileName as NSString).deletingPathExtension

        if options.exportGraph {
            let pngURL = options.outputFolder.appendingPathComponent(baseName + ".png")
            do {
                try ChartPNGRenderer.renderPNG(
                    analysis: analysis,
                    potentials: signals.potentials,
                    rawCurrents: signals.processedCurrents,
                    to: pngURL
                )
            } catch {
                appendLog("Avertissement (\(r.fileName)) : échec export PNG : \(error.localizedDescription)",
                          isError: true)
            }
        }

        switch options.exportProcessed {
        case .none:
            break
        case .csv:
            let csvURL = options.outputFolder.appendingPathComponent(baseName + ".csv")
            do {
                try PerFileExporters.writeCleanedCSV(
                    potentials: signals.potentials,
                    currents: signals.cleanedSignedCurrents,
                    to: csvURL
                )
            } catch {
                appendLog("Avertissement (\(r.fileName)) : échec export CSV : \(error.localizedDescription)",
                          isError: true)
            }
        case .xlsx:
            let xlsxURL = options.outputFolder.appendingPathComponent(baseName + ".xlsx")
            do {
                try PerFileExporters.writeCleanedXLSX(
                    potentials: signals.potentials,
                    currents: signals.cleanedSignedCurrents,
                    to: xlsxURL
                )
            } catch {
                appendLog("Avertissement (\(r.fileName)) : échec export XLSX : \(error.localizedDescription)",
                          isError: true)
            }
        }
    }
}
