import AppKit

enum EmojiProvider {
    // (emoji, searchable keywords — first word is the display name)
    static let emojis: [(String, String)] = [
        ("😀", "grinning happy smile face"), ("😂", "joy laughing tears funny lol"),
        ("🤣", "rofl rolling laughing"), ("😊", "blush smile happy"),
        ("😍", "heart eyes love"), ("🥰", "love hearts adore"),
        ("😎", "cool sunglasses"), ("🤔", "thinking hmm"),
        ("😅", "sweat smile relief"), ("😭", "crying sob tears"),
        ("😢", "sad cry tear"), ("😡", "angry mad rage"),
        ("🥳", "party celebrate birthday"), ("😴", "sleep tired zzz"),
        ("🤯", "mind blown exploding head"), ("😱", "scream shocked fear"),
        ("🙄", "eye roll annoyed"), ("😬", "grimace awkward"),
        ("🤗", "hug warm"), ("🤫", "shush quiet secret"),
        ("😇", "angel innocent halo"), ("🤩", "star struck excited wow"),
        ("😋", "yum tasty delicious"), ("🫠", "melting"),
        ("👍", "thumbs up like yes approve"), ("👎", "thumbs down dislike no"),
        ("👋", "wave hello hi bye"), ("🙏", "pray thanks please namaste"),
        ("👏", "clap applause"), ("🙌", "raised hands celebration praise"),
        ("💪", "muscle strong flex"), ("🤝", "handshake deal agreement"),
        ("✌️", "peace victory"), ("🤞", "fingers crossed luck"),
        ("👀", "eyes look watching"), ("🧠", "brain smart"),
        ("❤️", "red heart love"), ("🧡", "orange heart"),
        ("💛", "yellow heart"), ("💚", "green heart"),
        ("💙", "blue heart"), ("💜", "purple heart"),
        ("🖤", "black heart"), ("💔", "broken heart sad"),
        ("💯", "hundred perfect score"), ("🔥", "fire hot lit"),
        ("✨", "sparkles magic shine"), ("⭐", "star favorite"),
        ("🌟", "glowing star"), ("💥", "boom collision explosion"),
        ("🎉", "party popper celebration congrats tada"), ("🎊", "confetti celebration"),
        ("🎂", "birthday cake"), ("🎁", "gift present"),
        ("🚀", "rocket launch ship fast startup"), ("✈️", "airplane travel flight"),
        ("🚗", "car drive"), ("🏠", "house home"),
        ("💰", "money bag rich"), ("💸", "money wings spend"),
        ("💡", "idea light bulb"), ("🔔", "bell notification"),
        ("📌", "pin location"), ("📎", "paperclip attach"),
        ("📝", "memo note write"), ("📚", "books study reading"),
        ("💻", "laptop computer code"), ("⌨️", "keyboard typing"),
        ("🖥️", "desktop computer monitor"), ("📱", "phone mobile iphone"),
        ("🎧", "headphones music"), ("🎵", "music note song"),
        ("🎮", "game controller videogame"), ("📷", "camera photo"),
        ("🎬", "clapper movie film"), ("⚡", "lightning zap fast power"),
        ("☀️", "sun sunny weather"), ("🌙", "moon night"),
        ("🌈", "rainbow"), ("☁️", "cloud weather"),
        ("🌧️", "rain weather"), ("❄️", "snow snowflake cold winter"),
        ("🌊", "wave ocean sea water"), ("🌸", "cherry blossom flower spring"),
        ("🌹", "rose flower"), ("🌲", "tree evergreen nature"),
        ("🍕", "pizza food"), ("🍔", "burger hamburger food"),
        ("🍟", "fries food"), ("🌮", "taco food"),
        ("🍣", "sushi food japan"), ("🍜", "noodles ramen food"),
        ("🍩", "donut doughnut sweet"), ("🍦", "ice cream sweet"),
        ("☕", "coffee tea hot drink"), ("🍺", "beer drink cheers"),
        ("🍷", "wine drink"), ("🥂", "champagne cheers toast"),
        ("🍎", "apple fruit red"), ("🍌", "banana fruit"),
        ("🍇", "grapes fruit"), ("🍉", "watermelon fruit"),
        ("⚽", "soccer football sport"), ("🏀", "basketball sport"),
        ("🏈", "american football sport"), ("🎾", "tennis sport"),
        ("🏏", "cricket sport bat"), ("🏆", "trophy winner champion"),
        ("🥇", "gold medal first winner"), ("🎯", "dart target bullseye goal"),
        ("🐶", "dog puppy pet"), ("🐱", "cat kitten pet"),
        ("🐼", "panda bear"), ("🦁", "lion"),
        ("🐯", "tiger"), ("🐵", "monkey"),
        ("🦄", "unicorn magic"), ("🐢", "turtle slow"),
        ("🦋", "butterfly"), ("🐝", "bee honey"),
        ("✅", "check mark done yes complete"), ("❌", "cross x no wrong"),
        ("⚠️", "warning caution alert"), ("❓", "question mark"),
        ("❗", "exclamation important"), ("♻️", "recycle"),
        ("🔒", "lock secure private"), ("🔓", "unlock open"),
        ("🔑", "key password"), ("⏰", "alarm clock time"),
        ("⌛", "hourglass time waiting"), ("📅", "calendar date schedule"),
        ("📈", "chart increasing growth up stocks"), ("📉", "chart decreasing down loss"),
        ("🇮🇳", "india flag"), ("🇺🇸", "usa america flag"),
        ("🌍", "earth globe world"), ("🗺️", "map world travel"),
    ]

    static func results(for q: String) -> [SearchResult] {
        let lq = q.lowercased().trimmingCharacters(in: .whitespaces)
        guard lq.count >= 2 else { return [] }

        var out: [SearchResult] = []
        for (char, keywords) in emojis {
            guard keywords.contains(lq) else { continue }
            let name = keywords.split(separator: " ").first.map(String.init) ?? char
            out.append(SearchResult(
                id: "emoji:\(char)",
                kind: .emoji,
                title: "\(char)  \(name.capitalized)",
                subtitle: SelectionService.accessibilityGranted ? "⏎ to paste" : "⏎ to copy",
                icon: nil,
                symbolName: "face.smiling",
                score: keywords.hasPrefix(lq) ? 0.78 : 0.62,
                action: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        SelectionService.paste(char)
                    }
                }
            ))
            if out.count >= 8 { break }
        }
        return out
    }
}
