import SwiftUI
import AppKit
import EventKit

// MARK: - Weather (open-meteo, no API key)

struct WeatherInfo {
    let temp: String
    let symbol: String
    let label: String
    let city: String
}

final class WeatherService {
    static let shared = WeatherService()
    private var cached: (Date, WeatherInfo)?

    func fetch(completion: @escaping (WeatherInfo?) -> Void) {
        if let cached, Date().timeIntervalSince(cached.0) < 1800 {
            completion(cached.1)
            return
        }
        // Approximate location from IP, then current conditions.
        URLSession.shared.dataTask(with: URL(string: "https://ipapi.co/json/")!) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = obj["latitude"] as? Double,
                  let lon = obj["longitude"] as? Double
            else {
                completion(nil)
                return
            }
            let city = obj["city"] as? String ?? ""
            let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code")!
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let current = obj["current"] as? [String: Any],
                      let temp = current["temperature_2m"] as? Double
                else {
                    completion(nil)
                    return
                }
                let code = current["weather_code"] as? Int ?? 0
                let (symbol, label) = Self.describe(code)
                let info = WeatherInfo(
                    temp: "\(Int(temp.rounded()))°",
                    symbol: symbol,
                    label: label,
                    city: city
                )
                self.cached = (Date(), info)
                completion(info)
            }.resume()
        }.resume()
    }

    private static func describe(_ code: Int) -> (String, String) {
        switch code {
        case 0: return ("sun.max.fill", "Clear")
        case 1...3: return ("cloud.sun.fill", "Partly cloudy")
        case 45, 48: return ("cloud.fog.fill", "Foggy")
        case 51...67: return ("cloud.rain.fill", "Rain")
        case 71...77: return ("cloud.snow.fill", "Snow")
        case 80...82: return ("cloud.heavyrain.fill", "Showers")
        case 95...99: return ("cloud.bolt.rain.fill", "Storm")
        default: return ("cloud.fill", "Cloudy")
        }
    }
}

// MARK: - Widget data

final class WidgetDataStore: ObservableObject {
    static let shared = WidgetDataStore()

    @Published var nextEvent: EKEvent?
    @Published var dueReminders: [EKReminder] = []
    @Published var weather: WeatherInfo?

    func refresh() {
        CalendarService.shared.requestAccessIfNeeded { [weak self] in
            DispatchQueue.main.async {
                self?.nextEvent = CalendarService.shared.upcomingEvents(limit: 1).first
            }
            CalendarService.shared.fetchDueReminders { reminders in
                DispatchQueue.main.async {
                    self?.dueReminders = reminders
                }
            }
        }
        WeatherService.shared.fetch { [weak self] info in
            DispatchQueue.main.async {
                self?.weather = info
            }
        }
    }
}

// MARK: - Widget bar (home state of the launcher)

struct WidgetCard: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    var action: (() -> Void)?

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { action?() }
    }
}

struct WidgetBar: View {
    @ObservedObject var data = WidgetDataStore.shared

    private var dayString: (String, String) {
        let df = DateFormatter()
        df.dateFormat = "EEEE"
        let weekday = df.string(from: Date())
        df.dateFormat = "d MMMM"
        return (weekday, df.string(from: Date()))
    }

    var body: some View {
        HStack(spacing: 8) {
            WidgetCard(
                symbol: "calendar",
                color: .red,
                title: dayString.0,
                subtitle: dayString.1,
                action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
            )

            WidgetCard(
                symbol: "clock.fill",
                color: Theme.blue,
                title: data.nextEvent?.title ?? "No meetings",
                subtitle: data.nextEvent.map { CalendarService.eventTimeString($0) } ?? "Schedule is clear",
                action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
            )

            WidgetCard(
                symbol: "checklist",
                color: .orange,
                title: data.dueReminders.isEmpty ? "All done" : "\(data.dueReminders.count) due",
                subtitle: data.dueReminders.first?.title ?? "No reminders due",
                action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app")) }
            )

            WidgetCard(
                symbol: data.weather?.symbol ?? "cloud.fill",
                color: .cyan,
                title: data.weather.map { "\($0.temp) \($0.label)" } ?? "Weather",
                subtitle: data.weather?.city ?? "Loading…",
                action: nil
            )
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

// MARK: - Notion search integration

enum NotionProvider {
    /// Async — mirrors FileProvider's pattern; results merged by the view model.
    static func search(_ q: String, completion: @escaping ([SearchResult]) -> Void) {
        guard NotionService.token != nil else {
            completion([])
            return
        }
        NotionService.search(q) { pages in
            let results = pages.enumerated().map { i, page in
                SearchResult(
                    id: "notion:\(page.url)",
                    kind: .notion,
                    title: page.title,
                    subtitle: page.isDatabase ? "Notion database" : "Notion page",
                    icon: nil,
                    symbolName: "n.square.fill",
                    score: 0.42 - Double(i) * 0.005,
                    action: {
                        if let url = URL(string: page.url) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
            completion(results)
        }
    }
}
