import CoreData
import Foundation

/// Элемент избранного.
public struct FavoriteItem: Hashable, Identifiable {
    public enum ItemType: String, Hashable {
        case exercise, workout
    }

    public var itemId: String
    public var type: ItemType
    /// Название на момент добавления — чтобы показать запись, даже если Женя переименует или уберёт упражнение.
    public var title: String
    public var createdAt: Date

    public var id: String { "\(type.rawValue):\(itemId)" }

    public init(itemId: String, type: ItemType, title: String, createdAt: Date = Date()) {
        self.itemId = itemId
        self.type = type
        self.title = title
        self.createdAt = createdAt
    }
}

/// Запись истории — завершённая тренировка.
public struct HistoryEntry: Hashable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var kind: WorkoutKind
    public var title: String
    public var bodyParts: [String]
    public var exerciseIds: [String]
    /// Названия — снимок на момент тренировки (контент может поменяться).
    public var exerciseNames: [String]

    public init(id: UUID = UUID(), startedAt: Date, finishedAt: Date, kind: WorkoutKind, title: String,
                bodyParts: [String], exerciseIds: [String], exerciseNames: [String]) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.kind = kind
        self.title = title
        self.bodyParts = bodyParts
        self.exerciseIds = exerciseIds
        self.exerciseNames = exerciseNames
    }

    public var exerciseCount: Int { exerciseIds.count }
    public var duration: TimeInterval { max(0, finishedAt.timeIntervalSince(startedAt)) }
}

/// Избранное и история. Хранятся в Core Data и зеркалируются в приватную базу CloudKit
/// на Apple ID Андрея — так они сами появляются и на iPhone, и на iPad, без своего сервера.
@MainActor
public final class UserDataStore: ObservableObject {
    @Published public private(set) var favorites: [FavoriteItem] = []
    @Published public private(set) var history: [HistoryEntry] = []
    /// Не удалось открыть хранилище — показываем честно, а не делаем вид, что всё сохраняется.
    @Published public private(set) var storageError: String?

    public let isCloudSyncEnabled: Bool
    private let container: NSPersistentContainer
    private var context: NSManagedObjectContext { container.viewContext }
    private var observers: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - cloudKitContainerId: ID контейнера iCloud («iCloud.com.…»); nil — только локально (превью, тесты, сборка без платного аккаунта).
    ///   - inMemory: хранилище в памяти — для тестов и превью.
    public init(cloudKitContainerId: String?, inMemory: Bool = false, storeURL: URL? = nil) {
        let model = UserDataModel.shared
        let useCloud = !inMemory && !(cloudKitContainerId ?? "").isEmpty
        let container: NSPersistentContainer = useCloud
            ? NSPersistentCloudKitContainer(name: "UserData", managedObjectModel: model)
            : NSPersistentContainer(name: "UserData", managedObjectModel: model)

        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        } else {
            let url = storeURL ?? UserDataStore.defaultStoreURL()
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            description = NSPersistentStoreDescription(url: url)
        }
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        if useCloud, let id = cloudKitContainerId {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: id)
        }
        container.persistentStoreDescriptions = [description]
        self.container = container
        self.isCloudSyncEnabled = useCloud

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let error = loadError {
            storageError = "Не удалось открыть хранилище избранного и истории: \(error.localizedDescription). Новые записи не сохранятся до перезапуска приложения."
        }
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Изменения, пришедшие из iCloud с другого устройства.
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        })
        reload()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    public nonisolated static func defaultStoreURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UserData", isDirectory: true)
            .appendingPathComponent("UserData.sqlite")
    }

    // MARK: - Избранное

    public func isFavorite(_ itemId: String, type: FavoriteItem.ItemType) -> Bool {
        favorites.contains { $0.itemId == itemId && $0.type == type }
    }

    /// Переключает отметку ♡. Возвращает новое состояние.
    @discardableResult
    public func toggleFavorite(itemId: String, type: FavoriteItem.ItemType, title: String) -> Bool {
        if isFavorite(itemId, type: type) {
            removeFavorite(itemId: itemId, type: type)
            return false
        }
        addFavorite(FavoriteItem(itemId: itemId, type: type, title: title))
        return true
    }

    public func addFavorite(_ item: FavoriteItem) {
        guard !isFavorite(item.itemId, type: item.type) else { return }
        let object = NSManagedObject(entity: UserDataModel.favoriteEntity(in: context), insertInto: context)
        object.setValue(item.itemId, forKey: "itemId")
        object.setValue(item.type.rawValue, forKey: "itemType")
        object.setValue(item.title, forKey: "title")
        object.setValue(item.createdAt, forKey: "createdAt")
        save()
    }

    public func removeFavorite(itemId: String, type: FavoriteItem.ItemType) {
        let request = NSFetchRequest<NSManagedObject>(entityName: UserDataModel.favoriteName)
        request.predicate = NSPredicate(format: "itemId == %@ AND itemType == %@", itemId, type.rawValue)
        for object in (try? context.fetch(request)) ?? [] {
            context.delete(object)
        }
        save()
    }

    // MARK: - История

    public func addHistory(_ entry: HistoryEntry) {
        let request = NSFetchRequest<NSManagedObject>(entityName: UserDataModel.historyName)
        request.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        // Повторное сохранение той же тренировки (например, после «Отменить удаление») не создаёт дубль.
        let object = (try? context.fetch(request))?.first
            ?? NSManagedObject(entity: UserDataModel.historyEntity(in: context), insertInto: context)
        object.setValue(entry.id, forKey: "entryId")
        object.setValue(entry.startedAt, forKey: "startedAt")
        object.setValue(entry.finishedAt, forKey: "finishedAt")
        object.setValue(entry.kind.rawValue, forKey: "kind")
        object.setValue(entry.title, forKey: "title")
        object.setValue(UserDataModel.join(entry.bodyParts), forKey: "bodyParts")
        object.setValue(UserDataModel.join(entry.exerciseIds), forKey: "exerciseIds")
        object.setValue(UserDataModel.join(entry.exerciseNames), forKey: "exerciseNames")
        save()
    }

    public func deleteHistory(id: UUID) {
        let request = NSFetchRequest<NSManagedObject>(entityName: UserDataModel.historyName)
        request.predicate = NSPredicate(format: "entryId == %@", id as CVarArg)
        for object in (try? context.fetch(request)) ?? [] {
            context.delete(object)
        }
        save()
    }

    // MARK: - Загрузка

    public func reload() {
        let favoriteRequest = NSFetchRequest<NSManagedObject>(entityName: UserDataModel.favoriteName)
        favoriteRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let favoriteObjects = (try? context.fetch(favoriteRequest)) ?? []

        // Одно и то же могли отметить офлайн на двух устройствах — после синхронизации убираем дубли.
        var seen = Set<String>()
        var loadedFavorites: [FavoriteItem] = []
        var hasDuplicates = false
        for object in favoriteObjects {
            guard let itemId = object.value(forKey: "itemId") as? String,
                  let rawType = object.value(forKey: "itemType") as? String,
                  let type = FavoriteItem.ItemType(rawValue: rawType) else { continue }
            let item = FavoriteItem(itemId: itemId, type: type, title: object.value(forKey: "title") as? String ?? "",
                                    createdAt: object.value(forKey: "createdAt") as? Date ?? Date())
            if seen.insert(item.id).inserted {
                loadedFavorites.append(item)
            } else {
                context.delete(object)
                hasDuplicates = true
            }
        }
        if hasDuplicates { save(reloadAfter: false) }
        favorites = loadedFavorites

        let historyRequest = NSFetchRequest<NSManagedObject>(entityName: UserDataModel.historyName)
        historyRequest.sortDescriptors = [NSSortDescriptor(key: "finishedAt", ascending: false)]
        history = ((try? context.fetch(historyRequest)) ?? []).compactMap { object in
            guard let id = object.value(forKey: "entryId") as? UUID,
                  let started = object.value(forKey: "startedAt") as? Date,
                  let finished = object.value(forKey: "finishedAt") as? Date else { return nil }
            return HistoryEntry(
                id: id, startedAt: started, finishedAt: finished,
                kind: WorkoutKind(rawValue: object.value(forKey: "kind") as? String ?? "") ?? .custom,
                title: object.value(forKey: "title") as? String ?? "",
                bodyParts: UserDataModel.split(object.value(forKey: "bodyParts") as? String),
                exerciseIds: UserDataModel.split(object.value(forKey: "exerciseIds") as? String),
                exerciseNames: UserDataModel.split(object.value(forKey: "exerciseNames") as? String)
            )
        }
    }

    private func save(reloadAfter: Bool = true) {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                context.rollback()
                storageError = "Не удалось сохранить изменение: \(error.localizedDescription). Попробуйте ещё раз."
            }
        }
        if reloadAfter { reload() }
    }
}

/// Модель Core Data, описанная в коде (без .xcdatamodeld — пакет собирается без Xcode).
/// Требования CloudKit: все атрибуты необязательные, без уникальных ограничений, массивы — строками.
enum UserDataModel {
    static let favoriteName = "FavoriteRecord"
    static let historyName = "HistoryRecord"
    private static let separator = "\n"

    /// Одна модель на процесс: несколько экземпляров одной модели сбивают Core Data с толку.
    static let shared: NSManagedObjectModel = {
        let favorite = NSEntityDescription()
        favorite.name = favoriteName
        favorite.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        favorite.properties = [
            attribute("itemId", .stringAttributeType),
            attribute("itemType", .stringAttributeType),
            attribute("title", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
        ]

        let history = NSEntityDescription()
        history.name = historyName
        history.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        history.properties = [
            attribute("entryId", .UUIDAttributeType),
            attribute("startedAt", .dateAttributeType),
            attribute("finishedAt", .dateAttributeType),
            attribute("kind", .stringAttributeType),
            attribute("title", .stringAttributeType),
            attribute("bodyParts", .stringAttributeType),
            attribute("exerciseIds", .stringAttributeType),
            attribute("exerciseNames", .stringAttributeType),
        ]

        let model = NSManagedObjectModel()
        model.entities = [favorite, history]
        return model
    }()

    private static func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        return attribute
    }

    static func favoriteEntity(in context: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: favoriteName, in: context)!
    }

    static func historyEntity(in context: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: historyName, in: context)!
    }

    static func join(_ values: [String]) -> String { values.joined(separator: separator) }

    static func split(_ value: String?) -> [String] {
        guard let value = value, !value.isEmpty else { return [] }
        return value.components(separatedBy: separator)
    }
}
