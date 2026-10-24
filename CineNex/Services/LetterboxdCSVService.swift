import Combine
import Foundation

enum LetterboxdRecordKind: String, Codable {
    case diary
    case watched
    case ratings
    case watchlist
    case other
}

struct LetterboxdRecord: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let year: Int?
    let letterboxdURI: String?
    let dateAdded: String?
    let watchedDate: String?
    let rating: Double?
    let rewatch: Bool?
    let tags: String?
    let review: String?
    let kind: LetterboxdRecordKind
}

enum LetterboxdCSVError: LocalizedError {
    case missingHeader
    case missingTitleColumn
    case unreadableText
    case malformedCSV

    var errorDescription: String? {
        switch self {
        case .missingHeader:
            return "The selected file does not contain a CSV header row."
        case .missingTitleColumn:
            return "This CSV does not have a Name or Title column, so CineNex cannot identify films."
        case .unreadableText:
            return "CineNex could not decode this file as UTF-8 text."
        case .malformedCSV:
            return "This CSV contains invalid quotation marks or an unfinished quoted field. Export the file again from Letterboxd and retry."
        }
    }
}

enum LetterboxdCSVService {
    static func parse(_ text: String, filename: String) throws -> [LetterboxdRecord] {
        let cleanedText = text.replacingOccurrences(of: "\u{feff}", with: "")
        let rows = try parseRows(cleanedText)
        guard let rawHeaders = rows.first, !rawHeaders.isEmpty else {
            throw LetterboxdCSVError.missingHeader
        }

        let headers = rawHeaders.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func column(_ names: [String]) -> Int? {
            headers.firstIndex { names.contains($0) }
        }

        guard let titleColumn = column(["name", "title", "film", "movie"]) else {
            throw LetterboxdCSVError.missingTitleColumn
        }

        let yearColumn = column(["year", "release year"])
        let uriColumn = column(["letterboxd uri", "uri", "url", "link"])
        let dateColumn = column(["date", "date added"])
        let watchedDateColumn = column(["watched date"])
        let ratingColumn = column(["rating", "stars", "score"])
        let rewatchColumn = column(["rewatch", "re-watched", "rewatched"])
        let tagsColumn = column(["tags"])
        let reviewColumn = column(["review"])

        let name = filename.lowercased()
        let kind: LetterboxdRecordKind
        if name.contains("diary") {
            kind = .diary
        } else if name.contains("watchlist") {
            kind = .watchlist
        } else if name.contains("ratings") || ratingColumn != nil && watchedDateColumn == nil {
            kind = .ratings
        } else if name.contains("watched") {
            kind = .watched
        } else if watchedDateColumn != nil {
            kind = .diary
        } else {
            kind = .other
        }

        return rows.dropFirst().compactMap { row in
            func value(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let result = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return result.isEmpty ? nil : result
            }

            guard let title = value(titleColumn) else { return nil }
            let year = value(yearColumn).flatMap(Int.init)
            let uri = value(uriColumn)
            let watchedDate = value(watchedDateColumn)
            let dateAdded = value(dateColumn)
            let stableFilmID = uri ?? "\(title.lowercased())|\(year.map(String.init) ?? "")"
            let uniqueSuffix = kind == .diary ? (watchedDate ?? dateAdded ?? "") : ""
            let id = "\(kind.rawValue)|\(stableFilmID)|\(uniqueSuffix)"
            let rating = value(ratingColumn).flatMap { rawValue -> Double? in
                guard let parsed = Double(rawValue), parsed.isFinite, (0...5).contains(parsed) else {
                    return nil
                }
                return parsed
            }
            let rewatchValue = value(rewatchColumn)?.lowercased()
            let rewatch = rewatchValue.map { ["yes", "true", "1", "y"].contains($0) }

            return LetterboxdRecord(
                id: id,
                title: title,
                year: year,
                letterboxdURI: uri,
                dateAdded: dateAdded,
                watchedDate: watchedDate,
                rating: rating,
                rewatch: rewatch,
                tags: value(tagsColumn),
                review: value(reviewColumn),
                kind: kind
            )
        }
    }

    static func exportFilename(for kind: LetterboxdRecordKind) -> String {
        switch kind {
        case .diary: return "diary.csv"
        case .watched: return "watched.csv"
        case .ratings: return "ratings.csv"
        case .watchlist: return "watchlist.csv"
        case .other: return "cinenex-export.csv"
        }
    }

    static func makeDiaryCSV(from records: [LetterboxdRecord]) -> String {
        makeCSV(from: records, kind: .diary)
    }

    static func makeCSV(from records: [LetterboxdRecord], kind: LetterboxdRecordKind) -> String {
        let headers: [String]
        switch kind {
        case .diary:
            headers = ["Date", "Name", "Year", "Letterboxd URI", "Rating", "Rewatch", "Tags", "Watched Date"]
        case .watched:
            headers = ["Date", "Name", "Year", "Letterboxd URI"]
        case .ratings:
            headers = ["Date", "Name", "Year", "Letterboxd URI", "Rating"]
        case .watchlist:
            headers = ["Date", "Name", "Year", "Letterboxd URI"]
        case .other:
            headers = ["Date", "Name", "Year", "Letterboxd URI", "Rating", "Rewatch", "Tags", "Watched Date", "Review"]
        }

        let matchingRecords = records
            .filter { $0.kind == kind && (kind != .diary || $0.watchedDate != nil) }
            .sorted {
                if kind == .diary {
                    return ($0.watchedDate ?? "") < ($1.watchedDate ?? "")
                }
                if ($0.dateAdded ?? "") != ($1.dateAdded ?? "") {
                    return ($0.dateAdded ?? "") < ($1.dateAdded ?? "")
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }

        var lines = [headers.joined(separator: ",")]
        for record in matchingRecords {
            let date = kind == .watched ? (record.watchedDate ?? record.dateAdded ?? "") : (record.dateAdded ?? "")
            let fields: [String]
            switch kind {
            case .diary:
                fields = [
                    record.dateAdded ?? "",
                    record.title,
                    record.year.map(String.init) ?? "",
                    record.letterboxdURI ?? "",
                    record.rating.map { String(format: "%g", $0) } ?? "",
                    record.rewatch.map { $0 ? "Yes" : "No" } ?? "",
                    record.tags ?? "",
                    record.watchedDate ?? ""
                ]
            case .watched:
                fields = [date, record.title, record.year.map(String.init) ?? "", record.letterboxdURI ?? ""]
            case .ratings:
                fields = [date, record.title, record.year.map(String.init) ?? "", record.letterboxdURI ?? "", record.rating.map { String(format: "%g", $0) } ?? ""]
            case .watchlist:
                fields = [date, record.title, record.year.map(String.init) ?? "", record.letterboxdURI ?? ""]
            case .other:
                fields = [
                    record.dateAdded ?? "",
                    record.title,
                    record.year.map(String.init) ?? "",
                    record.letterboxdURI ?? "",
                    record.rating.map { String(format: "%g", $0) } ?? "",
                    record.rewatch.map { $0 ? "Yes" : "No" } ?? "",
                    record.tags ?? "",
                    record.watchedDate ?? "",
                    record.review ?? ""
                ]
            }
            lines.append(fields.map(escapeCSV).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\r") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func parseRows(_ text: String) throws -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        var closedQuotedField = false
        var index = 0

        func finishField() {
            row.append(field)
            field = ""
            closedQuotedField = false
        }

        func finishRow() {
            finishField()
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(row)
            }
            row = []
        }

        while index < characters.count {
            let character = characters[index]

            if insideQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    insideQuotes = false
                    closedQuotedField = true
                } else {
                    field.append(character)
                }
                index += 1
                continue
            }

            if closedQuotedField {
                if character == "," {
                    finishField()
                } else if character == "\n" || character == "\r" {
                    if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                        index += 1
                    }
                    finishRow()
                } else if character == " " || character == "\t" {
                } else {
                    throw LetterboxdCSVError.malformedCSV
                }
                index += 1
                continue
            }

            if character == "\"" {
                guard field.isEmpty else {
                    throw LetterboxdCSVError.malformedCSV
                }
                insideQuotes = true
            } else if character == "," {
                finishField()
            } else if character == "\n" || character == "\r" {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                finishRow()
            } else {
                field.append(character)
            }
            index += 1
        }

        guard !insideQuotes else {
            throw LetterboxdCSVError.malformedCSV
        }
        finishField()
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.append(row)
        }
        return rows
    }
}

@MainActor
final class LetterboxdLibraryStore: ObservableObject {
    static let shared = LetterboxdLibraryStore()

    @Published private(set) var records: [LetterboxdRecord] = []

    private let defaults: UserDefaults
    private let storageKey: String

    var diaryRecords: [LetterboxdRecord] {
        records.filter { $0.kind == .diary }.sorted { ($0.watchedDate ?? "") > ($1.watchedDate ?? "") }
    }

    init(defaults: UserDefaults = .standard, storageKey: String = "cinenex.letterboxd.records") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([LetterboxdRecord].self, from: data) {
            records = saved
        }
    }

    @discardableResult
    func importCSV(_ text: String, filename: String) throws -> Int {
        let imported = try LetterboxdCSVService.parse(text, filename: filename)
        var merged = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let previousCount = merged.count
        for record in imported {
            merged[record.id] = record
        }
        records = merged.values.sorted {
            if $0.title.localizedStandardCompare($1.title) == .orderedSame {
                return ($0.year ?? 0) < ($1.year ?? 0)
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        persist()
        return max(0, merged.count - previousCount)
    }

    func makeDiaryExport() -> Data {
        makeCSVExport(for: .diary)
    }

    func makeCSVExport(for kind: LetterboxdRecordKind) -> Data {
        Data(LetterboxdCSVService.makeCSV(from: records, kind: kind).utf8)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
