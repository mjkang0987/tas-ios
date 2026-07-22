import Foundation

/// Generic async load state for view models.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case let .loaded(value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var errorMessage: String? {
        if case let .failed(message) = self { return message }
        return nil
    }
}
