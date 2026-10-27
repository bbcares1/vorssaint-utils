// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// QRC format compatibility adapted from apoint123/qrc-decoder (MIT).
// See Resources/QQMusicDecoder-LICENSE.txt for the original copyright and license.

import Foundation
import zlib

/// QQ Music's lyric codec, not a general-purpose encryption implementation.
/// Input and inflated output are bounded before parsing any lyric content.
enum NotchQQMusicQRC {
    static func decode(_ hex: String) -> String? {
        guard !hex.isEmpty, hex.utf8.count <= 256 * 1024, hex.utf8.count % 16 == 0 else { return nil }
        let chars = Array(hex.utf8)
        func nibble(_ c: UInt8) -> UInt8? {
            switch c { case 48...57: return c - 48; case 65...70: return c - 55; case 97...102: return c - 87; default: return nil }
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let high = nibble(chars[i]), let low = nibble(chars[i + 1]) else { return nil }
            bytes.append(high << 4 | low)
        }
        for start in stride(from: 0, to: bytes.count, by: 8) {
            var block = bytes[start..<(start + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            for schedule in schedules { block = crypt(block, schedule: schedule) }
            for i in 0..<8 { bytes[start + i] = UInt8(truncatingIfNeeded: block >> (56 - i * 8)) }
        }
        var output = [UInt8](repeating: 0, count: 128 * 1024)
        var count = uLongf(output.count)
        guard uncompress(&output, &count, bytes, uLong(bytes.count)) == Z_OK else { return nil }
        return String(bytes: output.prefix(Int(count)), encoding: .utf8)
    }

    private static let schedules = [schedule("!@#)(NHL", reverse: true),
                                    schedule("123ZXC!@", reverse: false),
                                    schedule("!@#)(*$%", reverse: true)]

    private static func permute(_ value: UInt64, bits: Int, table: [Int]) -> UInt64 {
        table.reduce(UInt64(0)) { ($0 << 1) | ((value >> (bits - $1)) & 1) }
    }

    private static func schedule(_ key: String, reverse: Bool) -> [UInt64] {
        let bytes = Array(key.utf8)
        func part(_ table: [Int]) -> UInt64 {
            table.reduce(UInt64(0)) { result, pos in
                let index = (pos >> 5) * 4 + 3 - ((pos & 31) >> 3)
                return (result << 1) | UInt64((bytes[index] >> (7 - (pos & 7))) & 1)
            } << 4
        }
        var c = part(KEY_PERM_C), d = part(KEY_PERM_D)
        var result: [UInt64] = []
        for shift in KEY_RND_SHIFT {
            c = ((c << shift) | (c >> (28 - shift))) & 0xfffffff0
            d = ((d << shift) | (d >> (28 - shift))) & 0xfffffff0
            // The second half deliberately uses pos - 27, as in QQ's format.
            let key = KEY_COMPRESSION.reduce(UInt64(0)) { value, pos in
                (value << 1) | (pos < 28 ? ((c >> (31 - pos)) & 1) : ((d >> (31 - (pos - 27))) & 1))
            }
            result.append(key)
        }
        return reverse ? result.reversed() : result
    }

    private static func crypt(_ block: UInt64, schedule: [UInt64]) -> UInt64 {
        let initial = permute(block, bits: 64, table: IP_RULE)
        var left = initial >> 32, right = initial & 0xffffffff
        for key in schedule {
            let expanded = permute(right, bits: 32, table: E_BOX_TABLE) ^ key
            var substituted: UInt64 = 0
            for i in 0..<8 {
                let value = Int((expanded >> (42 - i * 6)) & 63)
                let index = (value & 32) | ((value & 31) >> 1) | ((value & 1) << 4)
                substituted = (substituted << 4) | UInt64(sBoxes[i][index])
            }
            let next = left ^ permute(substituted, bits: 32, table: P_BOX)
            left = right; right = next
        }
        return permute((right << 32) | left, bits: 64, table: INV_IP_RULE)
    }
    private static let KEY_PERM_C: [Int] = [
        56, 48, 40, 32, 24, 16, 8, 0, 57, 49, 41, 33, 25, 17, 9, 1,
        58, 50, 42, 34, 26, 18, 10, 2, 59, 51, 43, 35,
    ]
    private static let KEY_PERM_D: [Int] = [
        62, 54, 46, 38, 30, 22, 14, 6, 61, 53, 45, 37, 29, 21, 13, 5,
        60, 52, 44, 36, 28, 20, 12, 4, 27, 19, 11, 3,
    ]
    private static let KEY_COMPRESSION: [Int] = [
        13, 16, 10, 23, 0, 4, 2, 27, 14, 5, 20, 9, 22, 18, 11, 3,
        25, 7, 15, 6, 26, 19, 12, 1, 40, 51, 30, 36, 46, 54, 29, 39,
        50, 44, 32, 47, 43, 48, 38, 55, 33, 52, 45, 41, 49, 35, 28, 31,
    ]
    private static let KEY_RND_SHIFT: [Int] = [
        1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1,
    ]
    private static let P_BOX: [Int] = [
        16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10,
        2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25,
    ]
    private static let E_BOX_TABLE: [Int] = [
        32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9, 8, 9, 10, 11,
        12, 13, 12, 13, 14, 15, 16, 17, 16, 17, 18, 19, 20, 21, 20, 21,
        22, 23, 24, 25, 24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1,
    ]
    private static let IP_RULE: [Int] = [
        34, 42, 50, 58, 2, 10, 18, 26, 36, 44, 52, 60, 4, 12, 20, 28,
        38, 46, 54, 62, 6, 14, 22, 30, 40, 48, 56, 64, 8, 16, 24, 32,
        33, 41, 49, 57, 1, 9, 17, 25, 35, 43, 51, 59, 3, 11, 19, 27,
        37, 45, 53, 61, 5, 13, 21, 29, 39, 47, 55, 63, 7, 15, 23, 31,
    ]
    private static let INV_IP_RULE: [Int] = [
        37, 5, 45, 13, 53, 21, 61, 29, 38, 6, 46, 14, 54, 22, 62, 30,
        39, 7, 47, 15, 55, 23, 63, 31, 40, 8, 48, 16, 56, 24, 64, 32,
        33, 1, 41, 9, 49, 17, 57, 25, 34, 2, 42, 10, 50, 18, 58, 26,
        35, 3, 43, 11, 51, 19, 59, 27, 36, 4, 44, 12, 52, 20, 60, 28,
    ]
    private static let SBOX1: [Int] = [
        14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7,
        0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8,
        4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0,
        15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13,
    ]
    private static let SBOX2: [Int] = [
        15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10,
        3, 13, 4, 7, 15, 2, 8, 15, 12, 0, 1, 10, 6, 9, 11, 5,
        0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15,
        13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9,
    ]
    private static let SBOX3: [Int] = [
        10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8,
        13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1,
        13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7,
        1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12,
    ]
    private static let SBOX4: [Int] = [
        7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15,
        13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9,
        10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4,
        3, 15, 0, 6, 10, 10, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14,
    ]
    private static let SBOX5: [Int] = [
        2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9,
        14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6,
        4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14,
        11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3,
    ]
    private static let SBOX6: [Int] = [
        12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11,
        10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8,
        9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6,
        4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13,
    ]
    private static let SBOX7: [Int] = [
        4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1,
        13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6,
        1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2,
        6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12,
    ]
    private static let SBOX8: [Int] = [
        13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7,
        1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2,
        7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8,
        2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11,
    ]
    private static let sBoxes = [SBOX1,SBOX2,SBOX3,SBOX4,SBOX5,SBOX6,SBOX7,SBOX8]
}
