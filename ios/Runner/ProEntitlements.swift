import StoreKit

/// Pro unlock rule, kept apart from the Flutter channel so it can be tested.
/// Only an Apple-verified, active, non-revoked auto-renewable monthly
/// subscription counts; an unverified transaction is an error, never a grant.
enum ProEntitlements {
  static let productID = "kamubul_pro_monthly"

  enum Failure: Error {
    case unverified
  }

  static func activeProducts(now: Date = Date()) async throws -> [String] {
    var products = Set<String>()
    for await verification in Transaction.currentEntitlements {
      switch verification {
      case .verified(let transaction):
        guard transaction.productID == productID,
          transaction.productType == .autoRenewable,
          transaction.revocationDate == nil,
          let expiration = transaction.expirationDate,
          expiration > now
        else { continue }
        products.insert(transaction.productID)
      case .unverified:
        throw Failure.unverified
      }
    }
    return Array(products)
  }
}
