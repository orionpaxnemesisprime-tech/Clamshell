// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// "Support Clamshell" in Settings: optional tips that unlock nothing.
/// Shown only when the build has a RevenueCat key (see `TipJar`).
struct TipJarSection: View {
    @State private var tipJar = TipJar.shared

    var body: some View {
        if tipJar.isAvailable {
            Section {
                if tipJar.tips.isEmpty {
                    HStack {
                        Text("Loading Tips…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                    }
                }
                ForEach(tipJar.tips) { tip in
                    Button {
                        Task { await tipJar.buy(tip) }
                    } label: {
                        LabeledContent {
                            if tipJar.state == .purchasing(tip.id) {
                                ProgressView()
                            } else {
                                Text(tip.price)
                            }
                        } label: {
                            Text(tip.title)
                                .foregroundStyle(.primary)
                        }
                    }
                    .disabled(tipJar.state == .purchasing(tip.id))
                }
                if tipJar.state == .thanked {
                    Label("Thank you for supporting Clamshell!", systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                }
            } header: {
                Text("Support Clamshell")
            } footer: {
                Text("Tips are optional and don’t unlock anything. Clamshell stays free and open source either way.")
            }
            .task { await tipJar.loadTips() }
            .alert("Couldn’t Complete the Tip", isPresented: failed) {
                Button("OK", role: .cancel) { tipJar.state = .idle }
            } message: {
                if case .failed(let message) = tipJar.state { Text(message) }
            }
        }
    }

    private var failed: Binding<Bool> {
        Binding {
            if case .failed = tipJar.state { true } else { false }
        } set: { isPresented in
            if !isPresented { tipJar.state = .idle }
        }
    }
}
