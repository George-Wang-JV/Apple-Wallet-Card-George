import Foundation
import AppKit

@main
struct WalletViewModelTests {
    @MainActor
    static func main() throws {
        let suite = "ScreenWalletTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = String(repeating: "A", count: 27) + "="
        let b = String(repeating: "B", count: 27) + "="
        let c = String(repeating: "C", count: 27) + "="
        defaults.set([b, a, b], forKey: "mak5er.aircard.savedCards")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenSkinTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let library = SkinLibrary(directory: temp.appendingPathComponent("library"))
        let vm = AppViewModel(cardDefaults: defaults, connectOnLaunch: false, skinLibrary: library)
        precondition(vm.cards.map(\.id) == [b, a])
        precondition(vm.currentVerifiedCards.isEmpty) // Saved records stay hidden until this scan sees them.
        precondition(vm.confirmedCardIDs.isEmpty) // Legacy IDs have no device provenance.
        vm.activateCardDevice("first-phone")
        vm.isScanningCards = true
        vm.walletCatalog = WalletCatalog(paymentStatus: "matched", payments: [
            .init(id: a, name: "Active A", source: "payment"),
            .init(id: b, name: "Active B", source: "payment")
        ], memberships: [], warnings: [], cacheUpdatedAt: nil)
        vm.reconcileMatchedPaymentCards()
        precondition(vm.currentVerifiedCards.isEmpty) // A cache alone is not enough.
        vm.recordScannedCard(a)
        vm.recordScannedCard(a)
        precondition(vm.currentScanIDs == [a] && vm.confirmedCardIDs == [a, b])
        precondition(vm.currentVerifiedCardIDs == [a, b])
        precondition(vm.cards.count == 2)
        vm.isScanningCards = false
        let activation = "A00000000310100100000020"
        precondition(!vm.recordActivatedPaymentCard(activation))
        vm.walletCatalog = WalletCatalog(paymentStatus: "matched", payments: [.init(id: b, name: "Active B", source: "payment", activationID: activation)], memberships: [], warnings: [], cacheUpdatedAt: nil)
        vm.reconcilePendingPaymentActivations()
        precondition(vm.cards.first(where: { $0.id == b })?.displayName == "Active B")
        vm.cards[0].customImageURL = URL(fileURLWithPath: "/skin-b.png")
        vm.cards[1].customImageURL = URL(fileURLWithPath: "/skin-a.png")
        vm.cards.reverse()
        vm.activateCardDevice("second-phone")
        precondition(vm.confirmedCardIDs.isEmpty)
        precondition(vm.cards.allSatisfy { $0.customImageURL == nil })
        vm.recordScannedCard(b)
        vm.activateCardDevice("first-phone")
        precondition(vm.cards.map(\.id) == [a, b])
        precondition(vm.confirmedCardIDs == [a, b])
        precondition(vm.cards[0].customImageURL?.path == "/skin-a.png")
        precondition(vm.cards[1].customImageURL?.path == "/skin-b.png")
        vm.clearAllCards()
        vm.activateCardDevice("second-phone")
        precondition(vm.confirmedCardIDs == [b])
        vm.activateCardDevice("first-phone")
        precondition(vm.cards.isEmpty) // Clear must not resurrect legacy JSON/defaults.
        let relaunched = AppViewModel(cardDefaults: defaults, connectOnLaunch: false, skinLibrary: library)
        relaunched.activateCardDevice("first-phone")
        precondition(relaunched.cards.isEmpty)
        relaunched.activateCardDevice("second-phone")
        precondition(relaunched.confirmedCardIDs == [b])
        let countBeforePreload = relaunched.cards.count
        relaunched.recordPreloadedCard(c)
        relaunched.recordPreloadedCard(c)
        precondition(relaunched.cards.count == countBeforePreload + 1)
        precondition(relaunched.cards.first(where: { $0.id == c })?.confirmed == true)
        precondition(relaunched.currentVerifiedCards.map(\.id) == [c])
        // Images are owned copies, duplicate imports reuse one entry, and assignment
        // history survives restarts independently for each device/card pair.
        func fixture(_ name: String, _ red: Int) throws -> URL {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            for y in 0..<4 { for x in 0..<4 {
                rep.setColor(NSColor(calibratedRed: CGFloat(red) / 255, green: 0.3, blue: 0.6, alpha: 1), atX: x, y: y)
            } }
            let url = temp.appendingPathComponent(name + ".png")
            try rep.representation(using: .png, properties: [:])!.write(to: url)
            return url
        }
        let sourceA = try fixture("Blue", 20)
        let sourceB = try fixture("Pink", 220)
        let firstSkin = try library.importImage(sourceA)
        let duplicate = try library.importImage(sourceA)
        precondition(firstSkin.id == duplicate.id && library.skins.count == 1)
        precondition(relaunched.setCardImage(for: b, url: sourceA))
        precondition(relaunched.setCardImage(for: b, url: sourceB))
        let secondSkin = library.skins.first { $0.id != firstSkin.id }!
        precondition(library.history(deviceID: "second-phone", cardID: b).map(\.id) == [secondSkin.id, firstSkin.id])
        precondition(library.history(deviceID: "first-phone", cardID: b).isEmpty)
        precondition(library.history(deviceID: "second-phone", cardID: c).isEmpty)
        try FileManager.default.removeItem(at: sourceA)
        precondition(NSImage(contentsOf: library.url(for: firstSkin)) != nil)
        let restored = SkinLibrary(directory: library.directory)
        precondition(restored.skins.count == 2)
        precondition(restored.history(deviceID: "second-phone", cardID: b).count == 2)
        precondition(relaunched.setCardImage(for: b, url: restored.url(for: firstSkin)))
        precondition(relaunched.cards.first { $0.id == b }?.customImageURL == restored.url(for: firstSkin))
        precondition(library.history(deviceID: "second-phone", cardID: b).map(\.id) == [firstSkin.id, secondSkin.id])
        let invalid = temp.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalid)
        precondition(!relaunched.setCardImage(for: b, url: invalid))
        precondition(relaunched.cards.first { $0.id == b }?.customImageURL == restored.url(for: firstSkin))
        precondition(library.skins.count == 2)
        relaunched.clearCardImage(for: b)
        precondition(library.history(deviceID: "second-phone", cardID: b).count == 2)
        relaunched.isFlashing = true
        precondition(!relaunched.setCardImage(for: b, url: sourceB))
        relaunched.isFlashing = false
        precondition(!relaunched.setCardImage(for: "deleted-card", url: sourceB))
        // Deletion removes every history reference, protects assigned skins,
        // survives relaunch and rolls the index back when Trash is unavailable.
        let deletionRoot = temp.appendingPathComponent("delete-library")
        let deletionLibrary = SkinLibrary(directory: deletionRoot, trashFile: { url in
            try FileManager.default.moveItem(at: url, to: temp.appendingPathComponent("trashed-" + url.lastPathComponent))
        })
        let deletable = try deletionLibrary.importImage(sourceB)
        try deletionLibrary.record(deletable, deviceID: "one", cardID: "card")
        try deletionLibrary.record(deletable, deviceID: "two", cardID: "card")
        do {
            try deletionLibrary.remove(deletable, protectedURLs: [deletionLibrary.url(for: deletable)])
            preconditionFailure("In-use skins must not be deleted")
        } catch { }
        precondition(deletionLibrary.skins.count == 1)
        precondition(FileManager.default.fileExists(atPath: deletionLibrary.url(for: deletable).path))
        try deletionLibrary.remove(deletable, protectedURLs: [])
        precondition(deletionLibrary.skins.isEmpty)
        precondition(deletionLibrary.history(deviceID: "one", cardID: "card").isEmpty)
        precondition(deletionLibrary.history(deviceID: "two", cardID: "card").isEmpty)
        precondition(!FileManager.default.fileExists(atPath: deletionLibrary.url(for: deletable).path))
        precondition(SkinLibrary(directory: deletionRoot).skins.isEmpty)
        let failingLibrary = SkinLibrary(directory: deletionRoot, trashFile: { _ in
            throw NSError(domain: "TestTrash", code: 1)
        })
        let kept = try failingLibrary.importImage(sourceB)
        do {
            try failingLibrary.remove(kept, protectedURLs: [])
            preconditionFailure("Trash failure should be reported")
        } catch { }
        precondition(failingLibrary.skins.count == 1)
        precondition(SkinLibrary(directory: deletionRoot).skins.count == 1)
        precondition(FileManager.default.fileExists(atPath: failingLibrary.url(for: kept).path))
        precondition(relaunched.setCardImage(for: b, url: sourceB))
        let assignedURL = relaunched.cards.first { $0.id == b }!.customImageURL!
        relaunched.activateCardDevice("another-phone")
        precondition(relaunched.protectedSkinURLs.contains(assignedURL))
        print("Skin deletion, in-use protection across devices, persistence and Trash failure rollback passed")
        // Corrupt indexes must not silently discard an existing library.
        let index = library.directory.appendingPathComponent("index.json")
        let broken = Data("broken index".utf8)
        try broken.write(to: index)
        let corrupt = SkinLibrary(directory: library.directory)
        precondition(corrupt.loadError != nil)
        do {
            try corrupt.importImage(sourceB)
            preconditionFailure("A corrupt index must block writes")
        } catch { }
        let preservedIndex = try Data(contentsOf: index)
        precondition(preservedIndex == broken)
        print("Skin library deduplication, owned copies, restore, isolation, history, invalid input and corrupt-index protection passed")
        print("Wallet view model migration, device isolation, repeat scans, skin identity and clear/relaunch passed")
    }
}
