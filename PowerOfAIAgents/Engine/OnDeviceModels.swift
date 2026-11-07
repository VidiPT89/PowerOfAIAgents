import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Outcome of a real model deciding on the article's links.
struct ModelRun: Sendable, Equatable {
    var decisions: Int
    var correct: Int
    /// Wall-clock time of all decisions, in milliseconds.
    var totalMilliseconds: Double

    var accuracy: Double { decisions == 0 ? 0 : Double(correct) / Double(decisions) }
    var averageMilliseconds: Double { decisions == 0 ? 0 : totalMilliseconds / Double(decisions) }
    var decisionsPerSecond: Double { averageMilliseconds > 0 ? 1000 / averageMilliseconds : 0 }
}

/// A word-embedding encoder that ships with the system: one vector lookup and a distance, no text generation.
struct EmbeddingClassifier {
    static let threshold = 0.8

    /// Only the concept itself, so words from the article never match by being listed here.
    static func anchors(_ language: AppLanguage) -> [String] {
        language == .portuguese ? ["aranha", "aracnídeo"] : ["spider", "arachnid"]
    }

    private let embedding: NLEmbedding
    private let anchors: [String]

    init?(language: AppLanguage = .english) {
        guard let embedding = NLEmbedding.wordEmbedding(for: language == .portuguese ? .portuguese : .english) else { return nil }
        self.embedding = embedding
        anchors = Self.anchors(language)
    }

    /// Smallest distance between any word of the term and an anchor; 2 when the words are unknown.
    /// Hyphenated compounds ("aranha-lobo") are split, because the embedding only knows single words.
    func distance(_ term: String) -> Double {
        term.lowercased().split { $0 == " " || $0 == "-" }.compactMap { word -> Double? in
            anchors.compactMap { anchor -> Double? in
                let d = embedding.distance(between: String(word), and: anchor)
                return d.isFinite && d < 2 ? d : nil
            }.min()
        }.min() ?? 2
    }

    func isAboutSpiders(_ term: String) -> Bool { distance(term) < Self.threshold }

    /// Decides every link `rounds` times so the timing is stable even when one decision takes microseconds.
    func run(on links: [ArticleLink], rounds: Int = 40) -> ModelRun {
        guard rounds > 0, !links.isEmpty else {
            return ModelRun(decisions: 0, correct: 0, totalMilliseconds: 0)
        }
        let clock = ContinuousClock()
        var correct = 0
        let elapsed = clock.measure {
            for round in 0..<rounds {
                for link in links {
                    let right = isAboutSpiders(link.text) == link.relevant
                    if round == 0, right { correct += 1 }
                }
            }
        }
        return ModelRun(decisions: links.count, correct: correct,
                        totalMilliseconds: elapsed.milliseconds / Double(rounds))
    }
}

/// Apple's on-device language model (Apple Intelligence), when the device and system support it.
enum GenerativeClassifier {
    enum Unavailable: Error, Equatable, Sendable {
        case systemTooOld, simulator, deviceNotEligible, intelligenceOff, modelNotReady, other
    }

    /// nil when the model can be used right now.
    static var unavailableReason: Unavailable? {
        #if targetEnvironment(simulator)
        // The simulator reports the model as available, but generation fails there.
        return .simulator
        #else
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible): return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled): return .intelligenceOff
            case .unavailable(.modelNotReady): return .modelNotReady
            case .unavailable: return .other
            }
        }
        #endif
        return .systemTooOld
        #endif
    }

    static func instructions(_ language: AppLanguage) -> String {
        language == .portuguese
            ? "Classificas termos isolados, em português de Portugal, tirados de um artigo sobre um jardim. Decide se cada termo é sobre aranhas: um tipo de aranha, uma parte do corpo de uma aranha, ou algo que as aranhas fazem ou usam."
            : "You label single terms taken from an article about a garden. Decide whether each term is about spiders: a kind of spider, a part of a spider's body, or something spiders make or use."
    }

    /// A fresh session per link, so every decision pays its own full cost.
    static func isAboutSpiders(_ term: String, language: AppLanguage = .english) async throws -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions(language))
            let prompt = language == .portuguese ? "Termo: \(term)" : "Term: \(term)"
            let response = try await session.respond(to: prompt, generating: SpiderVerdict.self)
            return response.content.aboutSpiders
        }
        #endif
        throw unavailableReason ?? .other
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct SpiderVerdict {
    @Guide(description: "true only if the term is about spiders")
    var aboutSpiders: Bool
}
#endif

extension Duration {
    var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }
}
