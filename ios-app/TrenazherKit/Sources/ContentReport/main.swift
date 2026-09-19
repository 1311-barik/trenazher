import Foundation
import TrenazherKit

// Утилита проверки контента: собирает манифест тем же кодом, что и приложение,
// и печатает отчёт — какие файлы к каким упражнениям привязались и что поправить.
//
// Из живой таблицы и папок Drive:
//   swift run content-report --api-key KEY --spreadsheet ID --folder ID [--out manifest.json]
// Из выгрузки (CSV таблицы + JSON со списком файлов):
//   swift run content-report --csv sheet.csv [--workouts-csv w.csv] [--files files.json] [--out manifest.json]

struct Arguments {
    var values: [String: String] = [:]

    init(_ raw: [String]) {
        var index = 0
        while index < raw.count {
            let key = raw[index]
            if key.hasPrefix("--"), index + 1 < raw.count {
                values[String(key.dropFirst(2))] = raw[index + 1]
                index += 2
            } else {
                index += 1
            }
        }
    }

    subscript(_ key: String) -> String? { values[key] }
}

struct FileListing: Decodable {
    var photos: [DriveFile]
    var ownVideos: [DriveFile]
    var otherVideos: [DriveFile]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func readCSV(_ path: String) -> [[String]] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("Не удалось прочитать \(path)") }
    return CSVParser.parse(text)
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
let snapshot: ContentSnapshot

if let apiKey = arguments["api-key"] {
    guard let spreadsheet = arguments["spreadsheet"], let folder = arguments["folder"] else {
        fail("Нужны --spreadsheet и --folder")
    }
    let source = GoogleContentSource(config: GoogleContentConfig(apiKey: apiKey, spreadsheetId: spreadsheet, rootFolderId: folder),
                                     http: URLSessionHTTPClient())
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<ContentSnapshot, Error>!
    Task {
        do { result = .success(try await source.fetchSnapshot()) } catch { result = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    switch result! {
    case .success(let value): snapshot = value
    case .failure(let error): fail("Ошибка загрузки: \(error.localizedDescription)")
    }
} else if let csvPath = arguments["csv"] {
    var listing = FileListing(photos: [], ownVideos: [], otherVideos: [])
    if let filesPath = arguments["files"] {
        guard let data = FileManager.default.contents(atPath: filesPath),
              let decoded = try? JSONDecoder().decode(FileListing.self, from: data) else { fail("Не удалось прочитать \(filesPath)") }
        listing = decoded
    }
    snapshot = ContentSnapshot(exerciseRows: readCSV(csvPath), workoutRows: arguments["workouts-csv"].map(readCSV) ?? [],
                               photos: listing.photos, ownVideos: listing.ownVideos, otherVideos: listing.otherVideos)
} else {
    fail("""
    Использование:
      content-report --api-key KEY --spreadsheet ID --folder ID [--out manifest.json]
      content-report --csv sheet.csv [--workouts-csv w.csv] [--files files.json] [--out manifest.json]
    """)
}

let manifest = ManifestBuilder.build(from: snapshot)
print(ContentReportFormatter.markdown(for: manifest))

if let out = arguments["out"] {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
        try encoder.encode(manifest).write(to: URL(fileURLWithPath: out))
        FileHandle.standardError.write("Манифест сохранён: \(out)\n".data(using: .utf8)!)
    } catch {
        fail("Не удалось сохранить манифест: \(error.localizedDescription)")
    }
}
