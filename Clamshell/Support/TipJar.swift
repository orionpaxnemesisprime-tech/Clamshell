// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import RevenueCat

/// Optional tips: consumable in-app purchases that unlock nothing, bought through RevenueCat.
///
/// Clamshell stays free and complete without them. The RevenueCat public SDK key comes from
/// the `RevenueCatAPIKey` Info.plist entry (`REVENUECAT_API_KEY` build setting); without one,
/// the tip jar is hidden. Never put a RevenueCat *secret* key in the app.
@Observable
final class TipJar {
    static let shared = TipJar()

    /// Consumable product IDs, cheapest first. They must exist in App Store Connect and in the
    /// RevenueCat project.
    static let productIDs = [
        "com.foldingduo.Clamshell.tip.small",
        "com.foldingduo.Clamshell.tip.medium",
        "com.foldingduo.Clamshell.tip.large",
    ]

    struct Tip: Identifiable {
        let product: StoreProduct
        var id: String { product.productIdentifier }
        var title: String { product.localizedTitle }
        var price: String { product.localizedPriceString }
    }

    enum State: Equatable {
        case idle
        case purchasing(Tip.ID)
        case thanked
        case failed(String)
    }

    /// Whether a RevenueCat key is configured. False in builds without one (e.g. forks).
    let isAvailable: Bool
    private(set) var tips: [Tip] = []
    var state: State = .idle

    private init(bundle: Bundle = .main) {
        let key = (bundle.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        // appl_ is an App Store key; test_ is RevenueCat's Test Store key for development.
        isAvailable = key.hasPrefix("appl_") || key.hasPrefix("test_")
        guard isAvailable else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: key)
    }

    /// Loads the tips' localized names and prices from the App Store.
    func loadTips() async {
        guard isAvailable, tips.isEmpty else { return }
        let products = await Purchases.shared.products(Self.productIDs)
        tips = products
            .sorted { $0.price < $1.price }
            .map(Tip.init(product:))
    }

    func buy(_ tip: Tip) async {
        guard state != .purchasing(tip.id) else { return }
        state = .purchasing(tip.id)
        do {
            let result = try await Purchases.shared.purchase(product: tip.product)
            state = result.userCancelled ? .idle : .thanked
        } catch ErrorCode.purchaseCancelledError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
