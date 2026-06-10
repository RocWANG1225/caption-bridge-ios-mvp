import Foundation

struct TranscriptLine: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var date: Date
    var isFinal: Bool
}
