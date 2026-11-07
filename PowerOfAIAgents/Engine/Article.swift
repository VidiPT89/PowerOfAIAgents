import Foundation

/// A word of the article. Links carry their index and whether they are about spiders.
struct ArticleToken: Sendable, Equatable {
    let text: String
    let link: Int?
    let relevant: Bool
    /// Punctuation right after a link sticks to it, without a space.
    var joinsPrevious = false
}

struct Article: Sendable {
    let title: String
    let paragraphs: [[ArticleToken]]
    let relevance: [Bool]

    /// Markup: `[words|s]` is a link about spiders, `[words|n]` is any other link.
    init(title: String, markup: [String]) {
        self.title = title
        var linkCount = 0
        var relevance: [Bool] = []
        var paragraphs: [[ArticleToken]] = []
        for source in markup {
            var tokens: [ArticleToken] = []
            var rest = Substring(source)
            while !rest.isEmpty {
                if let open = rest.firstIndex(of: "["), let close = rest[open...].firstIndex(of: "]") {
                    tokens += Article.words(rest[..<open], link: nil, relevant: false)
                    let body = rest[rest.index(after: open)..<close]
                    let parts = body.split(separator: "|", maxSplits: 1)
                    let relevant = parts.count > 1 && parts[1] == "s"
                    tokens += Article.words(parts.first ?? "", link: linkCount, relevant: relevant)
                    relevance.append(relevant)
                    linkCount += 1
                    rest = rest[rest.index(after: close)...]
                } else {
                    tokens += Article.words(rest, link: nil, relevant: false)
                    rest = ""
                }
            }
            paragraphs.append(tokens)
        }
        self.paragraphs = paragraphs
        self.relevance = relevance
    }

    private static func words(_ text: Substring, link: Int?, relevant: Bool) -> [ArticleToken] {
        let attached = text.first.map { !$0.isWhitespace } ?? false
        return text.split(separator: " ").enumerated().map { index, word in
            ArticleToken(text: String(word), link: link, relevant: relevant, joinsPrevious: index == 0 && attached && link == nil)
        }
    }

    static func sample(_ language: AppLanguage) -> Article {
        language == .portuguese ? portuguese : english
    }

    // Both languages share the same link order, so a race can switch language without changing the result.
    static let english = Article(title: "Life under the old oak", markup: [
        "At dawn the garden is already busy. A [wolf spider|s] waits beside a stone while [ants|n] carry seeds along the [path|n]. Above them, an [orb weaver|s] repairs the threads its [web|s] lost during the [night|n].",
        "Each strand is [spider silk|s], a protein fibre stronger by weight than [steel|n]. The [spinnerets|s] at the tip of the [abdomen|s] mix several kinds of silk, some sticky, some dry, to build a trap that is almost invisible against the [sky|n].",
        "Under the leaves live [beetles|n], [snails|n] and patient [jumping spiders|s]. With eight eyes and excellent vision, they stalk [flies|n] like tiny cats. Their [cephalothorax|s] holds the brain, while a [hydraulic system|s] extends the legs for a sudden leap.",
        "Gardeners usually notice [roses|n], [rain|n] and the colour of the [soil|n]. Few look closer at the [arachnids|s] that keep pests in check. A single [garden spider|s] can catch hundreds of [insects|n] in a season, without any [pesticide|n].",
        "On warmer coasts, a [tarantula|s] may dig its burrow near the [roots|n] of a [pine|n]. Its [venom|s] is mild for people, but its [hairs|s] can irritate the skin. The [moon|n] rises, the [owls|n] wake up and the hunt changes shift.",
        "By morning, [dew|n] beads on every line. [Fossils|n] show that [silk|s] is older than [flowers|n] themselves, which makes the [web|s] beside the [fence|n] one of the oldest designs in the [garden|n].",
    ])

    static let portuguese = Article(title: "Vida debaixo do velho carvalho", markup: [
        "De madrugada o jardim já está em movimento. Uma [aranha-lobo|s] espera junto a uma pedra enquanto as [formigas|n] levam sementes pelo [caminho|n]. Por cima delas, uma [aranha-de-jardim tecedeira|s] repara os fios que a [teia|s] perdeu durante a [noite|n].",
        "Cada fio é [seda de aranha|s], uma fibra de proteína mais resistente, por peso, do que o [aço|n]. As [fieiras|s] na ponta do [abdómen|s] misturam vários tipos de seda, uns pegajosos, outros secos, para construir uma armadilha quase invisível contra o [céu|n].",
        "Debaixo das folhas vivem [escaravelhos|n], [caracóis|n] e pacientes [aranhas-saltadoras|s]. Com oito olhos e uma visão excelente, perseguem [moscas|n] como pequenos gatos. O [cefalotórax|s] guarda o cérebro, e um [sistema hidráulico|s] estica as patas para um salto repentino.",
        "Quem cuida do jardim repara nas [rosas|n], na [chuva|n] e na cor da [terra|n]. Poucos olham com atenção para os [aracnídeos|s] que mantêm as pragas controladas. Uma única [aranha-de-jardim|s] apanha centenas de [insetos|n] numa estação, sem qualquer [pesticida|n].",
        "Em costas mais quentes, uma [tarântula|s] pode cavar a toca junto às [raízes|n] de um [pinheiro|n]. O [veneno|s] é fraco para as pessoas, mas os [pelos|s] podem irritar a pele. A [lua|n] nasce, os [mochos|n] acordam e a caça muda de turno.",
        "De manhã, o [orvalho|n] pousa em cada fio. Os [fósseis|n] mostram que a [seda|s] é mais antiga do que as próprias [flores|n], o que faz da [teia|s] junto à [vedação|n] um dos desenhos mais antigos do [jardim|n].",
    ])
}
