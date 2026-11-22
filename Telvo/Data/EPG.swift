import Foundation

struct Epg {
    let byChannel: [String: [Programme]]
    let idByName: [String: String]

    static let empty = Epg(byChannel: [:], idByName: [:])
    var isEmpty: Bool { byChannel.isEmpty }

    // Casa pelo tvg-id; sem ele, pelo nome normalizado do canal.
    func programmes(_ channel: Channel) -> [Programme] {
        if let id = channel.tvgId?.lowercased(), let list = byChannel[id] { return list }
        let id = channel.tvgName.flatMap { idByName[normalize($0)] } ?? idByName[normalize(channel.name)]
        return id.flatMap { byChannel[$0] } ?? []
    }
}

// Formato XMLTV: "20260419083000 +0000"; sem fuso, assume UTC.
private func parseXmltvTime(_ value: String?) -> Int64? {
    guard let text = value?.trimmingCharacters(in: .whitespaces), text.count >= 8 else { return nil }
    let digits = String(text.prefix(14)).padding(toLength: 14, withPad: "0", startingAt: 0)
    var c = DateComponents()
    func part(_ from: Int, _ len: Int) -> Int? {
        let s = digits.index(digits.startIndex, offsetBy: from)
        return Int(digits[s..<digits.index(s, offsetBy: len)])
    }
    guard let y = part(0, 4), let mo = part(4, 2), let d = part(6, 2),
          let h = part(8, 2), let mi = part(10, 2), let s = part(12, 2) else { return nil }
    (c.year, c.month, c.day, c.hour, c.minute, c.second) = (y, mo, d, h, mi, s)
    var offset = 0
    let zone = text.dropFirst(14).trimmingCharacters(in: .whitespaces)
    if zone.count >= 5, let sign = zone.first, sign == "+" || sign == "-",
       let hh = Int(zone.dropFirst().prefix(2)), let mm = Int(zone.dropFirst(3).prefix(2)) {
        offset = (hh * 3600 + mm * 60) * (sign == "-" ? -1 : 1)
    }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: offset)!
    guard let date = cal.date(from: c) else { return nil }
    return Int64(date.timeIntervalSince1970 * 1000)
}

// Lê o XMLTV em streaming e guarda só os canais da lista, de ontem até daqui a 7 dias.
final class XmltvParser: NSObject, XMLParserDelegate {
    private let wantedIds: Set<String>
    private let wantedNames: Set<String>
    private let from: Int64
    private let to: Int64

    private var keep = Set<String>()
    private var idByName: [String: String] = [:]
    private var byChannel: [String: [Programme]] = [:]

    private var channelId: String?
    private var names: [String] = []
    private var programme: (id: String, start: Int64, stop: Int64)?
    private var title = ""
    private var desc: String?
    private var text = ""
    private var capturing = false

    init(channels: [Channel]) {
        wantedIds = Set(channels.compactMap { $0.tvgId?.lowercased() })
        wantedNames = Set(channels.flatMap { [$0.tvgName, $0.name].compactMap { $0 }.map(normalize) })
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        from = Int64(cal.date(byAdding: .day, value: -1, to: today)!.timeIntervalSince1970 * 1000)
        to = Int64(cal.date(byAdding: .day, value: 8, to: today)!.timeIntervalSince1970 * 1000)
    }

    func parse(_ data: Data) -> Epg {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return Epg(byChannel: byChannel.mapValues { $0.sorted { $0.start < $1.start } }, idByName: idByName)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "channel":
            channelId = attributes["id"]?.lowercased()
            names = []
        case "display-name" where channelId != nil:
            text = ""; capturing = true
        case "programme":
            guard let id = attributes["channel"]?.lowercased(), keep.contains(id),
                  let start = parseXmltvTime(attributes["start"]) else { programme = nil; return }
            let stop = parseXmltvTime(attributes["stop"]) ?? start + 30 * 60_000
            guard stop >= from, start <= to else { programme = nil; return }
            programme = (id, start, stop)
            title = ""; desc = nil
        case "title", "desc":
            if programme != nil { text = ""; capturing = true }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "display-name" where channelId != nil:
            names.append(normalize(text)); capturing = false
        case "channel":
            if let id = channelId {
                let matched = names.filter { wantedNames.contains($0) }
                for n in matched where idByName[n] == nil { idByName[n] = id }
                if wantedIds.contains(id) || !matched.isEmpty { keep.insert(id) }
            }
            channelId = nil
        case "title" where programme != nil:
            if title.isEmpty { title = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            capturing = false
        case "desc" where programme != nil:
            if desc == nil { desc = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            capturing = false
        case "programme":
            if let p = programme {
                byChannel[p.id, default: []].append(Programme(
                    start: p.start, stop: p.stop,
                    title: title.isEmpty ? "Sem título" : title,
                    description: (desc?.isEmpty ?? true) ? nil : desc))
            }
            programme = nil
        default: break
        }
    }
}
