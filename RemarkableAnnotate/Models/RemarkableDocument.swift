import Foundation

struct RemarkableDocument: Identifiable, Decodable {
    let uuid: String
    let title: String

    var id: String { uuid }
}
