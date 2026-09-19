import Foundation

/// Ошибки загрузки контента — с текстами, которые можно показать Андрею как есть.
public enum ContentError: LocalizedError, Equatable {
    case notConfigured
    case offline
    case accessDenied
    case invalidAPIKey
    case notFound(String)
    case outOfSpace
    case http(Int)
    case invalidData(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Источник контента не настроен: в сборке нет API-ключа Google или ID таблицы."
        case .offline:
            return "Нет интернета. Всё, что уже скачано, работает как обычно."
        case .accessDenied:
            return "Нет доступа к таблице или папке на Google Drive. Проверьте, что включён доступ «Все, у кого есть ссылка»."
        case .invalidAPIKey:
            return "Google отклонил API-ключ. Нужно проверить ключ в Google Cloud Console."
        case .notFound(let what):
            return "Не найдено на Google Drive: \(what)."
        case .outOfSpace:
            return "На устройстве не хватает места. Освободите место или удалите скачанные видео в Настройках."
        case .http(let code):
            return "Сервер Google ответил ошибкой \(code). Попробуйте позже."
        case .invalidData(let details):
            return "Не удалось разобрать ответ Google: \(details)."
        }
    }

    /// Ошибки, после которых нет смысла продолжать качать остальные файлы.
    public var stopsSync: Bool {
        switch self {
        case .offline, .outOfSpace, .accessDenied, .invalidAPIKey, .notConfigured: return true
        default: return false
        }
    }

    static func from(_ error: Error) -> ContentError {
        if let content = error as? ContentError { return content }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDataNotAllowed,
                 NSURLErrorInternationalRoamingOff:
                return .offline
            case NSURLErrorCannotWriteToFile, NSURLErrorCannotCreateFile:
                return .outOfSpace
            default:
                return .http(nsError.code)
            }
        }
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return .outOfSpace
        }
        return .invalidData(error.localizedDescription)
    }
}

/// Минимальный HTTP-клиент. Протокол — чтобы подменять сеть в тестах.
public protocol HTTPClient: AnyObject {
    func data(from url: URL) async throws -> (Data, HTTPURLResponse)
    /// Скачивает файл во временное место и атомарно перемещает в `destination`.
    func download(from url: URL, to destination: URL, progress: ((Double) -> Void)?) async throws
}

/// Реализация на URLSession с completion handler'ами: async-методы URLSession появились только в iOS 15.
public final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = URLSessionHTTPClient.makeDefaultSession()) {
        self.session = session
    }

    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 30
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    public func data(from url: URL) async throws -> (Data, HTTPURLResponse) {
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                let task = session.dataTask(with: url) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let http = response as? HTTPURLResponse {
                        continuation.resume(returning: (data ?? Data(), http))
                    } else {
                        continuation.resume(throwing: ContentError.invalidData("пустой ответ"))
                    }
                }
                box.start(task)
            }
        } onCancel: {
            box.cancel()
        }
    }

    public func download(from url: URL, to destination: URL, progress: ((Double) -> Void)?) async throws {
        let box = TaskBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.downloadTask(with: url) { tempURL, response, error in
                    box.observation?.invalidate()
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let http = response as? HTTPURLResponse, let tempURL = tempURL else {
                        continuation.resume(throwing: ContentError.invalidData("пустой ответ"))
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        let body = (try? Data(contentsOf: tempURL)) ?? Data()
                        continuation.resume(throwing: GoogleErrorMapper.error(status: http.statusCode, body: body))
                        return
                    }
                    // Временный файл удаляется сразу после выхода из обработчика — перемещаем здесь.
                    do {
                        let fileManager = FileManager.default
                        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        if fileManager.fileExists(atPath: destination.path) {
                            try fileManager.removeItem(at: destination)
                        }
                        try fileManager.moveItem(at: tempURL, to: destination)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                if let progress = progress {
                    box.observation = task.progress.observe(\.fractionCompleted) { value, _ in
                        progress(value.fractionCompleted)
                    }
                }
                box.start(task)
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// Держит задачу URLSession, чтобы её можно было отменить из onCancel (он может прийти раньше старта).
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var isCancelled = false
    var observation: NSKeyValueObservation?

    func start(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let cancelled = isCancelled
        lock.unlock()
        if cancelled { task.cancel() } else { task.resume() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

/// Перевод ответов Google API в понятные ошибки.
enum GoogleErrorMapper {
    static func error(status: Int, body: Data) -> ContentError {
        let text = String(data: body, encoding: .utf8) ?? ""
        switch status {
        case 400 where text.contains("API key") || text.contains("API_KEY"):
            return .invalidAPIKey
        case 401, 403:
            if text.contains("API key") || text.contains("API_KEY") || text.contains("apiKey") { return .invalidAPIKey }
            return .accessDenied
        case 404:
            return .notFound("файл или таблица")
        default:
            return .http(status)
        }
    }
}
