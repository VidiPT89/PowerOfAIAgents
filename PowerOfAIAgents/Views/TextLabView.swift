import NaturalLanguage
import SwiftUI

@MainActor
final class TextLabModel: ObservableObject {
    enum Mode: String, CaseIterable { case analyze, search, classify }

    @Published var mode: Mode = .analyze
    @Published var text = ""
    @Published var query = ""
    @Published var topic = ""
    @Published var terms = ""
    @Published var threshold = 1.1
    @Published private(set) var analysis: TextAnalysis?
    @Published private(set) var search: SemanticSearch?
    @Published private(set) var searchUnavailable = false
    @Published private(set) var decisions: [TopicClassifier.Decision] = []
    @Published private(set) var classifierUnavailable = false
    @Published private(set) var modelFailed = false
    @Published private(set) var busy = false
    private var job: Task<Void, Never>?

    func analyze() {
        let text = text
        busy = true
        job?.cancel()
        job = Task {
            await TextAnalyzer.prepareModels(for: text)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { TextAnalyzer.analyze(text) }.value
            guard !Task.isCancelled else { return }
            analysis = result
            busy = false
        }
    }

    func runSearch() {
        let text = text, query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !text.isEmpty else { return }
        busy = true
        job?.cancel()
        job = Task {
            let result = await Task.detached(priority: .userInitiated) { SemanticSearch.run(query: query, in: text) }.value
            guard !Task.isCancelled else { return }
            search = result
            searchUnavailable = result == nil
            busy = false
        }
    }

    var termList: [String] { TopicClassifier.words(terms) }

    func classify(language: AppLanguage, useModel: Bool) {
        let topic = topic, terms = termList, threshold = threshold
        guard !terms.isEmpty else { return }
        guard let classifier = TopicClassifier(topic: topic, terms: terms, language: language) else {
            classifierUnavailable = true
            decisions = []
            return
        }
        classifierUnavailable = false
        modelFailed = false
        decisions = classifier.decide(terms, threshold: threshold)
        guard useModel else { return }
        busy = true
        job?.cancel()
        job = Task {
            let clock = ContinuousClock()
            for index in decisions.indices {
                guard !Task.isCancelled else { return }
                do {
                    var says = false
                    let elapsed = try await clock.measure { says = try await TopicClassifier.modelSays(terms[index], topic: topic, language: classifier.language) }
                    guard !Task.isCancelled, index < decisions.count else { return }
                    decisions[index].modelSays = says
                    decisions[index].modelMilliseconds = elapsed.milliseconds
                } catch {
                    modelFailed = true
                    break
                }
            }
            busy = false
        }
    }

    /// The encoder is instant, so moving the threshold re-decides without the model.
    func rethreshold() {
        for i in decisions.indices { decisions[i].encoderSays = decisions[i].distance < threshold }
    }

    func loadExample(_ language: AppLanguage) {
        if language == .portuguese {
            text = "A Apple apresentou em Cupertino novos modelos que correm no iPhone. A Marta, programadora em Lisboa, ficou impressionada com a rapidez: as respostas chegam em milissegundos e nada sai do aparelho. Ainda assim, a bateria preocupa-a um pouco. Na empresa dela, a equipa vai testar a mesma funcionalidade na nuvem e comparar os tempos."
            query = "privacidade dos dados"
            topic = "comida"
            terms = "maçã, pão, teclado, sopa, queijo, comboio, laranja, cadeira"
        } else {
            text = "Apple introduced new models in Cupertino that run on the iPhone. Martha, a developer in Lisbon, was impressed by the speed: answers arrive in milliseconds and nothing leaves the device. Still, the battery worries her a little. At her company, the team will test the same feature in the cloud and compare the timings."
            query = "data privacy"
            topic = "food"
            terms = "apple, bread, keyboard, soup, cheese, train, orange, chair"
        }
        analysis = nil
        search = nil
        decisions = []
    }

    func cancel() {
        job?.cancel()
        job = nil
        busy = false
    }
}

/// Apple's on-device language tools on the person's own text, each one timed.
struct TextLabView: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var model: TextLabModel
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: prefs.text("Laboratório de texto", "Text lab"),
                    title: prefs.text("IA no aparelho, no teu texto", "On-device AI, on your text"),
                    subtitle: prefs.text(
                        "Cola um texto e vê o que os modelos da Apple encontram sem internet: idioma, sentimento, nomes, palavras-chave, pesquisa por significado e um classificador teu. Cada tarefa mostra quanto demorou.",
                        "Paste a text and see what Apple's models find with no internet: language, sentiment, names, keywords, search by meaning and a classifier of your own. Every task shows how long it took."))
                Picker(prefs.text("Ferramenta", "Tool"), selection: $model.mode) {
                    Text(prefs.text("Analisar", "Analyse")).tag(TextLabModel.Mode.analyze)
                    Text(prefs.text("Pesquisar", "Search")).tag(TextLabModel.Mode.search)
                    Text(prefs.text("Classificar", "Classify")).tag(TextLabModel.Mode.classify)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch model.mode {
                case .analyze: analyzeSection
                case .search: searchSection
                case .classify: classifySection
                }
                Text(prefs.text("Tudo corre neste aparelho com as frameworks da Apple. O texto não é enviado nem guardado.",
                                "Everything runs on this device with Apple's frameworks. The text is neither sent nor stored."))
                    .font(.caption)
                    .foregroundStyle(Brand.faint(scheme))
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Brand.background(scheme).ignoresSafeArea())
        .onAppear { if model.text.isEmpty { model.loadExample(prefs.language) } }
    }

    // MARK: Analyse

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $model.text)
                .focused($focused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140, maxHeight: 220)
                .padding(8)
                .background(Brand.panel2(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(prefs.text("Texto a analisar", "Text to analyse"))
            HStack {
                Text(prefs.text("\(model.text.count) caracteres", "\(model.text.count) characters"))
                    .font(.caption.monospacedDigit()).foregroundStyle(Brand.faint(scheme))
                Spacer()
                Button(prefs.text("Exemplo", "Example")) { model.loadExample(prefs.language) }
                    .font(.caption.weight(.semibold))
                Button(prefs.text("Limpar", "Clear")) { model.text = "" }
                    .font(.caption.weight(.semibold))
            }
            .tint(Brand.accent(scheme))
        }
    }

    private var analyzeSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                editor
                Button {
                    focused = false
                    model.analyze()
                } label: {
                    Label(prefs.text("Analisar no aparelho", "Analyse on device"), systemImage: "text.magnifyingglass")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                .overlay(alignment: .trailing) { if model.busy { ProgressView().controlSize(.small).offset(x: 30) } }
            }
            .card()
            if let analysis = model.analysis { analysisCards(analysis) }
        }
    }

    @ViewBuilder private func analysisCards(_ analysis: TextAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: prefs.text("Resultado", "Result"), detail: "NaturalLanguage · \(analysis.totalMilliseconds.milliseconds)", symbol: "cpu")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                StatTile(label: prefs.text("idioma", "language"), value: languageName(analysis.dominantLanguage), tint: Brand.accent(scheme))
                StatTile(label: prefs.text("sentimento", "sentiment"), value: sentimentText(analysis.sentiment), tint: sentimentColor(analysis.sentiment))
                StatTile(label: prefs.text("palavras", "words"), value: "\(analysis.words)")
                StatTile(label: prefs.text("frases", "sentences"), value: "\(analysis.sentences)")
                StatTile(label: prefs.text("nomes · verbos · adjetivos", "nouns · verbs · adjectives"), value: "\(analysis.nouns) · \(analysis.verbs) · \(analysis.adjectives)")
            }
            if analysis.words > 3, analysis.nouns + analysis.verbs + analysis.adjectives == 0 {
                Label(prefs.text("Este sistema não tem o modelo de classes de palavras para este idioma (o simulador não o inclui), por isso nomes e palavras-chave ficam vazios.",
                                 "This system has no part-of-speech model for this language (the simulator does not include it), so names and keywords stay empty."),
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(Brand.accent(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if analysis.languages.count > 1 {
                Text(prefs.text("Hipóteses: ", "Hypotheses: ") + analysis.languages.map { "\(languageName($0.code)) \(prefs.number($0.probability * 100))%" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Brand.dim(scheme))
            }
        }
        .card()

        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: prefs.text("Nomes encontrados", "Names found"), symbol: "person.text.rectangle")
            if analysis.entities.isEmpty {
                Text(prefs.text("Nenhuma pessoa, lugar ou organização reconhecida.", "No person, place or organisation recognised."))
                    .font(.subheadline).foregroundStyle(Brand.faint(scheme))
            } else {
                FlowChips(items: analysis.entities.map { ("\($0.text)", entityName($0.kind), entityColor($0.kind)) })
            }
            CardTitle(title: prefs.text("Palavras-chave", "Keywords"), symbol: "tag")
            if analysis.keywords.isEmpty {
                Text(prefs.text("Sem substantivos suficientes.", "Not enough nouns.")).font(.subheadline).foregroundStyle(Brand.faint(scheme))
            } else {
                FlowChips(items: analysis.keywords.map { ($0.word, "×\($0.count)", Brand.orange) })
            }
        }
        .card()

        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: prefs.text("Tempo de cada tarefa", "Time per task"), symbol: "stopwatch")
            let longest = analysis.timings.map(\.milliseconds).max() ?? 1
            ForEach(analysis.timings) { timing in
                HStack(spacing: 10) {
                    Text(taskName(timing.task)).font(.subheadline).frame(width: 130, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule().fill(Brand.gradient)
                            .frame(width: max(4, proxy.size.width * timing.milliseconds / max(longest, 0.001)))
                    }
                    .frame(height: 10)
                    Text(timing.milliseconds.milliseconds).font(.caption.monospacedDigit()).frame(width: 70, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            Text(prefs.text("Um pedido a um modelo na nuvem custa normalmente centenas de milissegundos só de rede. Aqui, todas as tarefas juntas demoraram \(analysis.totalMilliseconds.milliseconds).",
                            "A request to a cloud model usually costs hundreds of milliseconds in network time alone. Here, all tasks together took \(analysis.totalMilliseconds.milliseconds)."))
                .font(.caption).foregroundStyle(Brand.dim(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                editor
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Brand.accent(scheme))
                    TextField(prefs.text("Procura por significado…", "Search by meaning…"), text: $model.query)
                        .plainEntry()
                        .onSubmit { model.runSearch() }
                }
                .padding(12)
                .background(Brand.panel2(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button {
                    focused = false
                    model.runSearch()
                } label: {
                    Label(prefs.text("Pesquisar no aparelho", "Search on device"), systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty || model.text.isEmpty)
                Text(prefs.text("Encontra as frases mais próximas em significado, mesmo sem as mesmas palavras, com o sentence embedding do sistema.",
                                "Finds the sentences closest in meaning, even without the same words, using the system sentence embedding."))
                    .font(.caption).foregroundStyle(Brand.dim(scheme))
            }
            .card()
            if model.searchUnavailable {
                Label(prefs.text("Este aparelho não tem o modelo de frases para este idioma.", "This device has no sentence model for this language."),
                      systemImage: "info.circle")
                    .font(.subheadline).card()
            } else if let search = model.search {
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle(title: prefs.text("Frases mais próximas", "Closest sentences"),
                              detail: "\(languageName(search.language)) · \(search.milliseconds.milliseconds)", symbol: "list.number")
                    ForEach(Array(search.matches.enumerated()), id: \.element.id) { index, match in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 22, height: 22)
                                .background(index == 0 ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Brand.faint(scheme)), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(match.sentence).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                Text(prefs.text("semelhança \(prefs.number(similarity(match.distance) * 100))%", "similarity \(prefs.number(similarity(match.distance) * 100))%"))
                                    .font(.caption2.monospacedDigit()).foregroundStyle(Brand.dim(scheme))
                            }
                        }
                    }
                }
                .card()
            }
        }
    }

    private func similarity(_ distance: Double) -> Double { max(0, min(1, 1 - distance / 2)) }

    // MARK: Classify

    private var classifySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                labelled(prefs.text("Tema (uma ou mais palavras, separadas por vírgulas)", "Topic (one or more words, comma separated)")) {
                    TextField(prefs.text("ex.: comida", "e.g. food"), text: $model.topic).plainEntry()
                }
                labelled(prefs.text("Termos a classificar (vírgulas ou um por linha)", "Terms to classify (commas or one per line)")) {
                    TextEditor(text: $model.terms)
                        .plainEntry()
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 70, maxHeight: 120)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(prefs.text("Limiar do encoder", "Encoder threshold")).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(prefs.number(model.threshold, decimals: 2)).font(.subheadline.monospacedDigit())
                    }
                    Slider(value: $model.threshold, in: 0.3...1.3, step: 0.05)
                        .tint(Brand.orange)
                        .onChange(of: model.threshold) { _, _ in model.rethreshold() }
                    Text(prefs.text("Distância máxima a uma palavra do tema para o encoder dizer \"sim\". Ajusta e vê as decisões mudarem na hora.",
                                    "Largest distance to a topic word for the encoder to say \"yes\". Move it and watch the decisions change instantly."))
                        .font(.caption).foregroundStyle(Brand.dim(scheme))
                }
                HStack(spacing: 10) {
                    Button {
                        focused = false
                        model.classify(language: prefs.language, useModel: GenerativeClassifier.unavailableReason == nil)
                    } label: {
                        Label(prefs.text("Classificar", "Classify"), systemImage: "checklist")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.termList.isEmpty || TopicClassifier.words(model.topic).isEmpty || model.busy)
                    if model.busy { ProgressView().controlSize(.small) }
                }
            }
            .card()
            if model.classifierUnavailable {
                Label(prefs.text("O vocabulário de palavras deste idioma não está instalado neste aparelho. Escreve o tema e os termos em inglês para usar o vocabulário inglês.",
                                 "This language's word embedding is not installed on this device. Write the topic and terms in English to use the English embedding."),
                      systemImage: "character.bubble")
                    .font(.subheadline).card()
            } else if !model.decisions.isEmpty {
                decisionsCard
            }
        }
    }

    private var decisionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: prefs.text("Decisões", "Decisions"), detail: modelDetail, symbol: "checklist")
            ForEach(model.decisions) { decision in
                HStack(spacing: 10) {
                    Text(decision.term).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    verdictPill(decision.encoderSays, label: "encoder", detail: prefs.number(decision.distance, decimals: 2))
                    if let says = decision.modelSays {
                        verdictPill(says, label: "Apple", detail: decision.modelMilliseconds?.milliseconds ?? "")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            let encoderYes = model.decisions.filter(\.encoderSays).count
            let agreements = model.decisions.compactMap(\.agree)
            let encoderTime = model.decisions.map(\.encoderMilliseconds).reduce(0, +) / Double(max(1, model.decisions.count))
            Text(prefs.text("O encoder disse sim a \(encoderYes) de \(model.decisions.count), em média \(encoderTime.milliseconds) por termo.",
                            "The encoder said yes to \(encoderYes) of \(model.decisions.count), on average \(encoderTime.milliseconds) per term.")
                 + (agreements.isEmpty ? "" : prefs.text(" Concorda com o modelo da Apple em \(agreements.filter { $0 }.count) de \(agreements.count).",
                                                          " It agrees with Apple's model on \(agreements.filter { $0 }.count) of \(agreements.count).")))
                .font(.caption).foregroundStyle(Brand.dim(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if model.modelFailed {
                Label(prefs.text("O modelo da Apple não respondeu. Tenta outra vez daqui a pouco.", "Apple's model did not answer. Try again in a moment."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Brand.danger)
            }
        }
        .card()
    }

    private var modelDetail: String {
        GenerativeClassifier.unavailableReason == nil
            ? "NaturalLanguage + Apple Foundation Models"
            : prefs.text("NaturalLanguage (o modelo da Apple precisa de Apple Intelligence)", "NaturalLanguage (Apple's model needs Apple Intelligence)")
    }

    private func verdictPill(_ yes: Bool, label: String, detail: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: yes ? "checkmark.circle.fill" : "xmark.circle")
            Text(label).font(.caption2.weight(.bold))
            Text(detail).font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(yes ? Brand.ok : Brand.dim(scheme))
        .background((yes ? Brand.ok : Brand.faint(scheme)).opacity(0.14), in: Capsule())
        .fixedSize()
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Brand.dim(scheme))
            content()
                .padding(10)
                .background(Brand.panel2(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Names

    private func languageName(_ code: String?) -> String {
        guard let code else { return "?" }
        return prefs.locale.localizedString(forLanguageCode: code)?.capitalized(with: prefs.locale) ?? code
    }

    private func sentimentText(_ score: Double?) -> String {
        guard let score else { return prefs.text("n/d", "n/a") }
        let word = score > 0.25 ? prefs.text("positivo", "positive") : score < -0.25 ? prefs.text("negativo", "negative") : prefs.text("neutro", "neutral")
        return "\(word) \(prefs.number(score, decimals: 1))"
    }

    private func sentimentColor(_ score: Double?) -> Color? {
        guard let score else { return nil }
        return score > 0.25 ? Brand.ok : score < -0.25 ? Brand.danger : nil
    }

    private func entityName(_ kind: TextAnalysis.EntityKind) -> String {
        switch kind {
        case .person: prefs.text("pessoa", "person")
        case .place: prefs.text("lugar", "place")
        case .organization: prefs.text("organização", "organisation")
        }
    }

    private func entityColor(_ kind: TextAnalysis.EntityKind) -> Color {
        switch kind {
        case .person: Color(hex: 0x38BDF8)
        case .place: Brand.ok
        case .organization: Color(hex: 0xE879F9)
        }
    }

    private func taskName(_ task: TextAnalysis.Timing.Task) -> String {
        switch task {
        case .language: prefs.text("Idioma", "Language")
        case .tokens: prefs.text("Palavras e frases", "Words and sentences")
        case .sentiment: prefs.text("Sentimento", "Sentiment")
        case .entities: prefs.text("Nomes", "Names")
        case .keywords: prefs.text("Palavras-chave", "Keywords")
        }
    }
}

/// Chips that wrap onto new lines.
struct FlowChips: View {
    @Environment(\.colorScheme) private var scheme
    let items: [(String, String, Color)]

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    Text(item.0).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.text(scheme))
                    Text(item.1).font(.caption2).foregroundStyle(item.2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(item.2.opacity(0.12), in: Capsule())
            }
        }
    }
}

/// A simple left-to-right layout that wraps.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
