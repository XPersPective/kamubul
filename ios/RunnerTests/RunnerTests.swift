import StoreKit
import StoreKitTest
import XCTest

@testable import Runner

/// Exercises the real Pro unlock rule against StoreKit Testing in the simulator.
/// This is local StoreKit with a generated configuration, not Apple's sandbox
/// servers: it proves our entitlement logic, not App Store Connect state.
@available(iOS 16.0, *)
final class ProEntitlementsTests: XCTestCase {
  private static let productID = "kamubul_pro_monthly"

  private static let configuration = """
    {
      "identifier": "7C1B1A5E-0A55-4C3B-9D52-3B2B7D4A9F10",
      "nonRenewingSubscriptions": [],
      "products": [],
      "settings": {"_locale": "tr_TR", "_storefront": "TUR"},
      "subscriptionGroups": [
        {
          "id": "22513026",
          "localizations": [],
          "name": "KamuBul Pro",
          "subscriptions": [
            {
              "adHocOffers": [],
              "codeOffers": [],
              "displayPrice": "58.99",
              "familyShareable": false,
              "groupNumber": 1,
              "internalID": "6826881201",
              "introductoryOffer": null,
              "localizations": [
                {"description": "Reklamsiz kullanim", "displayName": "KamuBul Pro", "locale": "tr"}
              ],
              "productID": "kamubul_pro_monthly",
              "recurringSubscriptionPeriod": "P1M",
              "referenceName": "KamuBul Pro Aylik",
              "subscriptionGroupID": "22513026",
              "type": "RecurringSubscription"
            }
          ]
        }
      ],
      "version": {"major": 3, "minor": 0}
    }
    """

  private var session: SKTestSession!

  override func setUpWithError() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("KamuBul-\(UUID().uuidString).storekit")
    try Self.configuration.write(to: url, atomically: true, encoding: .utf8)
    session = try SKTestSession(contentsOf: url)
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
  }

  override func tearDown() {
    session?.clearTransactions()
    session = nil
  }

  func testProductIsOfferedAsMonthlySubscription() async throws {
    let products = try await Product.products(for: [Self.productID])
    XCTAssertEqual(products.map(\.id), [Self.productID])
    XCTAssertEqual(products.first?.type, .autoRenewable)
    XCTAssertEqual(products.first?.subscription?.subscriptionPeriod.unit, .month)
  }

  func testNothingPurchasedGrantsNothing() async throws {
    let active = try await ProEntitlements.activeProducts()
    XCTAssertEqual(active, [])
  }

  func testPurchaseUnlocksPro() async throws {
    try await session.buyProduct(identifier: Self.productID)
    let active = try await ProEntitlements.activeProducts()
    XCTAssertEqual(active, [Self.productID])
  }

  func testExpiredSubscriptionRemovesPro() async throws {
    try await session.buyProduct(identifier: Self.productID)
    try session.expireSubscription(productIdentifier: Self.productID)
    let active = try await ProEntitlements.activeProducts()
    XCTAssertEqual(active, [])
  }

  func testRefundRemovesPro() async throws {
    try await session.buyProduct(identifier: Self.productID)
    let transactions = session.allTransactions()
    XCTAssertEqual(transactions.count, 1)
    try session.refundTransaction(identifier: transactions[0].identifier)
    let active = try await ProEntitlements.activeProducts()
    XCTAssertEqual(active, [])
  }

  func testRestoreKeepsActiveSubscription() async throws {
    try await session.buyProduct(identifier: Self.productID)
    // A restore on a new install is AppStore.sync(); entitlements must survive it.
    try await AppStore.sync()
    let active = try await ProEntitlements.activeProducts()
    XCTAssertEqual(active, [Self.productID])
  }
}
