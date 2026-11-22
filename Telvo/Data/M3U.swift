import Foundation

let noGroup = "Sem grupo"

struct M3U {
    let channels: [Channel]
    let epgUrl: String?
}

private let attrRegex = try! NSRegularExpression(pattern: #"([\w-]+)="([^"]*)""#)
private let episodeRegex = try! NSRegularExpression(pattern: #"\bS\d{1,2}\s?E\d{1,3}\b"#, options: .caseInsensitive)
private let vodExtensions: Set<String> = ["mp4", "mkv", "avi", "mov", "m4v"]

private func attributeMatches(_ line: String) -> [(key: String, value: String, end: String.Index)] {
    let ns = line as NSString
    return attrRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { m in
        guard let range = Range(m.range, in: line) else { return nil }
        return (ns.substring(with: m.range(at: 1)).lowercased(), ns.substring(with: m.range(at: 2)), range.upperBound)
    }
}

private func attributes(_ line: String) -> [String: String] {
    var out: [String: String] = [:]
    for m in attributeMatches(line) where out[m.key] == nil { out[m.key] = m.value }
    return out
}

private func nonBlank(_ s: String?) -> String? {
    guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    return s
}

func parseM3U(_ text: String) -> M3U {
    var channels: [Channel] = []
    var epgUrl: String?
    var info: String?
    var extGroup: String?
    text.enumerateLines { raw, _ in
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = line.uppercased()
        if line.isEmpty { return }
        if upper.hasPrefix("#EXTM3U") {
            let attrs = attributes(line)
            // Pode vir mais de uma URL separada por vírgula; usamos a primeira.
            epgUrl = nonBlank((attrs["url-tvg"] ?? attrs["x-tvg-url"])?
                .split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) })
        } else if upper.hasPrefix("#EXTINF") {
            info = line
            extGroup = nil
        } else if upper.hasPrefix("#EXTGRP:") {
            extGroup = line.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
        } else if line.hasPrefix("#") {
            return
        } else {
            channels.append(toChannel(info: info, extGroup: extGroup, url: line))
            info = nil
            extGroup = nil
        }
    }
    return M3U(channels: channels, epgUrl: epgUrl)
}

private func toChannel(info: String?, extGroup: String?, url: String) -> Channel {
    guard let info else { return Channel(name: url, url: url, group: extGroup ?? noGroup) }
    let matches = attributeMatches(info)
    var attrs: [String: String] = [:]
    for m in matches where attrs[m.key] == nil { attrs[m.key] = m.value }
    // O nome vem depois da primeira vírgula que sucede os atributos.
    let tail = info[(matches.last?.end ?? info.startIndex)...]
    var name = tail.firstIndex(of: ",").map { String(tail[tail.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
    if name.isEmpty { name = attrs["tvg-name"] ?? "" }
    if name.isEmpty { name = url }
    return Channel(
        name: name,
        url: url,
        group: nonBlank(attrs["group-title"]) ?? extGroup ?? noGroup,
        logo: nonBlank(attrs["tvg-logo"]),
        tvgId: nonBlank(attrs["tvg-id"]),
        tvgName: nonBlank(attrs["tvg-name"]),
        kind: kindOf(url: url, name: name)
    )
}

// Servidores Xtream usam /movie/ e /series/ na URL; nas outras listas, a extensão
// de arquivo indica VOD e o padrão S01E02 no nome indica episódio.
private func kindOf(url: String, name: String) -> Kind {
    let path = (url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url).lowercased()
    if path.contains("/series/") { return .series }
    if path.contains("/movie/") { return .movie }
    let ext = path.split(separator: ".").last.map(String.init) ?? ""
    guard path.contains("."), vodExtensions.contains(ext) else { return .live }
    let range = NSRange(location: 0, length: (name as NSString).length)
    return episodeRegex.firstMatch(in: name, range: range) != nil ? .series : .movie
}
