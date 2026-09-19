import Foundation
import Testing
@testable import TrenazherKit

@Suite("Сессия тренировки")
struct WorkoutSessionTests {
    func makeSession(_ ids: [String] = ["a", "b", "c"]) -> WorkoutSession {
        WorkoutSession(kind: .custom, title: "Руки", bodyParts: ["Руки"], exerciseIds: ids, now: Date(timeIntervalSince1970: 0))
    }

    @Test func goesThroughListAndAsksForMore() {
        var session = makeSession()
        session.next()
        session.next()
        #expect(session.currentExerciseId == "c")
        #expect(session.phase == .exercising)
        session.next()
        #expect(session.phase == .askingMore)
        #expect(session.completedExerciseIds == ["a", "b", "c"])
    }

    @Test func everyStepHasReverse() {
        var session = makeSession()
        session.markSetDone(totalSets: 3)
        session.markSetDone(totalSets: 3)
        session.undoSet()
        #expect(session.currentSetsDone == 1)

        session.next()
        session.previous()
        #expect(session.currentExerciseId == "a")
        #expect(session.currentSetsDone == 1, "подходы не теряются при возврате")

        session.next(); session.next(); session.next()
        #expect(session.phase == .askingMore)
        session.previous()
        #expect(session.phase == .exercising)
        #expect(session.currentExerciseId == "c")

        session.next()
        session.wantMore()
        #expect(session.phase == .pickingMore)
        session.cancelPicking()
        #expect(session.phase == .askingMore)
    }

    @Test func setsAreCappedByKnownCount() {
        var session = makeSession()
        for _ in 0..<5 { session.markSetDone(totalSets: 3) }
        #expect(session.currentSetsDone == 3)
        // Без числа подходов — считаем без ограничения.
        session.next()
        for _ in 0..<5 { session.markSetDone(totalSets: nil) }
        #expect(session.currentSetsDone == 5)
    }

    @Test func addingMoreContinuesFromFirstNewExercise() {
        var session = makeSession(["a"])
        session.next()
        session.wantMore()
        session.append(["b", "a"], bodyParts: ["Попа"])
        #expect(session.phase == .exercising)
        #expect(session.currentExerciseId == "b")
        #expect(session.bodyParts == ["Руки", "Попа"])
        session.next(); session.next()
        #expect(session.phase == .askingMore)
        // Повтор допустим: «a» в истории дважды — это два разных захода.
        #expect(session.completedExerciseIds == ["a", "b", "a"])
    }

    @Test func emptyAddReturnsToQuestion() {
        var session = makeSession(["a"])
        session.next()
        session.wantMore()
        session.append([])
        #expect(session.phase == .askingMore)
    }

    @Test func historyCountsCurrentExerciseOnlyIfStarted() {
        var session = makeSession()
        session.next()
        let names: (String) -> String? = { $0.uppercased() }
        #expect(session.historyEntry(names: names)?.exerciseIds == ["a"])
        session.markSetDone(totalSets: nil)
        #expect(session.historyEntry(names: names)?.exerciseIds == ["a", "b"])
        #expect(session.historyEntry(names: names)?.exerciseNames == ["A", "B"])
        #expect(makeSession().historyEntry(names: names) == nil, "пустая тренировка в историю не попадает")
    }

    @Test func survivesEncoding() throws {
        var session = makeSession()
        session.markSetDone(totalSets: nil)
        session.next()
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(WorkoutSession.self, from: data)
        #expect(decoded == session)
    }

    @Test func estimateMatchesRecommendation() {
        #expect(WorkoutEstimate.minutes(forExerciseCount: 10) == 40...60)
        #expect(RussianPlural.exercises(1) == "1 упражнение")
        #expect(RussianPlural.exercises(3) == "3 упражнения")
        #expect(RussianPlural.exercises(11) == "11 упражнений")
        #expect(RussianPlural.exercises(22) == "22 упражнения")
    }
}

@MainActor
@Suite("Сохранение прогресса и пользовательские данные")
struct ControllerTests {
    func makeContent() -> ContentRepository {
        ContentRepository(manifest: ManifestBuilder.build(from: Fixtures.snapshot))
    }

    @Test func sessionRestoresAfterRelaunch() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("s.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let content = makeContent()
        let userData = UserDataStore(cloudKitContainerId: nil, inMemory: true)

        let first = SessionController(fileURL: file, userData: userData, content: content)
        first.startCustom(exerciseIds: ["руки/молот", "руки/диагональный молот"], bodyParts: ["Руки"])
        first.update { $0.markSetDone(totalSets: nil) }
        first.update { $0.next() }

        // «Перезапуск приложения».
        let second = SessionController(fileURL: file, userData: userData, content: content)
        #expect(second.session?.currentExerciseId == "руки/диагональный молот")
        #expect(second.currentExercise?.name == "Диагональный молот")

        let entry = second.finish()
        #expect(entry?.exerciseNames == ["Молот"])
        #expect(userData.history.count == 1)
        #expect(second.session == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func favoritesToggleAndHistoryUndo() {
        let store = UserDataStore(cloudKitContainerId: nil, inMemory: true)
        #expect(store.toggleFavorite(itemId: "руки/молот", type: .exercise, title: "Молот"))
        #expect(store.isFavorite("руки/молот", type: .exercise))
        #expect(!store.toggleFavorite(itemId: "руки/молот", type: .exercise, title: "Молот"))
        #expect(store.favorites.isEmpty)

        let entry = HistoryEntry(startedAt: Date(timeIntervalSince1970: 0), finishedAt: Date(timeIntervalSince1970: 3600), kind: .custom,
                                 title: "Руки", bodyParts: ["Руки"], exerciseIds: ["a"], exerciseNames: ["A"])
        store.addHistory(entry)
        store.deleteHistory(id: entry.id)
        #expect(store.history.isEmpty)
        // «Отменить» возвращает ту же запись, без дублей.
        store.addHistory(entry)
        store.addHistory(entry)
        #expect(store.history == [entry])
    }

    @Test func draftSurvivesAndPrunesRemovedContent() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let content = makeContent()
        let draft = CustomWorkoutDraft(defaults: defaults)
        draft.toggleBodyPart("Попа", order: content.bodyParts)
        draft.toggleBodyPart("Руки", order: content.bodyParts)
        #expect(draft.bodyParts == ["Руки", "Попа"], "части тела — в порядке таблицы")
        draft.toggleExercise("попа/приседание сумо")
        draft.toggleExercise("руки/молот")
        draft.toggleExercise("руки/удалённое")

        let restored = CustomWorkoutDraft(defaults: defaults)
        #expect(restored.exerciseIds.count == 3)
        restored.prune(using: content)
        #expect(restored.orderedSelection(in: content) == ["руки/молот", "попа/приседание сумо"])
    }

    @Test func settingsPreferNewerCopyFromOtherDevice() {
        let cloud = InMemoryKeyValueStore()
        let iphone = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, cloud: cloud)
        iphone.settings.restDurationSeconds = 30
        let ipad = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, cloud: cloud)
        #expect(ipad.settings.restDurationSeconds == 30)
        ipad.settings.restTimerEnabled = false
        iphone.applyRemoteIfNewer()
        #expect(iphone.settings.restTimerEnabled == false)
        #expect(iphone.settings.restDurationSeconds == 30)
    }

    @Test func settingsWorkLocallyWithoutICloud() {
        // Без платного аккаунта iCloud не подключён — настройки живут в UserDefaults устройства.
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = SettingsStore(defaults: defaults)
        #expect(!first.isSyncedAcrossDevices)
        first.settings.restDurationSeconds = 30
        first.applyRemoteIfNewer()
        let second = SettingsStore(defaults: defaults)
        #expect(second.settings.restDurationSeconds == 30)
    }

    @Test func restTimerCountsFromEndDate() {
        var now = Date(timeIntervalSince1970: 1000)
        let timer = RestTimer(notifications: nil, now: { now })
        var finished = false
        timer.onFinish = { finished = true }
        timer.start(seconds: 60)
        #expect(timer.remaining == 60)
        now += 45
        timer.tick()
        #expect(timer.remaining == 15)
        timer.extend(by: 15)
        #expect(timer.remaining == 30)
        now += 31
        timer.tick()
        #expect(timer.state == .finished)
        #expect(finished)
    }
}

/// Сеть-заглушка: отдаёт файлы или ошибку по списку.
final class FakeHTTPClient: HTTPClient {
    var failingIds: Set<String> = []
    var offlineAfter: Int?
    private(set) var downloads: [String] = []

    func data(from url: URL) async throws -> (Data, HTTPURLResponse) {
        throw ContentError.offline
    }

    func download(from url: URL, to destination: URL, progress: ((Double) -> Void)?) async throws {
        let id = url.lastPathComponent
        if let limit = offlineAfter, downloads.count >= limit { throw URLError(.notConnectedToInternet) }
        if failingIds.contains(id) { throw ContentError.http(500) }
        downloads.append(id)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(id.utf8).write(to: destination)
        progress?(1)
    }
}

@MainActor
@Suite("Синхронизация контента")
struct SyncTests {
    func makeSystem(http: FakeHTTPClient, prefetchVideos: Bool = true) -> (ContentSyncService, ContentRepository, ContentStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ContentStore(rootURL: root)
        let repository = ContentRepository()
        let rows = [["Часть тела", "Упражнение", "Фото", "Чужое видео"], ["Руки", "Молот", "", ""], ["", "Мертвый жук", "", ""]]
        let source = StaticContentSource(snapshot: ContentSnapshot(
            exerciseRows: rows,
            photos: [DriveFile(id: "p1", name: "Руки. Молот.jpg"), DriveFile(id: "p2", name: "Руки. Мертвый жук.jpg")],
            otherVideos: [DriveFile(id: "v1", name: "Руки. Молот.mov")]
        ))
        let downloader = MediaDownloader(store: store, source: source, http: http)
        let sync = ContentSyncService(repository: repository, source: source, downloader: downloader,
                                      network: NetworkMonitor(fixedConnected: true), defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                      prefetchVideos: { prefetchVideos })
        return (sync, repository, store, root)
    }

    @Test func downloadsPhotosThenVideosAndSavesManifest() async {
        let http = FakeHTTPClient()
        let (sync, repository, store, root) = makeSystem(http: http)
        defer { try? FileManager.default.removeItem(at: root) }
        await sync.performSync()
        #expect(repository.manifest.exercises.count == 2)
        #expect(http.downloads == ["p1", "p2", "v1"])
        #expect(sync.pendingDownloads == 0)
        #expect(sync.lastError == nil)
        #expect(store.loadManifest()?.contentVersion == repository.manifest.contentVersion)
    }

    @Test func resumesAfterConnectionLoss() async {
        let http = FakeHTTPClient()
        http.offlineAfter = 1
        let (sync, _, _, root) = makeSystem(http: http)
        defer { try? FileManager.default.removeItem(at: root) }
        await sync.performSync()
        #expect(sync.lastError == .offline)
        #expect(sync.pendingDownloads == 2)

        // Связь вернулась — докачиваются только недостающие файлы.
        http.offlineAfter = nil
        await sync.performSync()
        #expect(http.downloads == ["p1", "p2", "v1"])
        #expect(sync.pendingDownloads == 0)
    }

    @Test func singleFailedFileDoesNotStopTheRest() async {
        let http = FakeHTTPClient()
        http.failingIds = ["p1"]
        let (sync, _, _, root) = makeSystem(http: http, prefetchVideos: false)
        defer { try? FileManager.default.removeItem(at: root) }
        await sync.performSync()
        #expect(http.downloads == ["p2"], "видео заранее не качаются, если выключено")
        #expect(sync.failedDownloads == 1)
        #expect(sync.pendingDownloads == 1)
    }

    @Test func offlineKeepsExistingContent() async {
        let http = FakeHTTPClient()
        let (sync, repository, _, root) = makeSystem(http: http)
        defer { try? FileManager.default.removeItem(at: root) }
        await sync.performSync()
        let before = repository.manifest

        let offlineSync = ContentSyncService(repository: repository, source: StaticContentSource(snapshot: nil, error: .offline),
                                             downloader: MediaDownloader(store: ContentStore(rootURL: root), source: StaticContentSource(snapshot: nil), http: http),
                                             network: NetworkMonitor(fixedConnected: true), defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                             prefetchVideos: { true })
        await offlineSync.performSync()
        #expect(offlineSync.lastError == .offline)
        #expect(repository.manifest == before)
    }
}
