import Foundation
import SwiftData

@Model
final class BagClub {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    // false hides it from pickers; plans keep referencing clubs by name.
    var isInBag: Bool = true

    init(name: String, sortOrder: Int, isInBag: Bool = true) {
        self.name = name
        self.sortOrder = sortOrder
        self.isInBag = isInBag
    }
}
