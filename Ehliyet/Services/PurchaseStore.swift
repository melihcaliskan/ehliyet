import Foundation
import Observation
import StoreKit

enum ProductID {
    static let monthly = "com.melihcaliskan.ehliyet.premium.monthly"
    static let sixMonths = "com.melihcaliskan.ehliyet.premium.6months"
    static let videos = "com.melihcaliskan.ehliyet.videos"
    static let all = [sixMonths, monthly, videos]
}

/// StoreKit 2 satın alma akışı. Haklar her zaman sunucudan gelir;
/// cihazdaki işlemler doğrulanmak üzere sunucuya gönderilir.
@Observable
@MainActor
final class PurchaseStore {
    private(set) var products: [Product] = []
    private(set) var isPurchasing = false
    private(set) var loadError: String?
    var lastError: String?

    private let api = APIClient.shared
    private let auth: AuthStore
    private var updatesTask: Task<Void, Never>?

    init(auth: AuthStore) {
        self.auth = auth
    }

    func start() {
        guard updatesTask == nil else { return }
        // Uygulama dışında gerçekleşen işlemler (yenileme, Aile Paylaşımı, onay bekleyen satın almalar)
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = ProductID.all.compactMap { id in loaded.first { $0.id == id } }
            loadError = products.isEmpty ? "Ürünler bulunamadı" : nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    /// Satın alır ve sunucuda doğrular. Başarılıysa `true` döner.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard let user = auth.user else { auth.showLogin = true; return false }
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }

        do {
            // appAccountToken: sunucu satın almayı bu kullanıcıya bağlar
            let result = try await product.purchase(options: [.appAccountToken(user.id)])
            switch result {
            case .success(let verification):
                let ok = await handle(verification)
                Analytics.track(ok ? "purchase_success" : "purchase_failed", ["product": product.id])
                return ok
            case .pending:
                lastError = "Satın alma onay bekliyor. Onaylandığında otomatik açılacak."
            case .userCancelled:
                Analytics.track("purchase_cancel", ["product": product.id])
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    /// "Satın Alımları Geri Yükle"
    func restore() async {
        guard auth.isSignedIn else { auth.showLogin = true; return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            var jws: [String] = []
            for await result in Transaction.currentEntitlements { jws.append(result.jwsRepresentation) }
            let ent: APIEntitlements = try await api.send("POST", "/v1/iap/restore", body: ["signedTransactions": jws])
            auth.update(ent)
            if !ent.isPremium && ent.scopes.isEmpty { lastError = "Geri yüklenecek satın alma bulunamadı." }
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    private func handle(_ result: VerificationResult<Transaction>) async -> Bool {
        // Cihaz tarafında da imzayı kontrol et; asıl doğrulama sunucuda
        guard case .verified(let transaction) = result else {
            lastError = "Satın alma doğrulanamadı."
            return false
        }
        guard auth.isSignedIn else { return false } // giriş yapınca restore ile gönderilecek
        do {
            let ent: APIEntitlements = try await api.send("POST", "/v1/iap/transactions",
                                                          body: ["signedTransaction": result.jwsRepresentation])
            auth.update(ent)
            // Sunucu kaydettikten sonra bitir; aksi halde StoreKit tekrar teslim eder
            await transaction.finish()
            return true
        } catch {
            lastError = "Satın alma alındı ama sunucuya kaydedilemedi: \(error.localizedDescription)"
            return false
        }
    }
}
