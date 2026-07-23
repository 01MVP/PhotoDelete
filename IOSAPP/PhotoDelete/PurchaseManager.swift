//
//  PurchaseManager.swift
//  PhotoDelete
//
//  Created by PhotoDelete Team on 11/7/25.
//

import Foundation
import StoreKit

enum SupporterPurchasePlan: String, CaseIterable, Identifiable {
    case annual
    case lifetime

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .annual:
            AppConstants.supporterAnnualProductID
        case .lifetime:
            AppConstants.supporterLifetimeProductID
        }
    }
}

enum SupporterAccessKind: String, Equatable {
    case annual
    case lifetime

    init?(productID: String) {
        switch productID {
        case AppConstants.supporterAnnualProductID:
            self = .annual
        case AppConstants.supporterLifetimeProductID:
            self = .lifetime
        default:
            return nil
        }
    }
}

enum SupporterCachedEntitlementPolicy {
    static func isValid(
        isUnlocked: Bool,
        productID: String?,
        expirationDate: Date?,
        now: Date
    ) -> Bool {
        guard isUnlocked else { return false }

        // Existing purchases predate the product-ID cache and are permanent unlocks.
        guard let productID else { return true }
        guard let accessKind = SupporterAccessKind(productID: productID) else { return false }

        switch accessKind {
        case .lifetime:
            return true
        case .annual:
            guard let expirationDate else { return false }
            return expirationDate > now
        }
    }
}

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
    @Published private(set) var supporterPurchaseDate: Date?
    @Published private(set) var supporterExpirationDate: Date?
    @Published private(set) var supporterAccessKind: SupporterAccessKind?
    @Published private(set) var supporterTrialStartDate: Date?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private(set) var hasActivatedStoreKit = false

    private let productIDs = Array(AppConstants.supporterProductIDs)
    private let userDefaults: UserDefaults
    private let nowProvider: () -> Date
    private let allowsLocalSupporterTrial: Bool
    private var updatesTask: Task<Void, Never>?
    private var productLoadRequest: (id: UUID, task: Task<[Product], Error>)?
    private var externalEntitlementRefreshTask: Task<Void, Never>?
    private var lastExternalEntitlementRefreshDate: Date?
    private let externalEntitlementRefreshCooldown: TimeInterval = 20

    var supporterAnnualProduct: Product? {
        product(for: .annual)
    }

    var supporterLifetimeProduct: Product? {
        product(for: .lifetime)
    }

    var supporterAnnualPriceText: String {
        priceText(for: .annual)
    }

    var supporterLifetimePriceText: String {
        priceText(for: .lifetime)
    }

    // The compact advanced screen promotes the lower-barrier annual plan.
    var supporterPriceText: String {
        supporterAnnualPriceText
    }

    var hasPaidSupporterAccess: Bool {
        entitlementState.allowsSupporterAccess
    }

    var isSupporter: Bool {
        hasPaidSupporterAccess || isSupporterTrialActive
    }

    var isUsingCachedSupporterAccess: Bool {
        entitlementState.isCachedAccess
    }

    var isUsingTrialSupporterAccess: Bool {
        !hasPaidSupporterAccess && isSupporterTrialActive
    }

    var canStartSupporterTrial: Bool {
        allowsLocalSupporterTrial && !hasPaidSupporterAccess && supporterTrialStartDate == nil
    }

    var isSupporterTrialActive: Bool {
        guard allowsLocalSupporterTrial,
              !hasPaidSupporterAccess,
              let supporterTrialEndDate else {
            return false
        }
        return nowProvider() < supporterTrialEndDate
    }

    var isSupporterTrialExpired: Bool {
        guard !hasPaidSupporterAccess,
              supporterTrialStartDate != nil else {
            return false
        }
        return !isSupporterTrialActive
    }

    var supporterTrialEndDate: Date? {
        supporterTrialStartDate?.addingTimeInterval(AppConstants.supporterTrialDuration)
    }

    var supporterTrialDaysRemaining: Int {
        guard isSupporterTrialActive,
              let supporterTrialEndDate else {
            return 0
        }
        let secondsRemaining = max(0, supporterTrialEndDate.timeIntervalSince(nowProvider()))
        return max(1, Int(ceil(secondsRemaining / 86_400)))
    }

    var supporterTrialStatusText: String? {
        if isUsingTrialSupporterAccess {
            return String(format: L10n.string("支持者版试用中，还剩 %lld 天。"), supporterTrialDaysRemaining)
        }

        if isSupporterTrialExpired {
            return L10n.string("3 天体验已结束，基础整理仍可继续使用。开通年度或永久 Pro 后可继续使用进阶功能。")
        }

        return nil
    }

    init(
        userDefaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = { Date.now },
        startsStoreKitTasks: Bool = false,
        allowsLocalSupporterTrial: Bool = PurchaseManager.defaultAllowsLocalSupporterTrial
    ) {
        self.userDefaults = userDefaults
        self.nowProvider = nowProvider
        self.allowsLocalSupporterTrial = allowsLocalSupporterTrial
        let cachedProductID = userDefaults.string(forKey: AppConstants.supporterProductIDKey)
        let cachedExpirationDate = userDefaults.object(forKey: AppConstants.supporterExpirationDateKey) as? Date
        let hasCachedEntitlement = SupporterCachedEntitlementPolicy.isValid(
            isUnlocked: userDefaults.bool(forKey: AppConstants.supporterEntitlementKey),
            productID: cachedProductID,
            expirationDate: cachedExpirationDate,
            now: nowProvider()
        )
        self.entitlementState = .initial(hasCachedEntitlement: hasCachedEntitlement)
        self.supporterPurchaseDate = userDefaults.object(forKey: AppConstants.supporterPurchaseDateKey) as? Date
        self.supporterExpirationDate = hasCachedEntitlement ? cachedExpirationDate : nil
        self.supporterAccessKind = hasCachedEntitlement
            ? (cachedProductID.flatMap(SupporterAccessKind.init(productID:)) ?? .lifetime)
            : nil
        if hasCachedEntitlement || !allowsLocalSupporterTrial {
            self.supporterTrialStartDate = nil
            userDefaults.removeObject(forKey: AppConstants.supporterTrialStartDateKey)
        } else {
            self.supporterTrialStartDate = userDefaults.object(forKey: AppConstants.supporterTrialStartDateKey) as? Date
        }

        if startsStoreKitTasks {
            Task {
                await activateStoreKit()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
        externalEntitlementRefreshTask?.cancel()
    }

    func startSupporterTrial() {
        guard allowsLocalSupporterTrial, canStartSupporterTrial else { return }

        let startDate = nowProvider()
        supporterTrialStartDate = startDate
        userDefaults.set(startDate, forKey: AppConstants.supporterTrialStartDateKey)
    }

    nonisolated private static var defaultAllowsLocalSupporterTrial: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    func activateStoreKit() async {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                await self?.listenForTransactions()
            }
        }

        guard !hasActivatedStoreKit else { return }
        hasActivatedStoreKit = true

        async let entitlementRefresh: Void = refreshEntitlementsSilently()
        async let productLoad: Void = loadProducts()
        _ = await (entitlementRefresh, productLoad)
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

    func purchaseSupporter(plan: SupporterPurchasePlan = .annual) async {
        await activateStoreKit()
        isLoading = true
        defer { isLoading = false }

        if product(for: plan) == nil {
            await loadProducts()
        }

        guard let product = product(for: plan) else {
            errorMessage = L10n.string("暂时无法读取支持者版商品。")
            return
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                setVerifiedSupporterAccess(true, transaction: transaction)
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
        await activateStoreKit()
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlementsAfterPotentialExternalChange(showVerificationState: true)
            if !hasPaidSupporterAccess {
                errorMessage = L10n.string("没有找到可恢复的支持者版购买。")
            }
        } catch {
            if hasCachedSupporterEntitlement {
                entitlementState = .cachedOffline
            }
            errorMessage = L10n.string("恢复购买失败，请稍后再试。")
        }
    }

    func handleOfferCodeRedemptionCompletion(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            Task { await refreshEntitlementsAfterOfferCodeRedemption() }
        case .failure(let error):
            guard !(error is CancellationError) else { return }
            errorMessage = L10n.string("无法打开兑换页面，请稍后再试。")
        }
    }

    func refreshEntitlements() async {
        await refreshEntitlements(showVerificationState: true, shouldLockWhenMissing: true)
    }

    func refreshEntitlementsSilently() async {
        await refreshEntitlements(showVerificationState: false, shouldLockWhenMissing: true)
    }

    func refreshEntitlementsAfterPotentialExternalChange() async {
        await refreshEntitlementsAfterPotentialExternalChange(showVerificationState: false)
    }

    func refreshEntitlementsAfterForegroundActivationIfNeeded() {
        guard externalEntitlementRefreshTask == nil else { return }

        let now = nowProvider()
        if let lastExternalEntitlementRefreshDate,
           now.timeIntervalSince(lastExternalEntitlementRefreshDate) < externalEntitlementRefreshCooldown {
            return
        }

        lastExternalEntitlementRefreshDate = now
        externalEntitlementRefreshTask = Task { [weak self] in
            await self?.refreshEntitlementsAfterPotentialExternalChange()
            await MainActor.run {
                self?.externalEntitlementRefreshTask = nil
            }
        }
    }

    private func refreshEntitlementsAfterPotentialExternalChange(showVerificationState: Bool) async {
        await refreshEntitlements(showVerificationState: showVerificationState, shouldLockWhenMissing: true)
        if hasPaidSupporterAccess { return }

        for delay in [1_500_000_000, 4_000_000_000, 8_000_000_000] as [UInt64] {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await refreshEntitlementsSilently()
            if hasPaidSupporterAccess { return }
        }
    }

    private func refreshEntitlementsAfterOfferCodeRedemption() async {
        errorMessage = nil
        await refreshEntitlementsAfterPotentialExternalChange(showVerificationState: true)
    }

    private func refreshEntitlements(
        showVerificationState: Bool,
        shouldLockWhenMissing: Bool
    ) async {
        if showVerificationState {
            entitlementState = .verificationStarted(hasCachedEntitlement: hasCachedSupporterEntitlement)
        }
        var hasCurrentSupporterEntitlement = false
        var currentTransaction: Transaction?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard AppConstants.supporterProductIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }

            hasCurrentSupporterEntitlement = true
            if transaction.productID == AppConstants.supporterLifetimeProductID {
                currentTransaction = transaction
                break
            }
            currentTransaction = transaction
        }

        if hasCurrentSupporterEntitlement, let currentTransaction {
            setVerifiedSupporterAccess(true, transaction: currentTransaction)
            errorMessage = nil
        } else if shouldLockWhenMissing {
            setVerifiedSupporterAccess(false)
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            guard AppConstants.supporterProductIDs.contains(transaction.productID) else {
                await transaction.finish()
                continue
            }

            if transaction.revocationDate == nil {
                setVerifiedSupporterAccess(true, transaction: transaction)
            } else {
                await transaction.finish()
                await refreshEntitlementsSilently()
                continue
            }
            await transaction.finish()
        }
    }

    private var hasCachedSupporterEntitlement: Bool {
        SupporterCachedEntitlementPolicy.isValid(
            isUnlocked: userDefaults.bool(forKey: AppConstants.supporterEntitlementKey),
            productID: userDefaults.string(forKey: AppConstants.supporterProductIDKey),
            expirationDate: userDefaults.object(forKey: AppConstants.supporterExpirationDateKey) as? Date,
            now: nowProvider()
        )
    }

    private func setVerifiedSupporterAccess(_ value: Bool, transaction: Transaction? = nil) {
        entitlementState = value ? .verified : .locked
        userDefaults.set(value, forKey: AppConstants.supporterEntitlementKey)

        if value {
            supporterTrialStartDate = nil
            userDefaults.removeObject(forKey: AppConstants.supporterTrialStartDateKey)

            if let transaction,
               let accessKind = SupporterAccessKind(productID: transaction.productID) {
                supporterAccessKind = accessKind
                supporterPurchaseDate = transaction.purchaseDate
                supporterExpirationDate = transaction.expirationDate
                userDefaults.set(transaction.productID, forKey: AppConstants.supporterProductIDKey)
                userDefaults.set(transaction.purchaseDate, forKey: AppConstants.supporterPurchaseDateKey)
                if let expirationDate = transaction.expirationDate {
                    userDefaults.set(expirationDate, forKey: AppConstants.supporterExpirationDateKey)
                } else {
                    userDefaults.removeObject(forKey: AppConstants.supporterExpirationDateKey)
                }
            } else {
                supporterPurchaseDate = userDefaults.object(forKey: AppConstants.supporterPurchaseDateKey) as? Date
                supporterExpirationDate = userDefaults.object(forKey: AppConstants.supporterExpirationDateKey) as? Date
                supporterAccessKind = userDefaults.string(forKey: AppConstants.supporterProductIDKey)
                    .flatMap(SupporterAccessKind.init(productID:)) ?? .lifetime
            }
        } else {
            supporterPurchaseDate = nil
            supporterExpirationDate = nil
            supporterAccessKind = nil
            userDefaults.removeObject(forKey: AppConstants.supporterPurchaseDateKey)
            userDefaults.removeObject(forKey: AppConstants.supporterExpirationDateKey)
            userDefaults.removeObject(forKey: AppConstants.supporterProductIDKey)
        }
    }

    private func product(for plan: SupporterPurchasePlan) -> Product? {
        products.first { $0.id == plan.productID }
    }

    private func priceText(for plan: SupporterPurchasePlan) -> String {
        if let product = product(for: plan) {
            return product.displayPrice
        }
        return hasActivatedStoreKit ? L10n.string("读取价格中") : L10n.string("查看价格")
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
