import AppIntents
import Foundation
import SwiftUI
import WidgetKit

/// Widget della schermata Home e della schermata di blocco.
///
/// Non decifra nulla: legge dall'App Group i dati preparati dall'app
/// (HomeWidgetService in Flutter, tramite il plugin home_widget).
/// - `tuyjo_widget`: JSON con i todo, ognuno con la finestra di visibilità
///   (`start`..`end`, millisecondi) e le etichette di data già pronte per giorno.
/// - `tuyjo_unread`: numero dei messaggi non letti, scritto anche dalla
///   Notification Service Extension quando arriva un push con l'app chiusa.
///
/// Priorità: todo visibili adesso, poi numero dei non letti, poi "tutto letto".
/// La timeline contiene un'entrata per ogni momento in cui un todo compare o
/// scade e per ogni mezzanotte, così il widget resta giusto con l'app chiusa.

let tuyjoAppGroupId = "group.com.privatemessaging.tuyjo"

// MARK: - Dati

struct WidgetTodo {
    let text: String
    let due: Date
    let start: Date
    let end: Date
    let alert: String?
    let label: String
    let labels: [String: String]

    func label(at date: Date) -> String {
        labels[WidgetData.dayKey(date)] ?? label
    }
}

struct WidgetData {
    var todos: [WidgetTodo] = []
    var unread: Int = 0
    var strings: [String: String] = [:]

    func visibleTodos(at date: Date) -> [WidgetTodo] {
        todos.filter { $0.start <= date && date < $0.end }.sorted { $0.due < $1.due }
    }

    func string(_ key: String, _ fallback: String) -> String {
        strings[key] ?? fallback
    }

    var unreadText: String {
        if unread == 1 { return string("unreadOne", "1 new message") }
        return string("unreadOther", "%d new messages").replacingOccurrences(of: "%d", with: String(unread))
    }

    /// Momenti in cui il contenuto cambia: un todo compare o scade, o arriva
    /// la mezzanotte ("Domani" diventa "Oggi").
    func transitions(after date: Date, until limit: Date) -> [Date] {
        var result = Set<Date>()
        for todo in todos {
            if todo.start > date && todo.start < limit { result.insert(todo.start) }
            if todo.end > date && todo.end < limit { result.insert(todo.end) }
        }
        if !todos.isEmpty {
            let calendar = Calendar.current
            var midnight = calendar.startOfDay(for: date)
            while true {
                guard let next = calendar.date(byAdding: .day, value: 1, to: midnight) else { break }
                midnight = next
                if midnight >= limit { break }
                result.insert(midnight)
            }
        }
        return result.sorted()
    }

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func load() -> WidgetData {
        var data = WidgetData()
        let defaults = UserDefaults(suiteName: tuyjoAppGroupId)

        if let raw = defaults?.string(forKey: "tuyjo_unread"), let count = Int(raw) {
            data.unread = count
        } else if let count = defaults?.object(forKey: "tuyjo_unread") as? Int {
            data.unread = count
        }

        guard let json = defaults?.string(forKey: "tuyjo_widget"),
              let bytes = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        else { return data }

        data.strings = root["strings"] as? [String: String] ?? [:]
        for item in root["todos"] as? [[String: Any]] ?? [] {
            guard let due = (item["due"] as? NSNumber)?.doubleValue,
                  let start = (item["start"] as? NSNumber)?.doubleValue,
                  let end = (item["end"] as? NSNumber)?.doubleValue
            else { continue }
            data.todos.append(WidgetTodo(
                text: item["text"] as? String ?? "",
                due: Date(timeIntervalSince1970: due / 1000),
                start: Date(timeIntervalSince1970: start / 1000),
                end: Date(timeIntervalSince1970: end / 1000),
                alert: item["alert"] as? String,
                label: item["label"] as? String ?? "",
                labels: item["labels"] as? [String: String] ?? [:]
            ))
        }
        return data
    }

    /// Esempio per la galleria dei widget.
    static var sample: WidgetData {
        let now = Date()
        return WidgetData(
            todos: [WidgetTodo(
                text: "Prenotare il ristorante",
                due: now.addingTimeInterval(86_400),
                start: now.addingTimeInterval(-3_600),
                end: now.addingTimeInterval(86_400),
                alert: nil,
                label: "20:00",
                labels: [:]
            )],
            unread: 2,
            strings: [:]
        )
    }
}

// MARK: - Timeline

struct TuyJoEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct TuyJoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TuyJoEntry {
        TuyJoEntry(date: Date(), data: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TuyJoEntry) -> Void) {
        completion(TuyJoEntry(date: Date(), data: context.isPreview ? .sample : .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TuyJoEntry>) -> Void) {
        let now = Date()
        let data = WidgetData.load()
        let changes = data.transitions(after: now, until: now.addingTimeInterval(7 * 86_400))
        let entries = ([now] + changes.prefix(60)).map { TuyJoEntry(date: $0, data: data) }

        // Se nulla cambierà da solo, riprova il giorno dopo; l'app e il push
        // chiedono comunque un ricaricamento quando i dati cambiano.
        let policy: TimelineReloadPolicy
        if changes.isEmpty {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
            policy = .after(tomorrow ?? now.addingTimeInterval(86_400))
        } else {
            policy = .atEnd
        }
        completion(Timeline(entries: entries, policy: policy))
    }
}

// MARK: - Aspetto

private let tealLight = Color(red: 0x3B / 255.0, green: 0xA8 / 255.0, blue: 0xB0 / 255.0)
private let tealDark = Color(red: 0x14 / 255.0, green: 0x5A / 255.0, blue: 0x60 / 255.0)
private let badgeRed = Color(red: 1.0, green: 0x5B / 255.0, blue: 0x4F / 255.0)
private let tealGradient = LinearGradient(colors: [tealLight, tealDark], startPoint: .topLeading, endPoint: .bottomTrailing)

private let callURL = URL(string: "tuyjo://call")!
private let openURL = URL(string: "tuyjo://open")!

extension View {
    /// Sfondo del widget: containerBackground da iOS 17 (che aggiunge da sé i
    /// margini), padding e background prima.
    @ViewBuilder
    func tuyjoBackground<Background: View>(_ background: Background, padding: CGFloat) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) { background }
        } else {
            self.padding(padding).background(background)
        }
    }
}

struct CallCircle: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Image(systemName: "phone.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(tealDark)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
    }
}

struct Header: View {
    let icon: String
    let title: String
    let badge: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(title).font(.system(size: 11, weight: .bold)).lineLimit(1)
            Spacer(minLength: 0)
            if badge > 0 {
                Text(badge > 99 ? "99+" : String(badge))
                    .font(.system(size: 11, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(badgeRed))
            }
        }
        .opacity(0.95)
    }
}

struct TodoDateLine: View {
    let todo: WidgetTodo
    let date: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar").font(.system(size: 11))
            Text(todo.label(at: date)).font(.system(size: 12)).lineLimit(1)
            if let alert = todo.alert {
                Text(alert)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.22)))
            }
        }
        .opacity(0.92)
    }
}

/// Contenuto comune: todo, oppure numero dei non letti, oppure "tutto letto".
struct MainContent: View {
    let entry: TuyJoEntry
    let titleLines: Int
    let maxRows: Int

    var body: some View {
        let data = entry.data
        let todos = data.visibleTodos(at: entry.date)

        VStack(alignment: .leading, spacing: 4) {
            if let first = todos.first {
                Header(icon: "calendar", title: data.string("todo", "To do"), badge: data.unread)
                if todos.count == 1 || maxRows <= 1 {
                    Text(first.text)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(titleLines)
                        .padding(.top, 4)
                    TodoDateLine(todo: first, date: entry.date)
                } else {
                    let shown = todos.count > maxRows ? maxRows - 1 : todos.count
                    ForEach(0..<shown, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(todos[index].label(at: entry.date))
                                .font(.system(size: 11))
                                .opacity(0.85)
                                .lineLimit(1)
                                .frame(width: 84, alignment: .leading)
                            Text(todos[index].text)
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                        }
                        .padding(.top, index == 0 ? 4 : 0)
                    }
                    if todos.count > shown {
                        Text("+\(todos.count - shown)")
                            .font(.system(size: 12, weight: .bold))
                            .opacity(0.85)
                            .padding(.leading, 92)
                    }
                }
            } else if data.unread > 0 {
                Header(icon: "bubble.left.fill", title: data.string("partner", "My love"), badge: 0)
                Text(data.unreadText)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(3)
                    .padding(.top, 4)
            } else {
                Header(icon: "heart.fill", title: data.string("partner", "My love"), badge: 0)
                Text(data.string("allRead", "All caught up"))
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(0.9)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SmallWidgetView: View {
    let entry: TuyJoEntry

    var body: some View {
        let more = entry.data.visibleTodos(at: entry.date).count - 1
        ZStack(alignment: .bottomTrailing) {
            MainContent(entry: entry, titleLines: 3, maxRows: 1)
            if more > 0 {
                Text("+\(more)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(tealDark)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.95)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.bottom, 8)
            }
            smallCallButton
        }
    }

    /// Nel formato piccolo un tasto separato funziona solo da iOS 17
    /// (AppIntent). Prima tutto il widget è un unico tocco che apre l'app.
    @ViewBuilder
    private var smallCallButton: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: CallPartnerIntent()) { CallCircle(size: 40) }
                .buttonStyle(.plain)
        } else {
            CallCircle(size: 40)
        }
    }
}

struct MediumWidgetView: View {
    let entry: TuyJoEntry

    var body: some View {
        HStack(spacing: 12) {
            MainContent(entry: entry, titleLines: 2, maxRows: 3)
            Link(destination: callURL) { CallCircle(size: 50) }
        }
    }
}

@available(iOSApplicationExtension 16.0, *)
struct LockScreenWidgetView: View {
    let entry: TuyJoEntry

    var body: some View {
        let data = entry.data
        let todos = data.visibleTodos(at: entry.date)
        VStack(alignment: .leading, spacing: 1) {
            if let first = todos.first {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(todos.count > 1 ? "\(first.label(at: entry.date)) · +\(todos.count - 1)" : first.label(at: entry.date))
                }
                .font(.system(size: 13, weight: .bold))
                Text(first.text).lineLimit(2).privacySensitive()
            } else if data.unread > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.fill")
                    Text(data.string("partner", "My love"))
                }
                .font(.system(size: 13, weight: .bold))
                Text(data.unreadText)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                    Text("TuyJo")
                }
                .font(.system(size: 13, weight: .bold))
                Text(data.string("allRead", "All caught up"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TuyJoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TuyJoEntry

    var body: some View {
        content.widgetURL(openURL)
    }

    private var isLockScreen: Bool {
        if #available(iOSApplicationExtension 16.0, *) {
            return family == .accessoryRectangular
        }
        return false
    }

    @ViewBuilder
    private var content: some View {
        if isLockScreen {
            if #available(iOSApplicationExtension 16.0, *) {
                LockScreenWidgetView(entry: entry)
                    .tuyjoBackground(Color.clear, padding: 0)
            }
        } else if family == .systemSmall {
            SmallWidgetView(entry: entry)
                .foregroundColor(.white)
                .tuyjoBackground(tealGradient, padding: 14)
        } else {
            MediumWidgetView(entry: entry)
                .foregroundColor(.white)
                .tuyjoBackground(tealGradient, padding: 16)
        }
    }
}

// MARK: - Widget

struct TuyJoWidget: Widget {
    let kind = "TuyJoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TuyJoProvider()) { entry in
            TuyJoWidgetView(entry: entry)
        }
        .configurationDisplayName("TuyJo")
        .description(Self.localizedDescription)
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        if #available(iOSApplicationExtension 16.0, *) {
            return [.systemSmall, .systemMedium, .accessoryRectangular]
        }
        return [.systemSmall, .systemMedium]
    }

    private static var localizedDescription: String {
        let language = String(Locale.preferredLanguages.first?.prefix(2) ?? "en")
        switch language {
        case "it": return "Prossimo todo, messaggi nuovi e un tasto per chiamare il tuo amore"
        case "es": return "Próxima tarea, mensajes nuevos y un botón para llamar a tu amor"
        case "ca": return "Propera tasca, missatges nous i un botó per trucar al teu amor"
        default: return "Next to-do, new messages and a button to call your love"
        }
    }
}

@main
struct TuyJoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TuyJoWidget()
    }
}
