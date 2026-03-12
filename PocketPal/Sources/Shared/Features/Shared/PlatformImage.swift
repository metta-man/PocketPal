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
    PlatformImage(contentsOfFile: url.path())
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
    PlatformImage(contentsOf: url)
}
#endif
