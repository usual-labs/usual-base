import Foundation
import Yams

/// Front matter read for display. Writing never goes through this type: the raw YAML text is
/// kept as written, so parsing can't reorder keys or drop comments in the file.
public struct FrontMatter: Equatable, Sendable {
    public struct Property: Equatable, Sendable, Identifiable {
        public enum Value: Equatable, Sendable {
            case text(String)
            case list([String])
            case date(Date)
            case link(URL)
            case flag(Bool)
        }

        /// Nested keys are joined with dots, so `metadata: {type: x}` becomes `metadata.type`.
        public var key: String
        public var value: Value
        public var id: String { key }
    }

    public var properties: [Property]
    /// Why the YAML couldn't be read, when it couldn't.
    public var problem: String?

    public init(yaml: String) {
        do {
            guard let node = try Yams.compose(yaml: yaml) else {
                properties = []
                return
            }
            guard case .mapping(let mapping) = node else {
                properties = []
                problem = "The properties aren't a list of keys and values."
                return
            }
            properties = Self.flatten(mapping, prefix: "")
        } catch {
            properties = []
            problem = "The properties aren't valid YAML."
        }
    }

    /// The first of `title` or `name`.
    public var title: String? { text(for: ["title", "name"]) }
    /// The first of `description` or `summary`.
    public var summary: String? { text(for: ["description", "summary"]) }

    private func text(for keys: [String]) -> String? {
        for key in keys {
            if let property = properties.first(where: { $0.key.lowercased() == key }),
                case .text(let value) = property.value
            {
                return value
            }
        }
        return nil
    }

    private static func flatten(_ mapping: Node.Mapping, prefix: String) -> [Property] {
        var result: [Property] = []
        for (keyNode, valueNode) in mapping {
            let key = prefix + display(keyNode)
            switch valueNode {
            case .mapping(let nested):
                result += flatten(nested, prefix: key + ".")
            case .sequence(let sequence):
                result.append(Property(key: key, value: .list(sequence.map(display))))
            case .scalar(let scalar):
                result.append(Property(key: key, value: value(of: scalar)))
            case .alias:
                result.append(Property(key: key, value: .text(display(valueNode))))
            }
        }
        return result
    }

    private static func value(of scalar: Node.Scalar) -> Property.Value {
        let string = scalar.string
        if scalar.style == .plain {
            if let bool = Bool.construct(from: scalar) { return .flag(bool) }
            if let date = Date.construct(from: scalar) { return .date(date) }
        }
        if let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            return .link(url)
        }
        return .text(string)
    }

    private static func display(_ node: Node) -> String {
        if let string = node.string { return string }
        return ((try? Yams.serialize(node: node)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
