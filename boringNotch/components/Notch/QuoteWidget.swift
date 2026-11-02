//
//  QuoteWidget.swift
//  boringNotch
//
//  Quiet, editorial quote widget in two sizes. A curated offline list (attributions
//  checked against a primary source), rotated every 6 hours with no timer: the quote
//  is derived from the current time slot, so it costs nothing until the notch opens.
//

import SwiftUI

// MARK: - Model

struct Quote: Equatable {
    let text: String
    let author: String
    let source: String

    /// Fits the small widget comfortably.
    var isShort: Bool { text.count <= 64 }
}

enum QuoteLibrary {
    // Only lines traceable to a book, letter, poem or speech. Unsourced "internet quotes" stay out.
    static let all: [Quote] = [
        Quote(text: "Attention is the rarest and purest form of generosity.", author: "Simone Weil", source: "Letter to Joë Bousquet, 1942"),
        Quote(text: "Absolutely unmixed attention is prayer.", author: "Simone Weil", source: "Gravity and Grace"),
        Quote(text: "Do nothing which is of no use.", author: "Miyamoto Musashi", source: "The Book of Five Rings"),
        Quote(text: "Perceive those things which cannot be seen.", author: "Miyamoto Musashi", source: "The Book of Five Rings"),
        Quote(text: "Do not regret what you have done.", author: "Miyamoto Musashi", source: "Dokkōdō"),
        Quote(text: "How we spend our days is, of course, how we spend our lives.", author: "Annie Dillard", source: "The Writing Life"),
        Quote(text: "There is no shortage of good days. It is good lives that are hard to come by.", author: "Annie Dillard", source: "The Writing Life"),
        Quote(text: "Spend it all, shoot it, play it, lose it, all, right away, every time.", author: "Annie Dillard", source: "The Writing Life"),
        Quote(text: "You were made and set here to give voice to this, your own astonishment.", author: "Annie Dillard", source: "The Writing Life"),
        Quote(text: "Pay attention. Be astonished. Tell about it.", author: "Mary Oliver", source: "Sometimes"),
        Quote(text: "Tell me, what is it you plan to do with your one wild and precious life?", author: "Mary Oliver", source: "The Summer Day"),
        Quote(text: "You do not have to be good.", author: "Mary Oliver", source: "Wild Geese"),
        Quote(text: "Attention is the beginning of devotion.", author: "Mary Oliver", source: "Upstream"),
        Quote(text: "Keep some room in your heart for the unimaginable.", author: "Mary Oliver", source: "Mysteries, Yes"),
        Quote(text: "Someone I loved once gave me a box full of darkness. It took me years to understand that this, too, was a gift.", author: "Mary Oliver", source: "The Uses of Sorrow"),
        Quote(text: "We suffer more often in imagination than in reality.", author: "Seneca", source: "Letters to Lucilius, XIII"),
        Quote(text: "While we are postponing, life speeds by.", author: "Seneca", source: "Letters to Lucilius, I"),
        Quote(text: "Everywhere means nowhere.", author: "Seneca", source: "Letters to Lucilius, II"),
        Quote(text: "Life is long if you know how to use it.", author: "Seneca", source: "On the Shortness of Life"),
        Quote(text: "Begin at once to live, and count each separate day as a separate life.", author: "Seneca", source: "Letters to Lucilius, CI"),
        Quote(text: "He suffers more than necessary, who suffers before it is necessary.", author: "Seneca", source: "Letters to Lucilius, XCVIII"),
        Quote(text: "Fire tests gold, suffering tests brave men.", author: "Seneca", source: "On Providence"),
        Quote(text: "Waste no more time arguing about what a good man should be. Be one.", author: "Marcus Aurelius", source: "Meditations, X.16"),
        Quote(text: "Very little is needed to make a happy life.", author: "Marcus Aurelius", source: "Meditations, VII.67"),
        Quote(text: "If it is not right, do not do it; if it is not true, do not say it.", author: "Marcus Aurelius", source: "Meditations, XII.17"),
        Quote(text: "Dig within. Within is the wellspring of good.", author: "Marcus Aurelius", source: "Meditations, VII.59"),
        Quote(text: "Loss is nothing else but change, and change is Nature's delight.", author: "Marcus Aurelius", source: "Meditations, IX.35"),
        Quote(text: "First say to yourself what you would be; and then do what you have to do.", author: "Epictetus", source: "Discourses, III.23"),
        Quote(text: "It is impossible for a man to learn what he thinks he already knows.", author: "Epictetus", source: "Discourses, II.17"),
        Quote(text: "Character is destiny.", author: "Heraclitus", source: "Fragment 119"),
        Quote(text: "Be patient and tough; someday this pain will be useful to you.", author: "Ovid", source: "Amores, III.11"),
        Quote(text: "He who has begun has half done. Dare to be wise; begin!", author: "Horace", source: "Epistles, I.2"),
        Quote(text: "They can because they think they can.", author: "Virgil", source: "Aeneid, V"),
        Quote(text: "Let everything happen to you: beauty and terror. Just keep going. No feeling is final.", author: "Rainer Maria Rilke", source: "The Book of Hours"),
        Quote(text: "Live the questions now.", author: "Rainer Maria Rilke", source: "Letters to a Young Poet"),
        Quote(text: "You must change your life.", author: "Rainer Maria Rilke", source: "Archaic Torso of Apollo"),
        Quote(text: "Go into yourself.", author: "Rainer Maria Rilke", source: "Letters to a Young Poet"),
        Quote(text: "Perhaps all the dragons in our lives are princesses who are only waiting to see us act, just once, with beauty and courage.", author: "Rainer Maria Rilke", source: "Letters to a Young Poet"),
        Quote(text: "Not everything that is faced can be changed, but nothing can be changed until it is faced.", author: "James Baldwin", source: "As Much Truth As One Can Bear, 1962"),
        Quote(text: "Love takes off the masks that we fear we cannot live without and know we cannot live within.", author: "James Baldwin", source: "The Fire Next Time"),
        Quote(text: "Be water, my friend.", author: "Bruce Lee", source: "Longstreet, 1971"),
        Quote(text: "Absorb what is useful, reject what is useless, add what is essentially your own.", author: "Bruce Lee", source: "Tao of Jeet Kune Do"),
        Quote(text: "The world breaks everyone and afterward many are strong at the broken places.", author: "Ernest Hemingway", source: "A Farewell to Arms"),
        Quote(text: "It is good to have an end to journey toward; but it is the journey that matters, in the end.", author: "Ursula K. Le Guin", source: "The Left Hand of Darkness"),
        Quote(text: "The only thing that makes life possible is permanent, intolerable uncertainty.", author: "Ursula K. Le Guin", source: "The Left Hand of Darkness"),
        Quote(text: "In the midst of winter, I found there was, within me, an invincible summer.", author: "Albert Camus", source: "Return to Tipasa"),
        Quote(text: "The struggle itself toward the heights is enough to fill a man's heart.", author: "Albert Camus", source: "The Myth of Sisyphus"),
        Quote(text: "One must still have chaos in oneself to be able to give birth to a dancing star.", author: "Friedrich Nietzsche", source: "Thus Spoke Zarathustra"),
        Quote(text: "You shall become the person you are.", author: "Friedrich Nietzsche", source: "The Gay Science, §270"),
        Quote(text: "He who has a why to live can bear almost any how.", author: "Friedrich Nietzsche", source: "Twilight of the Idols"),
        Quote(text: "A book must be the axe for the frozen sea within us.", author: "Franz Kafka", source: "Letter to Oskar Pollak, 1904"),
        Quote(text: "From a certain point onward there is no longer any turning back. That is the point that must be reached.", author: "Franz Kafka", source: "Zürau Aphorisms"),
        Quote(text: "It is not enough to be busy. So are the ants. The question is: What are we busy about?", author: "Henry David Thoreau", source: "Letter to H. G. O. Blake, 1857"),
        Quote(text: "Rather than love, than money, than fame, give me truth.", author: "Henry David Thoreau", source: "Walden"),
        Quote(text: "The years teach much which the days never know.", author: "Ralph Waldo Emerson", source: "Experience"),
        Quote(text: "The greatest thing in the world is to know how to belong to oneself.", author: "Michel de Montaigne", source: "Essays, I.39"),
        Quote(text: "He who fears he shall suffer, already suffers what he fears.", author: "Michel de Montaigne", source: "Essays, III.13"),
        Quote(text: "The sole cause of man's unhappiness is that he does not know how to stay quietly in his room.", author: "Blaise Pascal", source: "Pensées"),
        Quote(text: "The mystery of human existence lies not in just staying alive, but in finding something to live for.", author: "Fyodor Dostoevsky", source: "The Brothers Karamazov"),
        Quote(text: "When we are no longer able to change a situation, we are challenged to change ourselves.", author: "Viktor E. Frankl", source: "Man's Search for Meaning"),
        Quote(text: "If there's a book that you want to read, but it hasn't been written yet, then you must write it.", author: "Toni Morrison", source: "Speech, 1981"),
        Quote(text: "This is water.", author: "David Foster Wallace", source: "Kenyon College address, 2005"),
        Quote(text: "We tell ourselves stories in order to live.", author: "Joan Didion", source: "The White Album"),
        Quote(text: "Life can only be understood backwards; but it must be lived forwards.", author: "Søren Kierkegaard", source: "Journals, 1843"),
        Quote(text: "In the beginner's mind there are many possibilities, but in the expert's there are few.", author: "Shunryu Suzuki", source: "Zen Mind, Beginner's Mind"),
        Quote(text: "There is no greater agony than bearing an untold story inside you.", author: "Maya Angelou", source: "I Know Why the Caged Bird Sings"),
        Quote(text: "Your silence will not protect you.", author: "Audre Lorde", source: "The Transformation of Silence into Language and Action"),
        Quote(text: "First forget inspiration. Habit is more dependable.", author: "Octavia E. Butler", source: "Furor Scribendi"),
        Quote(text: "All that you touch you change. All that you change changes you.", author: "Octavia E. Butler", source: "Parable of the Sower"),
        Quote(text: "Only those who will risk going too far can possibly find out how far one can go.", author: "T. S. Eliot", source: "Preface to Transit of Venus, 1931"),
        Quote(text: "Try again. Fail again. Fail better.", author: "Samuel Beckett", source: "Worstward Ho"),
        Quote(text: "The good life is one inspired by love and guided by knowledge.", author: "Bertrand Russell", source: "What I Believe"),
        Quote(text: "The first principle is that you must not fool yourself, and you are the easiest person to fool.", author: "Richard Feynman", source: "Cargo Cult Science, 1974"),
        Quote(text: "It may be that when we no longer know what to do we have come to our real work.", author: "Wendell Berry", source: "The Real Work"),
        Quote(text: "Be joyful though you have considered all the facts.", author: "Wendell Berry", source: "Manifesto: The Mad Farmer Liberation Front"),
        Quote(text: "Practice resurrection.", author: "Wendell Berry", source: "Manifesto: The Mad Farmer Liberation Front"),
        Quote(text: "We must risk delight.", author: "Jack Gilbert", source: "A Brief for the Defense"),
        Quote(text: "What is essential is invisible to the eye.", author: "Saint-Exupéry", source: "The Little Prince"),
        Quote(text: "Perfection is achieved, not when there is nothing more to add, but when there is nothing left to take away.", author: "Saint-Exupéry", source: "Wind, Sand and Stars"),
        Quote(text: "Less, but better.", author: "Dieter Rams", source: "Less but Better"),
        Quote(text: "Traveler, there is no road; the road is made by walking.", author: "Antonio Machado", source: "Campos de Castilla"),
        Quote(text: "As you set out for Ithaka, hope your road is a long one.", author: "C. P. Cavafy", source: "Ithaka"),
        Quote(text: "To be great, be whole.", author: "Fernando Pessoa", source: "Odes of Ricardo Reis"),
        Quote(text: "I hope for nothing. I fear nothing. I am free.", author: "Nikos Kazantzakis", source: "His epitaph"),
        Quote(text: "Life shrinks or expands in proportion to one's courage.", author: "Anaïs Nin", source: "The Diary of Anaïs Nin, Vol. 3"),
        Quote(text: "What matters most is how well you walk through the fire.", author: "Charles Bukowski", source: "how is your heart?"),
    ]

    static let period: TimeInterval = 6 * 3600

    /// Same quote for the whole 6-hour slot; every quote of the pool appears once per cycle,
    /// in an order reshuffled each cycle. `large` uses its own pool and offset.
    static func quote(at date: Date = Date(), large: Bool) -> Quote {
        let pool = large ? all.filter { !$0.isShort || $0.text.count > 40 } : all.filter(\.isShort)
        let slot = Int(date.timeIntervalSince1970 / period) + (large ? 7 : 0)
        let cycle = slot / pool.count
        var rng = SplitMix64(seed: UInt64(cycle))
        let order = Array(pool.indices).shuffled(using: &rng)
        return pool[order[slot % pool.count]]
    }

    #if DEBUG
    static let selfCheck: Void = {
        let small = all.filter(\.isShort)
        let start = Date(timeIntervalSince1970: Double(small.count * 100) * period)
        let seen = Set((0..<small.count).map { quote(at: start.addingTimeInterval(Double($0) * period), large: false).text })
        assert(seen.count == small.count, "each short quote once per cycle")
        assert(quote(at: start, large: false) == quote(at: start.addingTimeInterval(period - 1), large: false), "stable within a slot")
    }()
    #endif
}

/// Tiny deterministic generator so the shuffle is the same on every launch.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Views

struct QuoteContent: View {
    let quote: Quote
    let large: Bool
    var hovering = false

    static let champagne = Color(red: 0.86, green: 0.76, blue: 0.56)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\u{201C}")
                .font(.system(size: large ? 44 : 34, weight: .ultraLight, design: .serif))
                .foregroundStyle(Self.champagne.opacity(0.75))
                .frame(height: large ? 22 : 16, alignment: .top)
                .padding(.bottom, large ? 8 : 6) // keep the mark clear of long, multi-line text

            Text(quote.text)
                .font(.system(size: large ? 17 : 13.5, weight: .light, design: .serif))
                .lineSpacing(large ? 3 : 1.5)
                .foregroundStyle(.white.opacity(0.94))
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .id(quote.text)
                .transition(.opacity)

            HStack(spacing: 7) {
                Rectangle().fill(Self.champagne.opacity(0.6)).frame(width: large ? 18 : 12, height: 0.5)
                Text(hovering ? quote.source : quote.author.uppercased())
                    .font(.system(size: large ? 9.5 : 8.5, weight: hovering ? .regular : .medium, design: hovering ? .serif : .default))
                    .italic(hovering)
                    .kerning(hovering ? 0 : (large ? 1.6 : quote.author.count > 20 ? 0.2 : quote.author.count > 15 ? 0.7 : 1.6)) // long names fit the small card
                    .foregroundStyle(Self.champagne)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, large ? 10 : 8)
        }
        .padding(.horizontal, large ? 20 : 14)
        .padding(.vertical, large ? 14 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // warm, barely-there light from the top-left corner
            RadialGradient(colors: [Self.champagne.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: large ? 260 : 150)
        }
        .modifier(WidgetCard(highlighted: hovering))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(quote.text) — \(quote.author), \(quote.source)")
    }
}

// MARK: - Live

/// Recomputes on appear (notch open) and when the slot rolls over while visible.
struct QuoteWidget: View {
    let large: Bool
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            QuoteContent(quote: QuoteLibrary.quote(at: context.date, large: large), large: large, hovering: hovering)
                .animation(.easeInOut(duration: 1.2), value: QuoteLibrary.quote(at: context.date, large: large))
        }
        .animation(.smooth(duration: 0.3), value: hovering)
        .onHover { hovering = $0 }
        .onAppear {
            #if DEBUG
            _ = QuoteLibrary.selfCheck
            #endif
        }
    }
}
