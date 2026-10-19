// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// App information, the non-affiliation disclaimer, source code and licences (GPLv3).
/// Pushed from Settings.
struct AboutView: View {
    /// Public repository holding the exact source of this build. Required before release:
    /// GPLv3 needs the corresponding source to be available (see app-store-compliance).
    static let sourceRepository: URL? = nil

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: version)
                if let url = Self.sourceRepository {
                    Link("Source Code", destination: url)
                }
            } footer: {
                Text("Clamshell is free software, licensed under the GNU General Public License version 3.")
            }

            Section("Disclaimer") {
                Text("Clamshell is not affiliated with, endorsed by, or sponsored by Nintendo. All trademarks belong to their respective owners. Clamshell does not include any games; you must supply software you have the right to use.")
            }

            Section("Licences") {
                NavigationLink("GNU General Public License v3") {
                    LicenseTextView(title: "GPL v3", resource: "GPL-3.0")
                }
                NavigationLink("Third-Party Components") {
                    LicenseTextView(title: "Components", resource: "ThirdPartyComponents")
                }
                NavigationLink("Third-Party Licence Texts") {
                    LicenseTextView(title: "Licence Texts", resource: "ThirdPartyNotices")
                }
            }
        }
        .navigationTitle("About Clamshell")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseTextView: View {
    let title: LocalizedStringKey
    let resource: String

    private var text: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return String(localized: "Licence text unavailable.") }
        return text
    }

    var body: some View {
        // One Text per paragraph: VoiceOver gets navigable stops instead of a single ~700-line
        // element, and long licences lay out lazily.
        let paragraphs = text.components(separatedBy: "\n\n")
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(paragraphs.indices, id: \.self) { index in
                    Text(paragraphs[index])
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
