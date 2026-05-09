import Foundation

indirect enum DeviceNode: Identifiable, Decodable {
    case document(uuid: String, title: String)
    case folder(uuid: String, title: String, children: [DeviceNode])

    var id: String {
        switch self {
        case .document(let uuid, _): return uuid
        case .folder(let uuid, _, _): return uuid
        }
    }

    var title: String {
        switch self {
        case .document(_, let t): return t
        case .folder(_, let t, _): return t
        }
    }

    // MARK: Decodable

    private enum CodingKeys: String, CodingKey {
        case kind, uuid, title, children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        let uuid = try c.decode(String.self, forKey: .uuid)
        let title = try c.decode(String.self, forKey: .title)
        if kind == "folder" {
            let children = try c.decodeIfPresent([DeviceNode].self, forKey: .children) ?? []
            self = .folder(uuid: uuid, title: title, children: children)
        } else {
            self = .document(uuid: uuid, title: title)
        }
    }
}
