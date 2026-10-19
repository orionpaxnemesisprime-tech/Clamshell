//
//  ContentView.swift
//  Clamshell
//
//  Created by Optimus Prime on 10/19/26.
//

import SwiftUI

struct ContentView: View {
    @State private var model = EmulatorModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            if model.currentGame != nil {
                GameView(model: model)
            } else {
                LibraryView(model: model)
            }
        }
        #if DEBUG
        // Automation hook (simulator UI tools can't tap the iPhone Duo inner display):
        // launch with `-ClamshellAutoplay "<game name>"` to start a library game directly.
        .task {
            guard let name = UserDefaults.standard.string(forKey: "ClamshellAutoplay") else { return }
            model.refreshLibrary()
            if let game = model.library.first(where: { $0.name == name }) {
                model.play(game)
            }
        }
        #endif
        .onOpenURL { url in
            Task { await model.openExternalGame(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            model.setSceneActive(phase == .active)
        }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
}
