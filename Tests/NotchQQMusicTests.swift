// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

enum NotchQQMusicTests {
    static func run(_ suite: TestSuite) {
        typealias Support = NotchQQMusicSupport
        func reference(_ index: Int) -> [String: Int] { ["CF$UID": index] }
        func archive(_ objects: [Any], top: [String: Any]) -> Data {
            try! PropertyListSerialization.data(fromPropertyList: ["$archiver": "NSKeyedArchiver", "$version": 100000,
                                                                   "$objects": objects, "$top": top], format: .binary, options: 0)
        }
        let objects: [Any] = ["$null", ["ListData": reference(2)], ["NS.objects": [reference(3), reference(9)]],
            ["songId": 123, "songName": reference(4), "song_Duration": reference(5), "singerInfo": reference(6),
             "song_Mid": reference(8), "albumInfo": reference(10)],
            "A Song", 180.0, ["name": reference(7)], "An Artist", "mid123",
            ["songId": 456, "songName": reference(11), "song_Duration": reference(5), "singerInfo": reference(6)],
            ["name": reference(12)], "Another Song", "An Album"]
        let data = archive(objects, top: ["PlayingList": reference(1), "LastPlayingIndex": 0])
        let list = Support.decodePlaylist(data)
        suite.expect(list?.songs.map(\.songID) == [123, 456], "QQ queue preserves every song and its real order")
        suite.expect(list?.songs.first?.album == "An Album", "QQ queue resolves archive references without constructing classes")
        suite.expect(list?.currentIndex(title: "A Song", artist: "An Artist", album: "An Album", duration: 180) == 0,
                     "QQ saved current index must match the actual player")
        suite.expect(list?.currentIndex(title: "Another Song", artist: "An Artist", album: "", duration: 180) == 1,
                     "QQ playback moving ahead of the saved index still identifies a unique recording")
        suite.expect(list?.currentIndex(title: "A Song", artist: "Someone Else", album: "", duration: 180) == nil,
                     "QQ same title by another artist never shows stale lyrics")
        suite.expect(list?.currentIndex(title: "A Song", artist: "An Artist", album: "Live", duration: 180) == nil,
                     "QQ a different album is not silently treated as the same recording")
        suite.expect(list?.currentIndex(title: "A Song", artist: "An Artist", album: "", duration: 200) == nil,
                     "QQ different recording length rejects the saved queue")
        suite.expect(list?.currentIndex(title: "A Song", artist: "", album: "", duration: 180) == nil,
                     "QQ missing identity does not guess a matching lyric")
        if let song = list?.songs.first {
            let ambiguous = Support.Playlist(songs: [song, song], savedIndex: -1)
            suite.expect(ambiguous.currentIndex(title: song.title, artist: song.artist, album: song.album, duration: song.duration) == nil,
                         "QQ duplicate recordings require an actual current index")
        }
        var wrappedObjects = objects
        wrappedObjects[4] = ["NS.string": "A Song & More"]
        wrappedObjects[7] = ["NS.string": reference(13)]
        wrappedObjects[12] = ["NS.string": "An Album"]
        wrappedObjects.append("An Artist")
        let wrapped = Support.decodePlaylist(archive(wrappedObjects, top: ["PlayingList": reference(1), "LastPlayingIndex": 0]))
        suite.expect(wrapped?.songs.count == 2 && wrapped?.songs.first?.title == "A Song & More"
                     && wrapped?.songs.first?.artist == "An Artist" && wrapped?.songs.first?.album == "An Album",
                     "QQ mutable string titles and referenced artist strings do not reject an entire playlist")
        var collaborationObjects = objects
        var collaborationSong = collaborationObjects[3] as! [String: Any]
        collaborationSong["singerList"] = reference(13)
        collaborationObjects[3] = collaborationSong
        collaborationObjects.append(["NS.objects": [reference(6), reference(14)]])
        collaborationObjects.append(["name": "Guest Artist"])
        let collaboration = Support.decodePlaylist(archive(collaborationObjects, top: ["PlayingList": reference(1), "LastPlayingIndex": 0]))
        suite.expect(collaboration?.songs.first?.artist == "An Artist / Guest Artist"
                     && collaboration?.currentIndex(title: "A Song", artist: "An Artist", album: "An Album", duration: 180) == 0
                     && collaboration?.currentIndex(title: "A Song", artist: "An Artist / Guest Artist", album: "An Album", duration: 180) == 0,
                     "QQ collaborations match either the reported primary artist or complete credits without dropping displayed credits")
        var partialObjects = objects
        var partialSong = partialObjects[3] as! [String: Any]
        partialSong.removeValue(forKey: "singerInfo")
        partialSong.removeValue(forKey: "songId")
        partialSong["song_Duration"] = "unknown"
        partialObjects[3] = partialSong
        let partial = Support.decodePlaylist(archive(partialObjects, top: ["PlayingList": reference(1)]))
        suite.expect(partial?.songs.count == 2 && partial?.songs.first?.title == "A Song"
                     && partial?.songs.first?.duration == 0 && partial?.songs.first?.songID == 0,
                     "QQ optional metadata and an absent saved index never hide an otherwise readable queue")
        var malformedObjects = objects
        malformedObjects[3] = "unreadable row"
        let remaining = Support.decodePlaylist(archive(malformedObjects, top: ["PlayingList": reference(1), "LastPlayingIndex": 1]))
        suite.expect(remaining?.songs.count == 1 && remaining?.songs.first?.index == 1
                     && remaining?.currentIndex(title: "Another Song", artist: "An Artist", album: "", duration: 180) == 0,
                     "QQ skips an unreadable row without renumbering the remaining source entries or losing the current song")
        var cyclicObjects = objects
        cyclicObjects[4] = ["NS.string": reference(4)]
        let cyclic = Support.decodePlaylist(archive(cyclicObjects, top: ["PlayingList": reference(1), "LastPlayingIndex": 1]))
        suite.expect(cyclic?.songs.count == 1, "QQ cyclic string wrappers are bounded and do not hide valid rows")
        suite.expect(Support.decodePlaylist(Data("invalid".utf8)) == nil, "QQ truncated archives fail closed")
        let broken = archive(objects, top: ["PlayingList": reference(9999), "LastPlayingIndex": 0])
        suite.expect(Support.decodePlaylist(broken) == nil, "QQ invalid references cannot index outside the object table")
        suite.expect(Support.decodePlaylist(Data(repeating: 0, count: Support.maximumArchiveBytes + 1)) == nil,
                     "QQ oversized archives are rejected")

        // Independent vector generated by apoint123/qrc-decoder (MIT), with
        // synthetic text, not a recording's copyrighted lyric cache.
        let encrypted = "ee7befb746f93831d42dcdf2e21f0d5d977de00c85449a7c535da3bcf1beb3ca54d5d801d40005b7560ae828d0fe17076d86a0014d310e7ac713c4603ba258e2410192eafed8963d0c52720243caacc7df2b81dd056dea7e"
        let xml = NotchQQMusicQRC.decode(encrypted)
        suite.expect(xml?.contains("LyricContent") == true, "QQ nonstandard QRC codec matches an independent encoder")
        let lrc = xml.flatMap(Support.qrcToLRC)
        suite.expect(lrc == "[00:01.000]Hello\n[00:02.500]世界", "QQ QRC preserves exact line timing and Unicode, strips only word markers")
        if let lrc {
            let lines = NotchLyricsSupport.parse(lrc, duration: 10)
            let lyrics = NotchLyrics(lines: lines, plain: "", instrumental: false)
            suite.expect(lyrics.activeIndex(at: 0.99) == nil && lyrics.activeIndex(at: 1) == 0
                         && lyrics.activeIndex(at: 2.5) == 1 && lyrics.activeIndex(at: 1.5) == 0,
                         "QQ lyrics follow playback boundaries and a seek backwards")
        }
        let unescaped = #"<QrcInfos><LyricInfo><Lyric_1 LyricContent="[0,1000]A(0,100) & B(100,100) "C"(200,100)&#10;[1000,1000]D(1000,1000)"/></LyricInfo></QrcInfos>"#
        suite.expect(Support.qrcToLRC(unescaped) == "[00:00.000]A & B \"C\"\n[00:01.000]D",
                     "QQ's observed unescaped XML attributes retain punctuation and timing")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchQQMusicFolderBookmark),
                     "QQ local folder grants never travel in settings backups")
        for malformed in ["", "0", "zzzzzzzzzzzzzzzz", String(repeating: "0", count: 16), String(repeating: "0", count: 256 * 1024 + 16)] {
            suite.expect(NotchQQMusicQRC.decode(malformed) == nil, "QQ malformed or oversized QRC never produces lyrics")
        }
        suite.expect(Support.qrcToLRC("<!DOCTYPE x [<!ENTITY e 'a'>]><QrcInfos/>") == nil, "QQ lyrics do not expand XML entities")
        suite.expect(Support.qrcToLRC("<broken>") == nil, "QQ malformed lyric XML fails closed")
        let offsetXML = #"<Lyric_1 LyricContent="[offset:500]&#10;[1000,1000]Offset(1000,1000)"/>"#
        let offsetLines = Support.qrcToLRC(offsetXML).map { NotchLyricsSupport.parse($0, duration: 10) }
        suite.expect(offsetLines?.first?.time == 0.5, "QQ encoded lyric offsets survive conversion")
        for language in AppLanguage.allCases {
            let text = NotchQQMusicStrings(language)
            suite.expect([text.playlist, text.connect, text.accessHint, text.waiting, text.noLyrics, text.unsupported].allSatisfy { !$0.isEmpty },
                         "QQ integration has messages for \(language.rawValue)")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-qqmusic-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("iTemp"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("iRRCache"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try data.write(to: root.appendingPathComponent("iTemp/PlayingList.archive"))
            let dbPath = root.appendingPathComponent("iRRCache/rrdbcache.sqlite").path
            var db: OpaquePointer?
            guard sqlite3_open(dbPath, &db) == SQLITE_OK else { suite.expect(false, "QQ fixture database opens"); return }
            sqlite3_exec(db, "CREATE TABLE Cache(keyId TEXT PRIMARY KEY, data BLOB)", nil, nil, nil)
            let lyricData = archive(["$null", "[00:01.00]Fixture"], top: ["root": reference(1)])
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO Cache VALUES ('123.lrc', ?)", -1, &stmt, nil)
            _ = lyricData.withUnsafeBytes { sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            suite.expect(sqlite3_step(stmt) == SQLITE_DONE, "QQ fixture lyric is saved")
            sqlite3_finalize(stmt); sqlite3_close(db)
            let before = try Data(contentsOf: URL(fileURLWithPath: dbPath))
            let result = try Support.read(folder: root, title: "A Song", artist: "An Artist", album: "An Album", duration: 180, includeLyrics: true)
            suite.expect(result.lyric == "[00:01.00]Fixture" && result.playlist.songs.count == 2, "QQ reads actual saved lyrics by song ID")
            let after = try Data(contentsOf: URL(fileURLWithPath: dbPath))
            suite.expect(after == before, "QQ integration never changes the player's database")
            suite.expect(Support.readLyric(folder: root, songID: 999) == nil, "QQ missing lyric does not reuse a different song")
            let queueOnly = try Support.read(folder: root, title: "A Song", artist: "An Artist", album: "", duration: 180, includeLyrics: false)
            suite.expect(queueOnly.lyric == nil, "QQ queue view does not read lyric data")
            let withoutMetadata = try Support.read(folder: root, title: "", artist: "", album: "", duration: 0, includeLyrics: false)
            suite.expect(withoutMetadata.playlist.songs.count == 2 && withoutMetadata.currentSong == nil,
                         "QQ queue is visible while current-player metadata is missing, without guessing a highlighted song")
            let albumMismatch = try Support.read(folder: root, title: "A Song", artist: "An Artist", album: "Different release", duration: 180, includeLyrics: false)
            suite.expect(albumMismatch.playlist.songs.count == 2 && albumMismatch.currentSong?.songID == 123,
                         "QQ optional album differences never suppress the real queue or its playing marker")
            do {
                _ = try Support.read(folder: root, title: "A Song", artist: "An Artist", album: "Different release", duration: 180, includeLyrics: true)
                suite.expect(false, "QQ mismatched recordings must not supply lyrics")
            } catch Support.ReadError.waiting {
                suite.expect(true, "QQ lyric identity checks remain strict even when queue display is independent")
            }
            let singleObjects: [Any] = ["$null", ["ListData": reference(2)], ["NS.objects": [reference(3)]],
                ["songName": "Single selection", "songId": 789, "song_Duration": "120.5"]]
            try archive(singleObjects, top: ["PlayingList": reference(1), "LastPlayingIndex": 0])
                .write(to: root.appendingPathComponent("iTemp/PlayingList.archive"))
            let single = try Support.read(folder: root, title: "Single selection", artist: "", album: "", duration: 120.5, includeLyrics: false)
            suite.expect(single.playlist.songs.count == 1 && single.playlist.songs[0].duration == 120.5,
                         "QQ one-off song selection and numeric string durations form a readable queue")
            try data.write(to: root.appendingPathComponent("iTemp/PlayingList.archive"))
            let cache = Support.Cache()
            _ = try Support.read(folder: root, title: "A Song", artist: "An Artist", album: "", duration: 180, includeLyrics: true, cache: cache)
            let replacement = archive(["$null", "[00:02.00]Updated"], top: ["root": reference(1)])
            let hex = replacement.map { String(format: "%02x", $0) }.joined()
            sqlite3_open(dbPath, &db)
            sqlite3_exec(db, "UPDATE Cache SET data = X'\(hex)' WHERE keyId = '123.lrc'", nil, nil, nil)
            sqlite3_close(db)
            let updated = try Support.read(folder: root, title: "A Song", artist: "An Artist", album: "", duration: 180, includeLyrics: true, cache: cache)
            suite.expect(updated.lyric == "[00:02.00]Updated", "QQ live cache rewrites replace already decoded lyrics")
            try archive(objects, top: ["PlayingList": reference(1), "LastPlayingIndex": 1])
                .write(to: root.appendingPathComponent("iTemp/PlayingList.archive"))
            let moved = try Support.read(folder: root, title: "Another Song", artist: "An Artist", album: "", duration: 180, includeLyrics: false, cache: cache)
            suite.expect(moved.playlist.savedIndex == 1 && moved.currentIndex == 1,
                         "QQ live queue rewrites invalidate the decoded archive cache")
        } catch { suite.expect(false, "QQ isolated file integration: \(error)") }
    }
}
