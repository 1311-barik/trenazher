import AVFoundation
import AVKit
import ImageIO
import SwiftUI

/// Уменьшенные копии картинок и кадры из видео — в памяти, с ограничением размера.
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let cache = NSCache<NSString, CGImageBox>()
    private let queue = DispatchQueue(label: "trenazher.images", qos: .userInitiated, attributes: .concurrent)

    final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    init() {
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func cached(_ url: URL, maxPixel: Int) -> CGImage? {
        cache.object(forKey: key(url, maxPixel))?.image
    }

    /// Картинка с учётом поворота из EXIF, не больше maxPixel по длинной стороне.
    func image(at url: URL, maxPixel: Int, completion: @escaping (CGImage?) -> Void) {
        let cacheKey = key(url, maxPixel)
        if let hit = cache.object(forKey: cacheKey) {
            completion(hit.image)
            return
        }
        let isVideo = ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
        queue.async { [cache] in
            let image = isVideo ? Self.videoFrame(url, maxPixel: maxPixel) : Self.thumbnail(url, maxPixel: maxPixel)
            if let image = image {
                cache.setObject(CGImageBox(image), forKey: cacheKey, cost: image.bytesPerRow * image.height)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    private func key(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(url.lastPathComponent)#\(maxPixel)" as NSString
    }

    private static func thumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func videoFrame(_ url: URL, maxPixel: Int) -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        return try? generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil)
    }
}

/// Фото/кадр упражнения из локального кэша. Если файла ещё нет и есть интернет — докачивает.
struct MediaImage: View {
    @EnvironmentObject private var downloader: MediaDownloader
    @EnvironmentObject private var network: NetworkMonitor
    let media: MediaItem?
    var maxPixel: Int = 400
    var contentMode: ContentMode = .fill

    @State private var image: CGImage?
    @State private var loadedName: String?
    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.cardRaised
            if let image = image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: media?.kind.isVideo == true ? "film" : "photo")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .onAppear(perform: load)
        .onChange(of: media?.localFileName) { _ in load() }
        .onChange(of: downloader.progress[media?.driveFileId ?? ""] == nil) { finished in
            if finished && image == nil { load() }
        }
    }

    private func load() {
        guard let media = media else {
            image = nil
            return
        }
        if let url = downloader.localURL(for: media) {
            if loadedName == url.lastPathComponent, image != nil { return }
            if let cached = ImagePipeline.shared.cached(url, maxPixel: maxPixel) {
                image = cached
                loadedName = url.lastPathComponent
                return
            }
            ImagePipeline.shared.image(at: url, maxPixel: maxPixel) { result in
                image = result
                loadedName = url.lastPathComponent
            }
            // Есть старая версия, а новая ещё не скачана — подкачаем, картинка обновится сама.
            if !downloader.store.hasCurrentVersion(of: media), network.isConnected, !media.kind.isVideo {
                Task { try? await downloader.fetch(media) }
            }
        } else if !media.kind.isVideo, network.isConnected, !failed {
            Task {
                do {
                    try await downloader.fetch(media)
                    load()
                } catch {
                    failed = true
                }
            }
        }
    }
}

/// 1–2 фото упражнения, листаются свайпом.
struct PhotoCarousel: View {
    let photos: [MediaItem]
    @State private var page = 0

    var body: some View {
        Group {
            if photos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.system(size: 30))
                    Text("Фото пока нет").font(.subheadline)
                }
                .foregroundColor(Theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cardRaised)
            } else if photos.count == 1 {
                MediaImage(media: photos[0], maxPixel: 1400, contentMode: .fit)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        MediaImage(media: photo, maxPixel: 1400, contentMode: .fit)
                            .tag(index)
                    }
                }
                .pagedTabStyle(showsIndex: true)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Theme.cardRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(photos.isEmpty ? "Фото пока нет" : "Фото упражнения, \(photos.count) шт."))
    }
}

/// Список видео упражнения. Ничего не запускается само — только по нажатию на конкретное видео.
struct VideoList: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var downloader: MediaDownloader
    @EnvironmentObject private var network: NetworkMonitor
    let videos: [MediaItem]

    @State private var playing: PlayingVideo?
    @State private var errorMessage: String?

    struct PlayingVideo: Identifiable {
        let url: URL
        let title: String
        var id: String { url.lastPathComponent }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Видео", trailing: videos.isEmpty ? nil : "\(videos.count)")
            if videos.isEmpty {
                Text("Видео к этому упражнению пока нет.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            ForEach(videos) { video in
                Button { open(video) } label: { VideoRow(video: video, progress: downloader.progress[video.driveFileId], isLocal: downloader.localURL(for: video) != nil) }
                    .buttonStyle(PlainButtonStyle())
            }
            if let errorMessage = errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundColor(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fullScreenCoverCompat(item: $playing) { video in
            VideoPlayerScreen(url: video.url, title: video.title)
        }
    }

    private func open(_ video: MediaItem) {
        errorMessage = nil
        if let url = downloader.localURL(for: video) {
            playing = PlayingVideo(url: url, title: video.title)
            return
        }
        guard network.isConnected else {
            errorMessage = "Это видео ещё не скачано, а интернета нет. Остальное работает; видео откроется, когда появится связь."
            return
        }
        Task {
            do {
                let url = try await downloader.fetch(video)
                playing = PlayingVideo(url: url, title: video.title)
            } catch {
                let reason = (error as? ContentError)?.errorDescription ?? error.localizedDescription
                errorMessage = "Видео не загрузилось. \(reason) Нажмите на него ещё раз, чтобы повторить."
            }
        }
    }
}

private struct VideoRow: View {
    let video: MediaItem
    let progress: Double?
    let isLocal: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                MediaImage(media: isLocal ? video : nil, maxPixel: 300)
                Circle().fill(Color.black.opacity(0.45)).frame(width: 36, height: 36)
                Image(systemName: "play.fill").foregroundColor(.white)
            }
            .frame(width: 96, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.kind == .ownVideo ? "Видео Жени" : "Обучающее видео")
                    .font(.caption.weight(.bold))
                    .foregroundColor(video.kind == .ownVideo ? Theme.accent : Theme.blue)
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                if let progress = progress {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: Theme.blue))
                    Text("Загружается… \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                } else {
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(10)
        .card()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Открыть и воспроизвести"))
    }

    private var statusText: String {
        if isLocal { return "Скачано · смотреть без интернета" }
        if let size = video.byteSize { return "Скачать и смотреть · \(Formatters.megabytes(size))" }
        return "Скачать и смотреть"
    }
}

/// Полноэкранный плеер. Открывается только по нажатию на видео — это и есть команда «смотреть».
struct VideoPlayerScreen: View {
    let url: URL
    let title: String
    @Environment(\.presentationMode) private var presentationMode
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            Button {
                player?.pause()
                presentationMode.wrappedValue.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconButtonStyle())
            .padding(16)
            .accessibilityLabel(Text("Закрыть видео"))
        }
        .onAppear {
            AudioSessionConfigurator.prepareForVideo()
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
