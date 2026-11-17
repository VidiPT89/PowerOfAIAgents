import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What Apple's on-device NaturalLanguage framework finds in a text, with the time of each task.
struct TextAnalysis: Sendable, Equatable {
    struct LanguageGuess: Sendable, Equatable, Identifiable {
        var code: String
        var probability: Double
        var id: String { code }
    }

    enum EntityKind: String, Sendable, CaseIterable { case person, place, organization }

    struct Entity: Sendable, Equatable, Hashable {
        var text: String
        var kind: EntityKind
    }

    struct Keyword: Sendable, Equatable, Identifiable {
        var word: String
        var count: Int
        var id: String { word }
    }

    struct Timing: Sendable, Equatable, Identifiable {
        enum Task: String, Sendable, CaseIterable { case language, tokens, sentiment, entities, keywords }
        var task: Task
        var milliseconds: Double
        var id: String { task.rawValue }
    }

    var languages: [LanguageGuess] = []
    var words = 0
    var sentences = 0
    /// From -1 (negative) to 1 (positive); nil when the language has no sentiment model.
    var sentiment: Double?
    var entities: [Entity] = []
    var keywords: [Keyword] = []
    var nouns = 0
    var verbs = 0
    var adjectives = 0
    var timings: [Timing] = []

    var dominantLanguage: String? { languages.first?.code }
    var totalMilliseconds: Double { timings.map(\.milliseconds).reduce(0, +) }
}

enum TextAnalyzer {
    /// Runs every task on the text, each one timed on its own.
    static func analyze(_ text: String) -> TextAnalysis {
        var result = TextAnalysis()
        let clock = ContinuousClock()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return result }
        let range = text.startIndex..<text.endIndex

        var language: NLLanguage?
        result.timings.append(.init(task: .language, milliseconds: clock.measure {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            language = recognizer.dominantLanguage
            result.languages = recognizer.languageHypotheses(withMaximum: 3)
                .map { TextAnalysis.LanguageGuess(code: $0.key.rawValue, probability: $0.value) }
                .sorted { $0.probability > $1.probability }
        }.milliseconds))

        result.timings.append(.init(task: .tokens, milliseconds: clock.measure {
            let words = NLTokenizer(unit: .word)
            words.string = text
            if let language { words.setLanguage(language) }
            result.words = words.tokens(for: range).count
            let sentences = NLTokenizer(unit: .sentence)
            sentences.string = text
            result.sentences = sentences.tokens(for: range).count
        }.milliseconds))

        result.timings.append(.init(task: .sentiment, milliseconds: clock.measure {
            let tagger = NLTagger(tagSchemes: [.sentimentScore])
            tagger.string = text
            if let language { tagger.setLanguage(language, range: range) }
            var scores: [Double] = []
            tagger.enumerateTags(in: range, unit: .sentence, scheme: .sentimentScore, options: []) { tag, _ in
                if let raw = tag?.rawValue, let score = Double(raw) { scores.append(score) }
                return true
            }
            result.sentiment = sentimentAverage(scores)
        }.milliseconds))

        result.timings.append(.init(task: .entities, milliseconds: clock.measure {
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = text
            if let language { tagger.setLanguage(language, range: range) }
            var seen = Set<TextAnalysis.Entity>()
            tagger.enumerateTags(in: range, unit: .word, scheme: .nameType,
                                 options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, tokenRange in
                let kind: TextAnalysis.EntityKind? = switch tag {
                case .personalName: .person
                case .placeName: .place
                case .organizationName: .organization
                default: nil
                }
                if let kind {
                    let entity = TextAnalysis.Entity(text: String(text[tokenRange]), kind: kind)
                    if seen.insert(entity).inserted { result.entities.append(entity) }
                }
                return true
            }
        }.milliseconds))

        result.timings.append(.init(task: .keywords, milliseconds: clock.measure {
            let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
            tagger.string = text
            if let language { tagger.setLanguage(language, range: range) }
            var counts: [String: Int] = [:]
            tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass,
                                 options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, tokenRange in
                switch tag {
                case .noun:
                    result.nouns += 1
                    let lemma = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
                    let word = (lemma ?? String(text[tokenRange])).lowercased()
                    if word.count > 2 { counts[word, default: 0] += 1 }
                case .verb: result.verbs += 1
                case .adjective: result.adjectives += 1
                default: break
                }
                return true
            }
            result.keywords = counts.map { TextAnalysis.Keyword(word: $0.key, count: $0.value) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.word < $1.word }
                .prefix(8).map { $0 }
        }.milliseconds))

        return result
    }

    /// Some systems download tagger models on demand: ask for them first (best effort, nothing of the text is sent).
    /// Never waits more than `limit` seconds: without a download the analysis runs with what the system has.
    static func prepareModels(for text: String, limit: Double = 4) async {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return }
        let finished = Flag()
        Task.detached(priority: .userInitiated) {
            for scheme in [NLTagScheme.lexicalClass, .nameType, .lemma, .sentimentScore] {
                _ = try? await NLTagger.requestAssets(for: language, tagScheme: scheme)
            }
            finished.set()
        }
        let deadline = ContinuousClock.now + .seconds(limit)
        while !finished.value, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false
        var value: Bool { lock.withLock { raised } }
        func set() { lock.withLock { raised = true } }
    }

    /// Average of the sentence scores, or nil when they look like a missing model: with no model for a language,
    /// the system gives every sentence the same extreme or zero score.
    static func sentimentAverage(_ scores: [Double]) -> Double? {
        guard let first = scores.first else { return nil }
        if scores.count >= 2, scores.allSatisfy({ $0 == first }), [-1.0, 0, 1].contains(first) { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// Sentences of the text, in order.
    static func sentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// Finds the sentences of a text closest in meaning to a query, with the system's sentence embedding.
struct SemanticSearch: Sendable, Equatable {
    struct Match: Sendable, Equatable, Identifiable {
        var sentence: String
        /// 0 is identical in meaning; the embedding's cosine distance goes up to 2.
        var distance: Double
        var id: String { sentence }
    }

    var matches: [Match]
    var language: String
    var milliseconds: Double

    static func run(query: String, in text: String) -> SemanticSearch? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage ?? .english
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) ?? NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        let sentences = TextAnalyzer.sentences(text)
        var matches: [Match] = []
        let elapsed = ContinuousClock().measure {
            matches = sentences.map { Match(sentence: $0, distance: embedding.distance(between: query, and: $0)) }
                .filter { $0.distance.isFinite }
                .sorted { $0.distance < $1.distance }
        }
        return SemanticSearch(matches: Array(matches.prefix(5)), language: (embedding.language ?? language).rawValue, milliseconds: elapsed.milliseconds)
    }
}

/// A classifier the person defines: does each term belong to a topic? Decided by the system word embedding
/// and, where available, Apple's on-device model. Both only answer yes or no.
struct TopicClassifier {
    struct Decision: Sendable, Equatable, Identifiable {
        var term: String
        var distance: Double
        var encoderSays: Bool
        var encoderMilliseconds: Double
        var modelSays: Bool?
        var modelMilliseconds: Double?
        var id: String { term }
        var agree: Bool? { modelSays.map { $0 == encoderSays } }
    }

    private let embedding: NLEmbedding
    private let anchors: [String]

    /// Language of the word embedding actually used.
    let language: AppLanguage

    /// Topic words separated by commas. The embedding follows the language the words are written in
    /// (Portuguese or English), then the app's language, and only uses one that is installed.
    init?(topic: String, terms: [String] = [], language preferred: AppLanguage, hasEmbedding: (AppLanguage) -> Bool = { NLEmbedding.wordEmbedding(for: $0.nl) != nil }) {
        let anchors = Self.words(topic)
        guard !anchors.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .portuguese]
        recognizer.processString((anchors + terms).joined(separator: ", "))
        let detected: AppLanguage? = switch recognizer.dominantLanguage {
        case .portuguese?: .portuguese
        case .english?: .english
        default: nil
        }
        let candidates = [detected, preferred].compactMap { $0 }
        guard let chosen = candidates.first(where: hasEmbedding), let embedding = NLEmbedding.wordEmbedding(for: chosen.nl) else { return nil }
        self.embedding = embedding
        self.anchors = anchors
        language = chosen
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { $0 == "," || $0 == "\n" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Smallest distance between any word of the term and any topic word; 2 when unknown.
    func distance(_ term: String) -> Double {
        term.lowercased().split { $0 == " " || $0 == "-" }.compactMap { word -> Double? in
            anchors.flatMap { anchor in anchor.split(separator: " ").map(String.init) }.compactMap { anchor -> Double? in
                let d = embedding.distance(between: String(word), and: anchor)
                return d.isFinite && d < 2 ? d : nil
            }.min()
        }.min() ?? 2
    }

    func decide(_ terms: [String], threshold: Double) -> [Decision] {
        let clock = ContinuousClock()
        return terms.map { term in
            var d = 2.0
            let elapsed = clock.measure { d = distance(term) }
            return Decision(term: term, distance: d, encoderSays: d < threshold, encoderMilliseconds: elapsed.milliseconds)
        }
    }

    /// Apple's on-device model, one fresh session per term. Throws when the model is unavailable.
    static func modelSays(_ term: String, topic: String, language: AppLanguage) async throws -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let instructions = language == .portuguese
                ? "Classificas termos isolados. Decide se cada termo pertence ao tema: \(topic)."
                : "You label single terms. Decide whether each term belongs to the topic: \(topic)."
            let session = LanguageModelSession(instructions: instructions)
            let prompt = language == .portuguese ? "Termo: \(term)" : "Term: \(term)"
            return try await session.respond(to: prompt, generating: TopicVerdict.self).content.belongs
        }
        #endif
        throw GenerativeClassifier.unavailableReason ?? .other
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct TopicVerdict {
    @Guide(description: "true only if the term belongs to the topic")
    var belongs: Bool
}
#endif

extension AppLanguage {
    var nl: NLLanguage { self == .portuguese ? .portuguese : .english }
}
