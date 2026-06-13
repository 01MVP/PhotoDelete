//
//  PurchaseManager.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import Foundation
import StoreKit

enum SupporterEntitlementState: Equatable {
    case unknown
    case verifying
    case verified
    case cachedOffline
    case locked

    var allowsSupporterAccess: Bool {
        switch self {
        case .verified, .cachedOffline:
            true
        case .unknown, .verifying, .locked:
            false
        }
    }

    var isCachedAccess: Bool {
        self == .cachedOffline
    }

    static func initial(hasCachedEntitlement: Bool) -> SupporterEntitlementState {
        hasCachedEntitlement ? .cachedOffline : .locked
    }

    static func verificationStarted(hasCachedEntitlement: Bool) -> SupporterEntitlementState {
        hasCachedEntitlement ? .cachedOffline : .verifying
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var entitlementState: SupporterEntitlementState
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let productIDs = [AppConstants.supporterProductID]
    private let userDefaults: UserDefaults
    private var updatesTask: Task<Void, Never>?
    private var productLoadRequest: (id: UUID, task: Task<[Product], Error>)?

    var supporterProduct: Product? {
        products.first { $0.id == AppConstants.supporterProductID }
    }

    var supporterPriceText: String {
        supporterProduct?.displayPrice ?? L10n.string("读取价格中")
    }

    var isSupporter: Bool {
        entitlementState.allowsSupporterAccess
    }

    var isUsingCachedSupporterAccess: Bool {
        entitlementState.isCachedAccess
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.entitlementState = .initial(hasCachedEntitlement: userDefaults.bool(forKey: AppConstants.supporterEntitlementKey))

        updatesTask = Task { [weak self] in
            await self?.listenForTransactions()
        }

        Task {
            await refreshEntitlementsSilently()
            await loadProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        guard products.isEmpty else {
            errorMessage = nil
            return
        }

        let loadRequestID: UUID
        let loadTask: Task<[Product], Error>
        if let productLoadRequest {
            loadRequestID = productLoadRequest.id
            loadTask = productLoadRequest.task
        } else {
            let productIDs = productIDs
            loadRequestID = UUID()
            loadTask = Task {
                try await Product.products(for: productIDs)
            }
            productLoadRequest = (id: loadRequestID, task: loadTask)
        }

        do {
            products = try await loadTask.value
            if products.isEmpty {
                errorMessage = L10n.string("暂时无法读取支持者版商品。")
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = L10n.string("暂时无法读取支持者版商品。")
        }

        if productLoadRequest?.id == loadRequestID {
            productLoadRequest = nil
        }
    }

    func purchaseSupporter() async {
        isLoading = true
        defer { isLoading = false }

        if supporterProduct == nil {
            await loadProducts()
        }

        guard let product = supporterProduct else {
            errorMessage = L10n.string("暂时无法读取支持者版商品。")
            return
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                setVerifiedSupporterAccess(true)
                errorMessage = nil
            case .pending:
                errorMessage = L10n.string("购买正在处理中，完成后会自动解锁。")
            case .userCancelled:
                errorMessage = nil
            @unknown default:
                errorMessage = L10n.string("购买未完成，请稍后再试。")
            }
        } catch {
            errorMessage = L10n.string("购买未完成，请稍后再试。")
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isSupporter {
                errorMessage = L10n.string("没有找到可恢复的支持者版购买。")
            }
        } catch {
            if hasCachedSupporterEntitlement {
                entitlementState = .cachedOffline
            }
            errorMessage = L10n.string("恢复购买失败，请稍后再试。")
        }
    }

    func refreshEntitlements() async {
        await refreshEntitlements(showVerificationState: true, shouldLockWhenMissing: true)
    }

    func refreshEntitlementsSilently() async {
        await refreshEntitlements(showVerificationState: false, shouldLockWhenMissing: true)
    }

    private func refreshEntitlements(
        showVerificationState: Bool,
        shouldLockWhenMissing: Bool
    ) async {
        if showVerificationState {
            entitlementState = .verificationStarted(hasCachedEntitlement: hasCachedSupporterEntitlement)
        }
        var hasCurrentSupporterEntitlement = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == AppConstants.supporterProductID,
               transaction.revocationDate == nil {
                hasCurrentSupporterEntitlement = true
                break
            }
        }

        if hasCurrentSupporterEntitlement {
            setVerifiedSupporterAccess(true)
            errorMessage = nil
        } else if shouldLockWhenMissing {
            setVerifiedSupporterAccess(false)
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            guard transaction.productID == AppConstants.supporterProductID else {
                await transaction.finish()
                continue
            }

            if transaction.revocationDate == nil {
                setVerifiedSupporterAccess(true)
            } else {
                setVerifiedSupporterAccess(false)
            }
            await transaction.finish()
        }
    }

    private var hasCachedSupporterEntitlement: Bool {
        userDefaults.bool(forKey: AppConstants.supporterEntitlementKey)
    }

    private func setVerifiedSupporterAccess(_ value: Bool) {
        entitlementState = value ? .verified : .locked
        userDefaults.set(value, forKey: AppConstants.supporterEntitlementKey)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreKitVerificationError.unverifiedTransaction
        }
    }
}

private enum StoreKitVerificationError: Error {
    case unverifiedTransaction
}
