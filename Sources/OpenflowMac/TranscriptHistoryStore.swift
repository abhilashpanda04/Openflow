import Foundation

// MARK: - Transcript Record Model

public struct TranscriptRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let text: String
    public let language: String?
    public let engine: String
    public let timestamp: Date
    public let durationSeconds: Double?
    public let appName: String?

    public init(
        id: UUID = UUID(),
        text: String,
        language: String? = nil,
        engine: String,
        timestamp: Date = Date(),
        durationSeconds: Double? = nil,
        appName: String? = nil
    ) {
        self.id = id
        self.text = text
        self.language = language
        self.engine = engine
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.appName = appName
    }

    public var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    enum CodingKeys: String, CodingKey {
        case id, text, language, engine, timestamp, durationSeconds, appName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        engine = try container.decode(String.self, forKey: .engine)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
    }
}

// MARK: - Cumulative Speech Statistics Model

public struct CumulativeSpeechStats: Codable, Equatable {
    public var totalWords: Int
    public var totalSessions: Int
    public var totalSecondsSpoken: Double
    public var totalCommands: Int
    public var engineCounts: [String: Int]
    public var appCounts: [String: Int]
    public var dailyWords: [String: Int] // "yyyy-MM-dd" : count
    public var dailySessions: [String: Int] // "yyyy-MM-dd" : count

    public init(
        totalWords: Int = 0,
        totalSessions: Int = 0,
        totalSecondsSpoken: Double = 0,
        totalCommands: Int = 0,
        engineCounts: [String: Int] = [:],
        appCounts: [String: Int] = [:],
        dailyWords: [String: Int] = [:],
        dailySessions: [String: Int] = [:]
    ) {
        self.totalWords = totalWords
        self.totalSessions = totalSessions
        self.totalSecondsSpoken = totalSecondsSpoken
        self.totalCommands = totalCommands
        self.engineCounts = engineCounts
        self.appCounts = appCounts
        self.dailyWords = dailyWords
        self.dailySessions = dailySessions
    }
}

// MARK: - Daily Activity Bar Item

public struct DailySpeechActivity: Identifiable, Equatable {
    public var id: String { dateKey }
    public let dateKey: String
    public let dayLabel: String
    public let date: Date
    public let words: Int
    public let sessions: Int
    public let isToday: Bool

    public init(dateKey: String, dayLabel: String, date: Date, words: Int, sessions: Int, isToday: Bool) {
        self.dateKey = dateKey
        self.dayLabel = dayLabel
        self.date = date
        self.words = words
        self.sessions = sessions
        self.isToday = isToday
    }
}

// MARK: - Speech Stats Computed Summary

public struct SpeechStatsSummary: Equatable {
    public let totalWords: Int
    public let totalSessions: Int
    public let totalSecondsSpoken: Double
    public let totalCommands: Int
    public let estimatedMinutesSaved: Double
    public let formattedTimeSaved: String
    public let speakingSpeedWPM: Int
    public let averageWordsPerSession: Double

    public let wordsToday: Int
    public let sessionsToday: Int
    public let timeSavedTodayFormatted: String

    public let wordsThisWeek: Int
    public let sessionsThisWeek: Int
    public let timeSavedThisWeekFormatted: String

    public let dailyActivity: [DailySpeechActivity] // 7 days
    public let engineDistribution: [(name: String, count: Int, percentage: Double)]
    public let topAppsDistribution: [(name: String, count: Int, percentage: Double)]

    public static func == (lhs: SpeechStatsSummary, rhs: SpeechStatsSummary) -> Bool {
        lhs.totalWords == rhs.totalWords &&
        lhs.totalSessions == rhs.totalSessions &&
        lhs.wordsToday == rhs.wordsToday &&
        lhs.wordsThisWeek == rhs.wordsThisWeek
    }
}

// MARK: - Store

public final class TranscriptHistoryStore: ObservableObject {
    public static let shared = TranscriptHistoryStore()
    private static let storageKey = "openflow.transcript_history"
    private static let statsKey = "openflow.speech_stats"
    private static let maxRecords = 60

    @Published public var records: [TranscriptRecord] = []
    @Published public var cumulativeStats: CumulativeSpeechStats = CumulativeSpeechStats()

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        return df
    }()

    private static let dayLabelFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        df.timeZone = .current
        return df
    }()

    public init() {
        load()
        loadStats()
    }

    public func add(
        text: String,
        language: String? = nil,
        engine: String,
        durationSeconds: Double? = nil,
        appName: String? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newRecord = TranscriptRecord(
            text: trimmed,
            language: language,
            engine: engine,
            timestamp: Date(),
            durationSeconds: durationSeconds,
            appName: appName
        )
        records.insert(newRecord, at: 0)
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }
        save()

        // Accumulate statistics
        let wordCount = newRecord.wordCount
        let duration = durationSeconds ?? (Double(wordCount) / 150.0 * 60.0)
        accumulateSpeech(words: wordCount, duration: duration, engine: engine, appName: appName)
    }

    public func recordVoiceAction(_ actionName: String) {
        cumulativeStats.totalCommands += 1
        let key = "Voice Command (\(actionName))"
        cumulativeStats.engineCounts[key, default: 0] += 1
        saveStats()
    }

    public func delete(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    public func clear() {
        records.removeAll()
        save()
    }

    public func resetStats() {
        cumulativeStats = CumulativeSpeechStats()
        saveStats()
    }

    // MARK: - Summary Calculation

    public var statsSummary: SpeechStatsSummary {
        // Base words & sessions is cumulative maxed against in-memory records
        let inMemoryWords = records.reduce(0) { $0 + $1.wordCount }
        let totalWords = max(cumulativeStats.totalWords, inMemoryWords)
        let totalSessions = max(cumulativeStats.totalSessions, records.count)
        let inMemorySeconds = records.compactMap { $0.durationSeconds }.reduce(0, +)
        let totalSecondsSpoken = max(cumulativeStats.totalSecondsSpoken, inMemorySeconds)
        let totalCommands = cumulativeStats.totalCommands

        // Productivity calculation:
        // Average speaking: 150 WPM (or actual measured WPM). Average typing: 40 WPM.
        // Typing minutes = words / 40.0. Speaking minutes = words / 150.0.
        // Minutes saved = words * (1/40.0 - 1/150.0) = words * (110 / 6000) = words * 0.018333
        let savedMinutes = Double(totalWords) * (1.0 / 40.0 - 1.0 / 150.0)
        let formattedSaved = Self.formatTimeDuration(minutes: savedMinutes)

        // Measured speaking speed
        let speedWPM: Int
        if totalSecondsSpoken > 10 && totalWords > 0 {
            speedWPM = max(60, min(300, Int(Double(totalWords) / (totalSecondsSpoken / 60.0))))
        } else {
            speedWPM = 150
        }

        let avgWords = totalSessions > 0 ? (Double(totalWords) / Double(totalSessions)) : 0.0

        // Today's breakdown
        let todayKey = Self.dayFormatter.string(from: Date())
        let wordsToday = cumulativeStats.dailyWords[todayKey] ?? records.filter {
            Self.dayFormatter.string(from: $0.timestamp) == todayKey
        }.reduce(0) { $0 + $1.wordCount }
        let sessionsToday = cumulativeStats.dailySessions[todayKey] ?? records.filter {
            Self.dayFormatter.string(from: $0.timestamp) == todayKey
        }.count
        let savedMinutesToday = Double(wordsToday) * (1.0 / 40.0 - 1.0 / 150.0)

        // Last 7 days activity
        let calendar = Calendar.current
        var last7Days: [DailySpeechActivity] = []
        var wordsThisWeek = 0
        var sessionsThisWeek = 0

        for dayOffset in (0..<7).reversed() {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let key = Self.dayFormatter.string(from: date)
                let label = dayOffset == 0 ? "Today" : Self.dayLabelFormatter.string(from: date)
                let count = cumulativeStats.dailyWords[key] ?? records.filter {
                    Self.dayFormatter.string(from: $0.timestamp) == key
                }.reduce(0) { $0 + $1.wordCount }
                let sess = cumulativeStats.dailySessions[key] ?? records.filter {
                    Self.dayFormatter.string(from: $0.timestamp) == key
                }.count

                wordsThisWeek += count
                sessionsThisWeek += sess
                last7Days.append(DailySpeechActivity(
                    dateKey: key,
                    dayLabel: label,
                    date: date,
                    words: count,
                    sessions: sess,
                    isToday: dayOffset == 0
                ))
            }
        }

        let savedMinutesThisWeek = Double(wordsThisWeek) * (1.0 / 40.0 - 1.0 / 150.0)

        // Engine distribution
        var engines = cumulativeStats.engineCounts
        if engines.isEmpty {
            for record in records {
                engines[record.engine, default: 0] += 1
            }
        }
        let totalEngineSamples = max(1, engines.values.reduce(0, +))
        let engineDist: [(name: String, count: Int, percentage: Double)] = engines
            .map { ($0.key, $0.value, (Double($0.value) / Double(totalEngineSamples)) * 100.0) }
            .sorted { $0.count > $1.count }

        // Top Apps distribution
        var apps = cumulativeStats.appCounts
        if apps.isEmpty {
            for record in records {
                if let app = record.appName, !app.isEmpty {
                    apps[app, default: 0] += 1
                }
            }
        }
        let totalAppSamples = max(1, apps.values.reduce(0, +))
        let appDist: [(name: String, count: Int, percentage: Double)] = apps
            .map { ($0.key, $0.value, (Double($0.value) / Double(totalAppSamples)) * 100.0) }
            .sorted { $0.count > $1.count }

        return SpeechStatsSummary(
            totalWords: totalWords,
            totalSessions: totalSessions,
            totalSecondsSpoken: totalSecondsSpoken,
            totalCommands: totalCommands,
            estimatedMinutesSaved: savedMinutes,
            formattedTimeSaved: formattedSaved,
            speakingSpeedWPM: speedWPM,
            averageWordsPerSession: avgWords,
            wordsToday: wordsToday,
            sessionsToday: sessionsToday,
            timeSavedTodayFormatted: Self.formatTimeDuration(minutes: savedMinutesToday),
            wordsThisWeek: wordsThisWeek,
            sessionsThisWeek: sessionsThisWeek,
            timeSavedThisWeekFormatted: Self.formatTimeDuration(minutes: savedMinutesThisWeek),
            dailyActivity: last7Days,
            engineDistribution: engineDist,
            topAppsDistribution: appDist
        )
    }

    public static func formatTimeDuration(minutes: Double) -> String {
        if minutes <= 0.2 {
            return "< 1 min"
        } else if minutes < 60 {
            return "\(Int(round(minutes))) min"
        } else {
            let hours = minutes / 60.0
            if hours < 10 {
                return String(format: "%.1f hrs", hours)
            } else {
                return "\(Int(round(hours))) hrs"
            }
        }
    }

    // MARK: - Private Persistence

    private func accumulateSpeech(words: Int, duration: Double, engine: String, appName: String?) {
        cumulativeStats.totalWords += words
        cumulativeStats.totalSessions += 1
        cumulativeStats.totalSecondsSpoken += duration
        cumulativeStats.engineCounts[engine, default: 0] += 1
        if let app = appName, !app.isEmpty {
            cumulativeStats.appCounts[app, default: 0] += 1
        }
        let todayKey = Self.dayFormatter.string(from: Date())
        cumulativeStats.dailyWords[todayKey, default: 0] += words
        cumulativeStats.dailySessions[todayKey, default: 0] += 1
        saveStats()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([TranscriptRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        }
    }

    private func loadStats() {
        if let data = UserDefaults.standard.data(forKey: Self.statsKey),
           let decoded = try? JSONDecoder().decode(CumulativeSpeechStats.self, from: data) {
            cumulativeStats = decoded
        } else {
            // Seed from existing history records if any exist
            var stats = CumulativeSpeechStats()
            for r in records {
                let w = r.wordCount
                stats.totalWords += w
                stats.totalSessions += 1
                let dur = r.durationSeconds ?? (Double(w) / 150.0 * 60.0)
                stats.totalSecondsSpoken += dur
                stats.engineCounts[r.engine, default: 0] += 1
                if let app = r.appName, !app.isEmpty {
                    stats.appCounts[app, default: 0] += 1
                }
                let k = Self.dayFormatter.string(from: r.timestamp)
                stats.dailyWords[k, default: 0] += w
                stats.dailySessions[k, default: 0] += 1
            }
            cumulativeStats = stats
            saveStats()
        }
    }

    private func saveStats() {
        if let encoded = try? JSONEncoder().encode(cumulativeStats) {
            UserDefaults.standard.set(encoded, forKey: Self.statsKey)
        }
    }
}
