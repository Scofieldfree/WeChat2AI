import Foundation

/// Single serial executor shared by both development interfaces.
final class AppOperations {
    private let worker = DispatchQueue(label: "local.scofield.wechat2ai.library", qos: .userInitiated)
    func perform<T>(_ task: @escaping () throws -> T, completion: @escaping @MainActor (Result<T, Error>) -> Void) {
        worker.async {
            let result = Result { try task() }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
