// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchQQMusicView: View {
    let playback: NotchPlayback
    let showsLyrics: Bool
    @Environment(\.notchSettingsPreview) private var preview
    @StateObject private var service = NotchQQMusicService()
    @ObservedObject private var access = NotchQQMusicAccess.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchQQMusicStrings { NotchQQMusicStrings(l10n.language) }
    private var common: NotchMusicExtrasStrings { FeatureStrings.notchMusicExtras(l10n.language) }
    private struct Request: Hashable {
        let identity: NotchMusicIdentity
        let lyrics: Bool
        let accessRevision: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(showsLyrics ? "QQ Music · \(common.lyrics)" : text.playlist)
                    .font(.callout.weight(.semibold))
                Spacer()
                Button(action: access.chooseFolder) { Image(systemName: "folder.badge.gearshape") }
                    .buttonStyle(.borderless).help(text.connect).accessibilityLabel(text.connect)
            }
            if service.identity != NotchMusicIdentity(playback) || service.state == .loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.state == .access {
                NotchEmptyView(symbol: "folder", message: text.accessHint) {
                    NotchPillButton(title: text.connect, prominent: true, action: access.chooseFolder)
                }
            } else if service.state == .unsupported || service.state == .waiting {
                empty(service.state == .unsupported ? text.unsupported : text.waiting)
            } else if showsLyrics {
                if let lyrics = service.lyrics {
                    if lyrics.instrumental {
                        empty(common.instrumental)
                    } else if playback.hasPosition {
                        NotchSyncedLyricsView(lyrics: lyrics, playback: playback, offset: 0, text: common)
                    } else {
                        Text(common.noPosition).font(.caption).foregroundStyle(.secondary)
                        ScrollView { Text(lyrics.lines.map(\.text).joined(separator: "\n")) }
                    }
                } else {
                    empty(text.noLyrics)
                }
            } else if let snapshot = service.snapshot, snapshot.playlist.songs.isEmpty {
                empty(common.queueEmpty)
            } else if let snapshot = service.snapshot {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(snapshot.playlist.songs) { song in
                                HStack(spacing: 10) {
                                    if song.id == snapshot.currentSong?.id {
                                        Image(systemName: playback.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                            .frame(width: 24).foregroundStyle(.tint)
                                    } else {
                                        Text("\(song.index + 1)").monospacedDigit()
                                            .frame(width: 24).foregroundStyle(.secondary)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(song.title).font(.callout.weight(.medium)).lineLimit(1)
                                        Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Text(song.duration > 0 ? String(format: "%d:%02d", Int(song.duration) / 60, Int(song.duration) % 60) : "—")
                                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                .id(song.id)
                            }
                        }
                    }
                    .notchScrollEdgeFade()
                    .onChange(of: snapshot.currentSong?.id, initial: true) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: Request(identity: NotchMusicIdentity(playback), lyrics: showsLyrics, accessRevision: access.revision)) {
            guard !preview else { return }
            await service.follow(NotchMusicIdentity(playback), includeLyrics: showsLyrics, folder: access.folder())
        }
    }

    private func empty(_ message: String) -> some View {
        NotchEmptyView(symbol: showsLyrics ? "quote.bubble" : "list.bullet", message: message) {
            NotchPillButton(title: common.openPlayer, prominent: true) { RadialNowPlayingApplication.open(playback.track) }
        }
    }
}
