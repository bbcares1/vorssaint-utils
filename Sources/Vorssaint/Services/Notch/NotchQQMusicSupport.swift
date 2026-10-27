// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Read-only compatibility with QQ Music for Mac 11.10.5's own saved queue and
/// lyric cache. Never decodes executable archive classes or touches account data.
enum NotchQQMusicSupport {
    static let bundleIdentifier = "com.tencent.QQMusicMac"
    static let maximumArchiveBytes = 8 * 1024 * 1024
    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac", isDirectory: true)
    }
    struct Song: Equatable, Identifiable {
        let index: Int
        let songID: Int64
        let mid: String
        let title: String
        let artist: String
        let album: String
        let duration: Double
        var primaryArtist: String = ""
        var id: String { "\(index):\(songID):\(mid)" }
    }
    struct Playlist: Equatable {
        let songs: [Song]
        let savedIndex: Int

        func currentIndex(title: String, artist: String, album: String, duration: Double) -> Int? {
            guard !title.isEmpty, !artist.isEmpty, duration.isFinite, duration > 0 else { return nil }
            func matches(_ song: Song) -> Bool {
                normalize(song.title) == normalize(title)
                    && [song.artist, song.primaryArtist].contains { normalize($0) == normalize(artist) }
                    && abs(song.duration - duration) <= 3
                    && (album.isEmpty || song.album.isEmpty || normalize(song.album) == normalize(album))
            }
            if let position = songs.firstIndex(where: { $0.index == savedIndex }), matches(songs[position]) { return position }
            let candidates = songs.indices.filter { matches(songs[$0]) }
            return candidates.count == 1 ? candidates[0] : nil
        }
    }
    struct Snapshot: Equatable {
        let playlist: Playlist
        /// Position in decoded songs, which can differ from QQ's source index
        /// if one malformed row was omitted. Nil leaves the queue visible.
        let currentIndex: Int?
        let lyric: String?
        var currentSong: Song? {
            currentIndex.flatMap { playlist.songs.indices.contains($0) ? playlist.songs[$0] : nil }
        }
    }
    enum ReadError: Error { case access, unsupported, waiting }

    /// One queue and one lyric per visible reader. Every access is protected
    /// by lock, including nested readLyric calls. Bytes are still checked for
    /// changes on each poll; decoded data alone is never evidence of freshness.
    final class Cache: @unchecked Sendable {
        fileprivate let lock = NSRecursiveLock()
        fileprivate var archiveData: Data?
        fileprivate var playlist: Playlist?
        fileprivate var lyricKey: String?
        fileprivate var lyricData: Data?
        fileprivate var lyricText: String?
    }

    static func read(folder: URL, title: String, artist: String, album: String, duration: Double,
                     includeLyrics: Bool, cache: Cache? = nil) throws -> Snapshot {
        cache?.lock.lock()
        defer { cache?.lock.unlock() }
        let path = folder.appendingPathComponent("iTemp/PlayingList.archive")
        let data: Data
        do { data = try boundedData(path, limit: maximumArchiveBytes) }
        catch let error as ReadError { throw error }
        catch { throw ReadError.access }
        let decoded = cache?.archiveData == data ? cache?.playlist : decodePlaylist(data)
        guard let playlist = decoded else { throw ReadError.unsupported }
        cache?.archiveData = data; cache?.playlist = playlist
        // The queue is QQ's own saved array and does not depend on matching
        // the current song's optional metadata. Lyrics still need a verified
        // recording before using its song ID.
        let lyricIndex = playlist.currentIndex(title: title, artist: artist, album: album, duration: duration)
        if includeLyrics && lyricIndex == nil { throw ReadError.waiting }
        let index = includeLyrics ? lyricIndex
            : playlist.currentIndex(title: title, artist: artist, album: "", duration: duration)
        let lyric = includeLyrics ? lyricIndex.flatMap {
            readLyric(folder: folder, songID: playlist.songs[$0].songID, cache: cache)
        } : nil
        // Do not combine a queue before a rewrite with lyrics from after it.
        guard try boundedData(path, limit: maximumArchiveBytes) == data else { throw ReadError.waiting }
        return Snapshot(playlist: playlist, currentIndex: index, lyric: lyric)
    }

    static func decodePlaylist(_ data: Data) -> Playlist? {
        guard let archive = Archive(data, limit: maximumArchiveBytes),
              let list = archive.dictionary(archive.top["PlayingList"]),
              let entries = archive.dictionary(list["ListData"])?["NS.objects"] as? [Any],
              entries.count <= 10_000 else { return nil }
        let savedIndex = archive.top["LastPlayingIndex"] as? Int ?? -1
        var songs: [Song] = []
        for (index, entry) in entries.enumerated() {
            guard let song = archive.dictionary(entry),
                  let title = archive.string(song["songName"]), !title.isEmpty else { continue }
            let id = max(0, archive.integer(song["songId"]) ?? 0)
            let rawDuration = archive.number(song["song_Duration"]) ?? 0
            let duration = rawDuration.isFinite && (0...604_800).contains(rawDuration) ? rawDuration : 0
            let artist = archive.dictionary(song["singerInfo"]).flatMap { archive.string($0["name"]) } ?? ""
            var artists: [String] = []
            if let singers = archive.dictionary(song["singerList"])?["NS.objects"] as? [Any], singers.count <= 64 {
                artists = singers.compactMap { archive.dictionary($0).flatMap { archive.string($0["name"]) } }
            }
            let album = archive.dictionary(song["albumInfo"]).flatMap { archive.string($0["name"]) } ?? ""
            songs.append(Song(index: index, songID: id, mid: archive.string(song["song_Mid"]) ?? "",
                              title: title, artist: artists.isEmpty ? artist : artists.joined(separator: " / "),
                              album: album, duration: duration, primaryArtist: artist))
        }
        guard entries.isEmpty || !songs.isEmpty else { return nil }
        return Playlist(songs: songs, savedIndex: savedIndex)
    }

    static func readLyric(folder: URL, songID: Int64, cache: Cache? = nil) -> String? {
        cache?.lock.lock()
        defer { cache?.lock.unlock() }
        guard songID > 0 else { return nil }
        let path = folder.appendingPathComponent("iRRCache/rrdbcache.sqlite").path
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        for suffix in [".lrc", ".qrc"] {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT data FROM Cache WHERE keyId = ? AND length(data) <= 524288 LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            let key = "\(songID)\(suffix)"
            _ = key.withCString { sqlite3_bind_text(stmt, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard sqlite3_step(stmt) == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else { continue }
            let count = Int(sqlite3_column_bytes(stmt, 0))
            guard count > 0, count <= 524288 else { continue }
            let data = Data(bytes: bytes, count: count)
            if cache?.lyricKey == key, cache?.lyricData == data { return cache?.lyricText }
            guard let archive = Archive(data, limit: 524288),
                  let source = archive.string(archive.top["root"], limit: 256 * 1024) else { continue }
            let text = suffix == ".lrc" ? source : NotchQQMusicQRC.decode(source).flatMap(qrcToLRC)
            cache?.lyricKey = key; cache?.lyricData = data; cache?.lyricText = text
            return text
        }
        return nil
    }

    /// Strip per-word markers while retaining QQ's exact line start times.
    static func qrcToLRC(_ xml: String) -> String? {
        guard xml.utf8.count <= 128 * 1024,
              !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY") else { return nil }
        let reader = LyricXML()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        let parsed = parser.parse() ? reader.content : nil
        // Real QQ caches can contain unescaped quotes and ampersands inside
        // LyricContent. Accept that bounded wrapper without executing entities.
        let content: String
        if let parsed { content = parsed }
        else if let element = xml.range(of: "<Lyric_1 "),
                let start = xml.range(of: "LyricContent=\"", range: element.upperBound..<xml.endIndex),
                let closing = xml.range(of: "</LyricInfo>", range: start.upperBound..<xml.endIndex),
                let end = xml.range(of: "\"/>", options: .backwards, range: start.upperBound..<closing.lowerBound) {
            content = decodeEntities(String(xml[start.upperBound..<end.lowerBound]))
        } else { return nil }
        let linePattern = try! NSRegularExpression(pattern: #"\[(\d+),(\d+)\]([\s\S]*?)(?=\[\d+,\d+\]|$)"#)
        let wordPattern = try! NSRegularExpression(pattern: #"\(\d+,\d+\)"#)
        var result: [String] = []
        if let offsetRange = content.range(of: #"\[offset:[+-]?\d+\]"#, options: .regularExpression) {
            result.append(String(content[offsetRange]))
        }
        let raw = content
        for match in linePattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            guard let timeRange = Range(match.range(at: 1), in: raw),
                  let wordsRange = Range(match.range(at: 3), in: raw),
                  let milliseconds = Int(raw[timeRange]), milliseconds <= 604_800_000 else { continue }
            let words = String(raw[wordsRange])
            let clean = wordPattern.stringByReplacingMatches(in: words, range: NSRange(words.startIndex..., in: words), withTemplate: "")
            result.append(String(format: "[%02d:%02d.%03d]%@", milliseconds / 60000, milliseconds / 1000 % 60, milliseconds % 1000, clean.trimmingCharacters(in: .whitespacesAndNewlines)))
            guard result.count <= 2000 else { return nil }
        }
        return result.isEmpty ? nil : result.joined(separator: "\n")
    }

    private static func decodeEntities(_ text: String) -> String {
        let pattern = try! NSRegularExpression(pattern: #"&(amp|lt|gt|quot|apos|#[0-9]+|#x[0-9a-fA-F]+);"#)
        var result = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let nameRange = Range(match.range(at: 1), in: text),
                  let replacementRange = Range(match.range, in: result) else { continue }
            let name = String(text[nameRange])
            let known = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
            let scalar = name.hasPrefix("#x") ? UInt32(name.dropFirst(2), radix: 16)
                : name.hasPrefix("#") ? UInt32(name.dropFirst()) : nil
            if let replacement = known[name] ?? scalar.flatMap(UnicodeScalar.init).map(String.init) {
                result.replaceSubrange(replacementRange, with: replacement)
            }
        }
        return result
    }

    private final class LyricXML: NSObject, XMLParserDelegate {
        var content: String?
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            if elementName == "Lyric_1" { content = attributeDict["LyricContent"] }
        }
    }

    private static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
            .replacingOccurrences(of: #"\s*[/、&]\s*"#, with: "/", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func boundedData(_ url: URL, limit: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ReadError.unsupported }
        return data
    }

    /// Convert keyed-archive UIDs to ordinary CF$UID dictionaries. This reads
    /// only property-list values, never NSKeyedUnarchiver/custom app classes.
    private struct Archive {
        let objects: [Any]
        let top: [String: Any]
        init?(_ data: Data, limit: Int) {
            guard data.count <= limit,
                  let binary = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let xml = try? PropertyListSerialization.data(fromPropertyList: binary, format: .xml, options: 0),
                  xml.count <= limit * 8,
                  let xmlText = String(data: xml, encoding: .utf8),
                  let plist = try? PropertyListSerialization.propertyList(
                    from: Data(xmlText.replacingOccurrences(of: "<key>CF$UID</key>", with: "<key>QQReference</key>").utf8),
                    options: [], format: nil) as? [String: Any],
                  plist["$archiver"] as? String == "NSKeyedArchiver",
                  let objects = plist["$objects"] as? [Any], objects.count <= 200_000,
                  let top = plist["$top"] as? [String: Any] else { return nil }
            self.objects = objects; self.top = top
        }
        func value(_ reference: Any?) -> Any? {
            guard let reference else { return nil }
            if let uid = reference as? [String: Any], let index = uid["QQReference"] as? Int {
                return index > 0 && objects.indices.contains(index) ? objects[index] : nil
            }
            return reference
        }
        func dictionary(_ reference: Any?) -> [String: Any]? { value(reference) as? [String: Any] }
        func string(_ reference: Any?, limit: Int = 4096) -> String? {
            var current = reference
            // NSString can be a scalar; NSMutableString is an NS.string
            // wrapper. Its payload may itself be a UID. Never instantiate
            // archive classes, and bound indirection in malformed archives.
            for _ in 0..<16 {
                guard let resolved = value(current) else { return nil }
                if let text = resolved as? String { return text.utf8.count <= limit ? text : nil }
                guard let wrapper = resolved as? [String: Any], let payload = wrapper["NS.string"] else { return nil }
                current = payload
            }
            return nil
        }
        func number(_ reference: Any?) -> Double? {
            if let raw = value(reference) as? NSNumber, CFGetTypeID(raw) != CFBooleanGetTypeID() {
                return raw.doubleValue
            }
            return string(reference, limit: 64).flatMap(Double.init)
        }
        func integer(_ reference: Any?) -> Int64? {
            if let raw = value(reference) as? NSNumber, CFGetTypeID(raw) != CFBooleanGetTypeID() {
                return Int64(exactly: raw.doubleValue)
            }
            return string(reference, limit: 32).flatMap(Int64.init)
        }
    }
}
