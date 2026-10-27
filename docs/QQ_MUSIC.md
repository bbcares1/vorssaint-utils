# QQ Music in Dynamic Island

When QQ Music is the active player, the existing lyrics and playlist buttons
read QQ Music's own local data. Other players keep their existing integration.

Open either page and use **Connect QQ Music** if access is requested. Select:

```
~/Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac
```

The folder chooser opens at that location. Select the `QQMusicMac` folder,
not the app in Applications. The app saves a read-only folder bookmark; this
machine-specific permission is excluded from settings backups. Giving Codex
permission during development does not grant the installed Vorssaint app access.

The playlist shows the complete saved queue in QQ Music's order, marks the
current song when its identity can be matched and initially scrolls to it. This integration displays the queue;
selecting a different song remains in QQ Music. Lyrics use QQ's cached LRC or
QRC data, keyed by its numeric song ID, and follow the player's shared position,
including pause and seek. Instrumental recordings display the instrumental state.
No title search, account credentials or external lyric service is used for QQ.

Both pages check for local updates once per second while visible. QQ Music must
first write the queue or cache the lyrics. If lyrics are missing, open them in
QQ Music; the island will pick them up when they appear. A mismatched title,
artist, album or duration produces a waiting state for lyrics instead of displaying the
previous recording's lyrics. Queue display is independent of that strict lyric
match: the saved queue remains visible even when the player has not provided
complete metadata. Missing optional song IDs, singers or durations do not reject
a queue, and a malformed row does not hide its other songs. Collaborations match
both QQ's primary-artist playback metadata and its complete queue credits. Plain and wrapped
NSString/NSMutableString archive representations are both supported. The page stops polling when hidden, and cancelled
reads cannot update a different song. Previously decoded, unchanged data is
reused to avoid decoding QRC every second.

## Compatibility and validation

The reader was checked against QQ Music for Mac **11.10.5**. Its archive/cache
formats are private and may change with a QQ Music update. Unsupported formats
show an unavailable message. The files are opened read-only:

- `iTemp/PlayingList.archive`: keyed-archive property-list values, without
  instantiating QQ Music classes. Song IDs, metadata and array order are retained.
- `iRRCache/rrdbcache.sqlite`: bounded `.lrc` / `.qrc` records from `Cache`.
- QRC uses a bounded native Swift port of the MIT-licensed
  [apoint123/qrc-decoder](https://github.com/apoint123/qrc-decoder).
  Attribution and license are bundled in `QQMusicDecoder-LICENSE.txt`.

`Tests/NotchQQMusicTests.swift` uses synthetic archives, a disposable SQLite
cache, and an independently encoded synthetic QRC vector. It covers identity
mismatches, stale indexes, duplicate songs, corruption, input limits, punctuation
in QQ's nonstandard XML, timestamps and read-only access. Run:

```sh
./build.sh --test-suite=notch
./build.sh --dev
./build/VorssaintDeveloper --selftest
```

Development also checked actual current-player metadata against a live 60-song
queue and decoded 117 available lyric cache records (85 LRC, 32 QRC). No private
queue, account data or real lyric cache is included in the repository. This
checks data compatibility; visual scrolling and the installed app's first-use
folder permission still need an interactive check on the user's desktop.

The queue regression was reproduced with an actual 26-song QQ playlist that
contained a wrapped NSMutableString title. The old reader rejected the whole
array. A regression fixture with the same string representation now passes,
and a subsequent live four-song queue is readable. A collaboration in that queue
also reproduced QQ reporting only the primary artist; the updated match keeps
all credits displayed while identifying the playing song correctly. Tests also cover singleton queues, absent current metadata,
missing optional fields, malformed rows and bounded cyclic string wrappers.
