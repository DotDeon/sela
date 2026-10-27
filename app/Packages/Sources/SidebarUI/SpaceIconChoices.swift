import Foundation

/// The two sets of icons a space can choose from.
public enum SpaceIconKind: Sendable {
    case symbols
    case emoji
}

/// SF Symbols offered for spaces, each with words that find it. All exist on macOS 15.
let spaceSymbolChoices: [(name: String, keywords: String)] = [
    ("house.fill", "home"), ("briefcase.fill", "work job office"), ("building.2.fill", "office company city"),
    ("person.fill", "personal me"), ("person.2.fill", "people team friends"), ("heart.fill", "love favourite"),
    ("star.fill", "favourite"), ("bolt.fill", "fast energy power"), ("flame.fill", "fire hot"),
    ("sparkles", "magic new ideas"), ("lightbulb.fill", "idea think"), ("brain.head.profile", "mind learn think"),
    ("book.fill", "read study"), ("books.vertical.fill", "library read study"), ("graduationcap.fill", "school study university learn"),
    ("pencil", "write edit draft"), ("doc.text.fill", "document notes"), ("folder.fill", "files"),
    ("tray.full.fill", "inbox mail"), ("envelope.fill", "mail email inbox"), ("paperplane.fill", "send travel"),
    ("bubble.left.and.bubble.right.fill", "chat messages talk"), ("phone.fill", "call"), ("video.fill", "call meeting camera"),
    ("calendar", "date schedule plan"), ("clock.fill", "time"), ("checkmark.circle.fill", "tasks todo done"),
    ("list.bullet", "list tasks todo"), ("flag.fill", "goal"), ("bookmark.fill", "save read later"),
    ("chevron.left.forwardslash.chevron.right", "code dev programming"), ("terminal.fill", "code dev shell"), ("hammer.fill", "build tools make"),
    ("wrench.and.screwdriver.fill", "tools fix settings"), ("gearshape.fill", "settings"), ("cpu.fill", "computer tech"),
    ("server.rack", "server dev ops"), ("cloud.fill", "cloud weather"), ("globe", "web world internet"),
    ("network", "web connect"), ("lock.fill", "private secure"), ("key.fill", "password secure"),
    ("cart.fill", "shop shopping buy"), ("bag.fill", "shop shopping"), ("creditcard.fill", "money bank pay"),
    ("banknote.fill", "money finance cash"), ("chart.line.uptrend.xyaxis", "finance stocks growth"), ("chart.bar.fill", "stats data analytics"),
    ("dollarsign.circle.fill", "money finance"), ("music.note", "music song"), ("headphones", "music listen podcast"),
    ("mic.fill", "podcast record"), ("film.fill", "movies video watch"), ("tv.fill", "watch shows"),
    ("play.rectangle.fill", "video youtube watch"), ("gamecontroller.fill", "games play"), ("camera.fill", "photo"),
    ("photo.fill", "pictures images"), ("paintbrush.fill", "art design paint"), ("paintpalette.fill", "art design colour"),
    ("pencil.and.ruler.fill", "design draw"), ("scissors", "cut craft"), ("leaf.fill", "nature green plant"),
    ("tree.fill", "nature outdoors"), ("mountain.2.fill", "outdoors hike nature"), ("sun.max.fill", "sun summer weather"),
    ("moon.fill", "night sleep"), ("snowflake", "winter cold"), ("drop.fill", "water"),
    ("pawprint.fill", "pets dog cat animal"), ("fish.fill", "fish animal"), ("bird.fill", "bird animal"),
    ("airplane", "travel flight"), ("car.fill", "drive travel"), ("bicycle", "bike cycle sport"),
    ("figure.run", "run fitness sport exercise"), ("dumbbell.fill", "gym fitness exercise"), ("sportscourt.fill", "sport"),
    ("fork.knife", "food eat recipes"), ("cup.and.saucer.fill", "coffee tea cafe"), ("wineglass.fill", "wine drink"),
    ("birthday.cake.fill", "party birthday"), ("gift.fill", "present birthday"), ("cross.case.fill", "health medical"),
    ("heart.text.square.fill", "health"), ("pills.fill", "health medicine"), ("newspaper.fill", "news read"),
    ("magnifyingglass", "search research find"), ("map.fill", "maps travel"), ("mappin.and.ellipse", "place location"),
    ("tag.fill", "label"), ("archivebox.fill", "archive store"), ("shippingbox.fill", "package delivery"),
    ("puzzlepiece.fill", "puzzle extension"), ("atom", "science physics"), ("flask.fill", "science lab"),
    ("crown.fill", "king queen best"), ("trophy.fill", "win award"),
    ("circle.fill", "dot"), ("square.fill", "shape"), ("triangle.fill", "shape"), ("diamond.fill", "shape gem"),
    ("hexagon.fill", "shape"), ("seal.fill", "badge"),
]

/// Emoji offered for spaces. Their Unicode names find them, so "rocket" finds 🚀.
let spaceEmojiChoices: [String] = [
    "🏠", "💼", "🏢", "👤", "👥", "❤️", "⭐️", "⚡️", "🔥", "✨",
    "💡", "🧠", "📚", "🎓", "✏️", "📝", "📁", "📬", "✉️", "💬",
    "📞", "📅", "⏰", "✅", "🚩", "🔖", "💻", "🛠️", "⚙️", "🌐",
    "🔒", "🔑", "🛒", "🛍️", "💳", "💰", "📈", "📊", "🎵", "🎧",
    "🎙️", "🎬", "📺", "🎮", "📷", "🖼️", "🎨", "✂️", "🌿", "🌳",
    "⛰️", "☀️", "🌙", "❄️", "💧", "🐶", "🐱", "🐟", "🐦", "✈️",
    "🚗", "🚲", "🏃", "🏋️", "⚽️", "🍴", "☕️", "🍷", "🎂", "🎁",
    "🩺", "💊", "📰", "🔍", "🗺️", "📍", "🏷️", "📦", "🧩", "⚛️",
    "🧪", "👑", "🏆", "🚀", "🌈", "🍀", "🎯", "🧘", "🏝️", "🎉",
]

/// The icons to show for `query`, in order. Every word must be found in a symbol's name or words, or in an
/// emoji's Unicode name. A query that is itself a symbol name, checked by `isSymbol`, or a single emoji comes
/// first, so any symbol or emoji can be chosen even when it isn't in the list.
public func spaceIconChoices(_ kind: SpaceIconKind, matching query: String, isSymbol: (String) -> Bool) -> [String] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let words = trimmed.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    let matches = { (text: String) in words.allSatisfy { text.contains($0) } }
    var results: [String]
    var exact: String?
    switch kind {
    case .symbols:
        results = spaceSymbolChoices.filter { matches("\($0.name) \($0.keywords)") }.map(\.name)
        if words.count == 1, isSymbol(trimmed) { exact = trimmed }
    case .emoji:
        results = spaceEmojiChoices.filter { matches(emojiName($0)) }
        if trimmed.count == 1, isEmoji(trimmed) { exact = trimmed }
    }
    if let exact {
        results.removeAll { $0 == exact }
        results.insert(exact, at: 0)
    }
    return results
}

/// True for a character drawn as an emoji, such as 🚀, or ❤️ with its emoji variation.
private func isEmoji(_ character: String) -> Bool {
    guard let first = character.unicodeScalars.first, first.properties.isEmoji else { return false }
    return first.properties.isEmojiPresentation || character.unicodeScalars.count > 1
}

/// Everyday words for emoji whose Unicode names don't use them, such as "coffee" for ☕️ (HOT BEVERAGE).
private let emojiKeywords: [String: String] = [
    "🏠": "home", "💼": "work job", "🏢": "work office company", "👤": "personal me", "👥": "people team friends",
    "❤️": "love", "⚡️": "fast energy", "🔥": "hot", "💡": "idea", "🧠": "mind think learn", "📚": "read study",
    "🎓": "school study university", "📝": "notes write", "📬": "inbox", "✉️": "mail email", "💬": "chat messages",
    "📅": "date schedule", "✅": "tasks todo done", "💻": "code dev computer work", "🛠️": "tools build fix",
    "⚙️": "settings", "🌐": "web internet world", "🔒": "private secure", "🛒": "shop shopping", "🛍️": "shop shopping",
    "💳": "money bank pay", "💰": "money finance", "📈": "finance stocks growth", "📊": "stats data", "🎵": "music song",
    "🎧": "music listen podcast", "🎙️": "podcast", "🎬": "movies film video", "📺": "watch shows", "🎮": "games play",
    "📷": "photo", "🖼️": "pictures images art", "🎨": "art design", "🌿": "nature plant green", "⛰️": "outdoors hike",
    "☀️": "summer weather", "🐶": "pets dog", "🐱": "pets cat", "✈️": "travel flight", "🚗": "drive travel",
    "🚲": "bike cycle", "🏃": "run fitness sport", "🏋️": "gym fitness", "🍴": "food eat recipes", "☕️": "coffee tea cafe",
    "🍷": "wine drink", "🎂": "birthday party", "🎁": "present birthday", "🩺": "health medical doctor", "💊": "health medicine",
    "📰": "news", "🔍": "search research", "🗺️": "maps travel", "📍": "place location", "📦": "package delivery",
    "⚛️": "science react", "🧪": "science lab", "🏆": "win award", "🚀": "launch startup", "🎯": "goal focus",
    "🧘": "calm meditate yoga", "🏝️": "holiday vacation beach", "🎉": "party celebrate",
]

private func emojiName(_ emoji: String) -> String {
    let name = emoji.unicodeScalars.compactMap(\.properties.name).joined(separator: " ")
    return "\(name) \(emojiKeywords[emoji] ?? "")".lowercased()
}
