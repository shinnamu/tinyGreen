import Foundation
import os

let bundleID = "fyi.shinnamu.tinyGreen"

extension Logger {
    static func tinyGreen(_ category: String) -> Logger {
        Logger(subsystem: bundleID, category: category)
    }
}
