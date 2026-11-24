import Foundation

enum LocalBuild {
    static let isCustom = Bundle.main.bundleIdentifier == "local.couch.tv.custom"
    static let name = "MacTV Custom"
}
