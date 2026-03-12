import Foundation

enum ReceiptProcessingState: String, Codable, CaseIterable, Sendable {
    case queued
    case runningOCR
    case ready
    case failed

    var isActive: Bool {
        switch self {
        case .queued, .runningOCR:
            return true
        case .ready, .failed:
            return false
        }
    }
}
