import Foundation

struct KindleBook: Identifiable {
    let id: String          // title used as stable key
    let title: String
    let author: String
    let highlightCount: Int
    let clippingsPath: String
}
