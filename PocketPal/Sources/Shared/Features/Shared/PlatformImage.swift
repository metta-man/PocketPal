import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

func loadPlatformImage(from url: URL) -> PlatformImage? {
    if let image = PlatformImage(contentsOfFile: url.path()) {
        return image
    }

    guard let data = try? Data(contentsOf: url) else {
        return nil
    }

    return PlatformImage(data: data)
}
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

func loadPlatformImage(from url: URL) -> PlatformImage? {
    if let image = PlatformImage(contentsOf: url) {
        return image
    }

    guard let data = try? Data(contentsOf: url) else {
        return nil
    }

    return PlatformImage(data: data)
}
#endif
