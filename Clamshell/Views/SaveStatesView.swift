// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import SwiftUI

/// Save-state slots for the running game. The game stays paused while this is open.
struct SaveStatesView: View {
    let model: EmulatorModel
    @Environment(\.dismiss) private var dismiss
    @State private var slots: [StateStore.Slot] = []
    @State private var pendingOverwrite: StateStore.Slot?
    @State private var pendingLoad: StateStore.Slot?

    var body: some View {
        NavigationStack {
            List(slots) { slot in
                SlotRow(slot: slot,
                        save: { slot.isEmpty ? save(slot) : (pendingOverwrite = slot) },
                        load: { pendingLoad = slot })
                    .swipeActions {
                        if !slot.isEmpty {
                            Button("Delete", role: .destructive) {
                                model.deleteState(slot: slot.index)
                                refresh()
                            }
                        }
                    }
            }
            .navigationTitle("Save States")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Replace this save state?", isPresented: isPresented($pendingOverwrite),
                                presenting: pendingOverwrite) { slot in
                Button("Replace Slot \(slot.index + 1)", role: .destructive) { save(slot) }
            }
            .confirmationDialog("Load this save state?", isPresented: isPresented($pendingLoad),
                                presenting: pendingLoad) { slot in
                Button("Load Slot \(slot.index + 1)", role: .destructive) {
                    Task {
                        await model.loadState(slot: slot.index)
                        dismiss()
                    }
                }
            } message: { _ in
                Text("Progress since the last save will be lost.")
            }
            .task { refresh() }
        }
    }

    private func save(_ slot: StateStore.Slot) {
        Task {
            await model.saveState(slot: slot.index)
            refresh()
        }
    }

    private func refresh() {
        slots = model.saveStateSlots()
    }

    private func isPresented(_ slot: Binding<StateStore.Slot?>) -> Binding<Bool> {
        Binding(get: { slot.wrappedValue != nil }, set: { if !$0 { slot.wrappedValue = nil } })
    }
}

private struct SlotRow: View {
    let slot: StateStore.Slot
    let save: () -> Void
    let load: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility text sizes the buttons move below the slot details instead of
        // squeezing them.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            details
            HStack {
                Button("Load", action: load)
                    .buttonStyle(.bordered)
                    .disabled(slot.isEmpty)
                    // Four rows share these titles; name the slot for VoiceOver and Voice Control
                    // while keeping the visible word as a valid spoken command.
                    .accessibilityLabel("Load Slot \(slot.index + 1)")
                    .accessibilityInputLabels([Text("Load"), Text("Load Slot \(slot.index + 1)")])
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Save to Slot \(slot.index + 1)")
                    .accessibilityInputLabels([Text("Save"), Text("Save to Slot \(slot.index + 1)")])
            }
        }
    }

    private var details: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 48, height: 72)
                .clipShape(.rect(cornerRadius: 4))
                .accessibilityHidden(true)

            VStack(alignment: .leading) {
                Text("Slot \(slot.index + 1)")
                    .font(.headline)
                if let date = slot.date {
                    Text(date, format: .dateTime.day().month().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Empty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let url = slot.thumbnailURL, let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}
