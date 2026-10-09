import AppKit
import Foundation

enum AppIconStyle: String, CaseIterable, Identifiable, Sendable {
    case defaultIcon
    case dark
    case clearLight
    case clearDark
    case tintedLight
    case tintedDark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultIcon: "Default"
        case .dark: "Dark"
        case .clearLight: "Clear Light"
        case .clearDark: "Clear Dark"
        case .tintedLight: "Tinted Light"
        case .tintedDark: "Tinted Dark"
        }
    }

    var resourceName: String {
        let variant: String
        switch self {
        case .defaultIcon: variant = "Default"
        case .dark: variant = "Dark"
        case .clearLight: variant = "ClearLight"
        case .clearDark: variant = "ClearDark"
        case .tintedLight: variant = "TintedLight"
        case .tintedDark: variant = "TintedDark"
        }
        return "Untitled-macOS-\(variant)-1024x1024@1x"
    }

    var image: NSImage? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png", subdirectory: "AppIcons") else { return nil }
        return NSImage(contentsOf: url)
    }
}
