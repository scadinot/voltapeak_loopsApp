//
//  ContentView.swift
//  voltapeak_loops
//
//  Interface batch reproduisant les sections de la GUI Tkinter du script
//  Python : dossier d'entrée, paramètres de lecture, options d'export,
//  barre de progression, journal et boutons d'action.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var vm = VoltapeakLoopsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputFolderRow
            settingsBox
            progressBox
            logBox
            actionRow
        }
        .padding(14)
        .frame(minWidth: 720, minHeight: 580)
    }

    // MARK: - Sections

    private var inputFolderRow: some View {
        HStack(spacing: 8) {
            Text("Dossier d'entrée :")
            Text(vm.inputFolder?.path ?? " ")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.3))
                )
            Button("Parcourir") { vm.selectFolder() }
                .disabled(vm.isRunning)
        }
    }

    private var settingsBox: some View {
        GroupBox("Paramètres de lecture") {
            Grid(alignment: .leadingFirstTextBaseline,
                 horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Séparateur de colonnes :")
                    Picker("", selection: $vm.config.columnSeparator) {
                        ForEach(SWVFileConfiguration.ColumnSeparator.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                }
                GridRow {
                    Text("Séparateur décimal :")
                    Picker("", selection: $vm.config.decimalSeparator) {
                        ForEach(SWVFileConfiguration.DecimalSeparator.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                }
                GridRow {
                    Text("Export des fichiers traités :")
                    Picker("", selection: $vm.exportProcessed) {
                        Text("Ne pas exporter").tag(BatchOptions.ProcessedExport.none)
                        Text("Exporter au format .CSV").tag(BatchOptions.ProcessedExport.csv)
                        Text("Exporter au format Excel").tag(BatchOptions.ProcessedExport.xlsx)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                }
                GridRow {
                    Text("Export des graphiques :")
                    Picker("", selection: $vm.exportGraph) {
                        Text("Ne pas exporter").tag(false)
                        Text("Exporter au format .png").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                }
                GridRow {
                    Text("Mode de traitement :")
                    Picker("", selection: $vm.useMultiThread) {
                        Text("Multi-thread (un Task par cœur)").tag(true)
                        Text("Séquentiel").tag(false)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(vm.isRunning)
        }
    }

    private var progressBox: some View {
        GroupBox("Progression du traitement") {
            ProgressView(value: Double(vm.progressCurrent),
                         total: Double(max(vm.progressTotal, 1)))
                .progressViewStyle(.linear)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
        }
    }

    private var logBox: some View {
        GroupBox("Journal de traitement") {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(vm.logLines) { line in
                            Text(line.message.isEmpty ? " " : line.message)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(line.isError ? Color.red : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: vm.logLines.count) { _, _ in
                    guard let last = vm.logLines.last else { return }
                    withAnimation(nil) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .frame(minHeight: 160)
        }
    }

    private var actionRow: some View {
        HStack {
            Spacer()
            Button("Ouvrir le dossier de résultats") {
                vm.openResultsFolder()
            }
            .disabled(!vm.canOpenResults || vm.isRunning)

            Button("Lancer l'analyse") {
                Task { await vm.run() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(vm.inputFolder == nil || vm.isRunning)
        }
    }
}

#Preview {
    ContentView()
}
