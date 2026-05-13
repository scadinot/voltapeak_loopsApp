//
//  voltapeak_loopsApp.swift
//  voltapeak_loops
//
//  Point d'entrée SwiftUI. Fenêtre unique, redimensionnable, taille par
//  défaut similaire à celle de la GUI Tkinter du script Python.
//

import SwiftUI

@main
struct VoltapeakLoopsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 760, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
