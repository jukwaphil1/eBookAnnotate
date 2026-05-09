import Foundation

struct RemarkableDocument: Identifiable, Decodable {
    let uuid: String
    let title: String
    let highlightCount: Int
    let pageCount: Int

    var id: String { uuid }

    enum CodingKeys: String, CodingKey {
        case uuid, title
        case highlightCount = "highlight_count"
        case pageCount = "page_count"
    }
}
