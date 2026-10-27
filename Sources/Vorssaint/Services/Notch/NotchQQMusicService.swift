// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Folder access is explicit and scoped to QQ Music's music-data directory.
/// A bookmark persists the user's choice without requiring full disk access.
final class NotchQQMusicAccess: ObservableObject {
    static let shared = NotchQQMusicAccess()
    private static let bookmarkKey = DefaultsKey.notchQQMusicFolderBookmark
    @Published private(set) var revision = 0
    private var panel: NSOpenPanel?
    var isChoosingFolder: Bool { panel != nil }

    func folder() -> URL {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return NotchQQMusicSupport.defaultFolder }
        var stale = false
        return (try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                         relativeTo: nil, bookmarkDataIsStale: &stale)) ?? NotchQQMusicSupport.defaultFolder
    }

    func chooseFolder() {
        guard panel == nil else { return }
        let text = NotchQQMusicStrings(L10n.shared.language)
        let chooser = NSOpenPanel()
        chooser.canChooseFiles = false
        chooser.canChooseDirectories = true
        chooser.allowsMultipleSelection = false
        chooser.directoryURL = NotchQQMusicSupport.defaultFolder
        chooser.message = text.accessHint
        chooser.prompt = text.connect
        chooser.hidesOnDeactivate = false
        if let parent = NotchService.shared.presentationWindow {
            chooser.level = NSWindow.Level(rawValue: parent.level.rawValue + 1)
        }
        panel = chooser
        chooser.begin { [weak self] response in
            guard let self else { return }
            defer { self.panel = nil }
            guard response == .OK, let url = chooser.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // An arbitrary home directory is not accepted as the integration root.
            guard url.lastPathComponent == "QQMusicMac",
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("iTemp").path),
                  let bookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                       includingResourceValuesForKeys: nil, relativeTo: nil) else {
                let alert = NSAlert(); alert.messageText = text.accessHint; alert.runModal(); return
            }
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            self.revision += 1
        }
    }
}

@MainActor final class NotchQQMusicService: ObservableObject {
    enum State { case loading, ready, access, waiting, unsupported }
    @Published private(set) var identity: NotchMusicIdentity?
    @Published private(set) var state: State = .loading
    @Published private(set) var snapshot: NotchQQMusicSupport.Snapshot?
    @Published private(set) var lyrics: NotchLyrics?
    private let cache = NotchQQMusicSupport.Cache()
    private let work = DispatchQueue(label: "com.vorssaint.qqmusic-read", qos: .utility)

    /// SwiftUI cancels this task on dismissal, player/track changes and a new
    /// folder grant. No polling continues while either page is hidden.
    func follow(_ identity: NotchMusicIdentity, includeLyrics: Bool, folder: URL) async {
        self.identity = identity
        snapshot = nil; lyrics = nil; state = .loading
        var previousLyric: String?
        while !Task.isCancelled {
            let result: Result<NotchQQMusicSupport.Snapshot, Error> = await withCheckedContinuation { continuation in
                work.async { [cache] in
                    let scoped = folder.startAccessingSecurityScopedResource()
                    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
                    continuation.resume(returning: Result {
                        try NotchQQMusicSupport.read(folder: folder, title: identity.title, artist: identity.artist,
                                                    album: identity.album, duration: identity.duration, includeLyrics: includeLyrics, cache: cache)
                    })
                }
            }
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let next):
                if snapshot != next { snapshot = next }
                state = .ready
                if next.lyric != previousLyric {
                    previousLyric = next.lyric
                    lyrics = next.lyric.flatMap { source in
                        let instrumental = source.contains("此歌曲为没有填词的纯音乐")
                        // Some QQ LRCs use a colon before the fractional seconds.
                        let normalized = source.replacingOccurrences(of: #"\[(\d+):(\d{2}):(\d{2,3})\]"#,
                                                                      with: "[$1:$2.$3]", options: .regularExpression)
                        let lines = NotchLyricsSupport.parse(normalized, duration: identity.duration)
                        guard instrumental || !lines.isEmpty else { return nil }
                        return NotchLyrics(lines: instrumental ? [] : lines, plain: "", instrumental: instrumental)
                    }
                }
            case .failure(let error):
                snapshot = nil; lyrics = nil; previousLyric = nil
                switch error as? NotchQQMusicSupport.ReadError {
                case .access: state = .access
                case .unsupported: state = .unsupported
                default: state = .waiting
                }
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }
}
