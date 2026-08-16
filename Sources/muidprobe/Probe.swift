import Foundation
import MapKit
import CoreLocation

// Does MapKit hand a third-party app the same place identifier Apple Maps uses
// internally (the `muid`)? If it does, the guide-link pipeline is clean end to end.
// If it does not, we need another route to IDs.
//
// Ground truth below was captured from Apple Maps' own web client on 16 Aug 2026.
// Each guide link built from these muids populates correctly in Maps on iPhone.

struct Known {
    let query: String
    let muid: UInt64
    let lat: CLLocationDegrees
    let lon: CLLocationDegrees
}

let knowns: [Known] = [
    Known(query: "Dishoom Shoreditch",           muid: 4898268440419489333,  lat: 51.52450180053711, lon: -0.07686139643192291),
    Known(query: "Wright Brothers Borough Market", muid: 7304537147265648657, lat: 51.505615234375,   lon: -0.09155450016260147),
    Known(query: "Elliot's Borough Market",      muid: 10736127904580997346, lat: 51.50564956665039, lon: -0.09163080155849457),
    Known(query: "Arabica Borough Market",       muid: 5962421024212360822,  lat: 51.50577926635742, lon: -0.09137000143527985),
    Known(query: "Black & Blue Borough Market",  muid: 1403702173631356384,  lat: 51.50582504272461, lon: -0.09140729904174805),
]

// MARK: - Does this string hide the muid?

/// Scan raw bytes for an 8-byte window equal to `expected`, either endianness.
func scanFixed64(_ bytes: [UInt8], for expected: UInt64) -> String? {
    guard bytes.count >= 8 else { return nil }
    for i in 0...(bytes.count - 8) {
        var be: UInt64 = 0
        var le: UInt64 = 0
        for j in 0..<8 {
            be = (be << 8) | UInt64(bytes[i + j])
            le |= UInt64(bytes[i + j]) << UInt64(8 * j)
        }
        if be == expected { return "big-endian fixed64 at offset \(i)" }
        if le == expected { return "little-endian fixed64 at offset \(i)" }
    }
    return nil
}

/// Scan for a protobuf varint equal to `expected` (the muid is a varint in the guide payload).
func scanVarint(_ bytes: [UInt8], for expected: UInt64) -> String? {
    for start in bytes.indices {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var i = start
        while i < bytes.count && shift < 64 {
            let b = bytes[i]
            value |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 {
                if value == expected { return "varint at offset \(start)" }
                break
            }
            shift += 7
            i += 1
        }
    }
    return nil
}

func base64Decode(_ s: String) -> [UInt8]? {
    var t = s.replacingOccurrences(of: "-", with: "+")
             .replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t += "=" }
    guard let d = Data(base64Encoded: t) else { return nil }
    return [UInt8](d)
}

func hexDecode(_ s: String) -> [UInt8]? {
    let cleaned = s.filter { $0.isHexDigit }
    guard cleaned.count >= 16, cleaned.count % 2 == 0 else { return nil }
    var out: [UInt8] = []
    var idx = cleaned.startIndex
    while idx < cleaned.endIndex {
        let next = cleaned.index(idx, offsetBy: 2)
        guard let b = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
        out.append(b)
        idx = next
    }
    return out
}

func analyse(rawValue raw: String, expected: UInt64) -> [String] {
    var hits: [String] = []
    let dec = String(expected)
    let hex = String(expected, radix: 16)

    if raw == dec                                    { hits.append("IDENTICAL to the decimal muid") }
    else if raw.contains(dec)                        { hits.append("contains the decimal muid as a substring") }
    if raw.lowercased().contains(hex)                { hits.append("contains the hex muid (\(hex))") }
    if let v = UInt64(raw), v == expected            { hits.append("parses directly to the muid") }
    if let v = UInt64(raw, radix: 16), v == expected { hits.append("parses as hex to the muid") }

    if let b = base64Decode(raw) {
        if let where_ = scanFixed64(b, for: expected) { hits.append("base64 payload contains muid as \(where_)") }
        if let where_ = scanVarint(b, for: expected)  { hits.append("base64 payload contains muid as \(where_)") }
    }
    if let b = hexDecode(raw) {
        if let where_ = scanFixed64(b, for: expected) { hits.append("hex payload contains muid as \(where_)") }
        if let where_ = scanVarint(b, for: expected)  { hits.append("hex payload contains muid as \(where_)") }
    }
    return hits
}

// MARK: - Guide link builder (same encoding proven working on device)

enum Proto {
    static func varint(_ value: UInt64) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }
    static func tag(_ field: Int, _ wire: Int) -> [UInt8] { varint(UInt64(field << 3 | wire)) }
    static func lenDelim(_ field: Int, _ body: [UInt8]) -> [UInt8] {
        tag(field, 2) + varint(UInt64(body.count)) + body
    }
    static func string(_ field: Int, _ s: String) -> [UInt8] { lenDelim(field, Array(s.utf8)) }
    static func vint(_ field: Int, _ v: UInt64) -> [UInt8] { tag(field, 0) + varint(v) }
}

func guideLink(title: String, places: [(muid: UInt64, name: String)]) -> String {
    var body = Proto.string(1, title)
    for p in places {
        let loc = Proto.vint(1, 9902)          // lsp — Apple's own place database
                + Proto.vint(2, p.muid)        // appleMapsId
                + Proto.string(3, "")          // address (server overrides it)
                + Proto.string(5, p.name)      // label (server overrides it too)
        body += Proto.lenDelim(2, loc)
    }
    let b64 = Data(body).base64EncodedString()
    let enc = b64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? b64
    return "https://maps.apple.com/guide?_col=" + enc
}

// MARK: - Search

func bestMatch(for k: Known) async -> MKMapItem? {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = k.query
    request.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: k.lat, longitude: k.lon),
        latitudinalMeters: 600, longitudinalMeters: 600)

    do {
        let response = try await MKLocalSearch(request: request).start()
        let target = CLLocation(latitude: k.lat, longitude: k.lon)
        return response.mapItems.min {
            let a = CLLocation(latitude: $0.placemark.coordinate.latitude,
                               longitude: $0.placemark.coordinate.longitude)
            let b = CLLocation(latitude: $1.placemark.coordinate.latitude,
                               longitude: $1.placemark.coordinate.longitude)
            return a.distance(from: target) < b.distance(from: target)
        }
    } catch {
        print("    search failed: \(error.localizedDescription)")
        return nil
    }
}

// MARK: - Run

@main
struct Probe {
    static func main() async {
        print("MapKit place-identifier probe")
        print("Comparing MKMapItem.identifier against known Apple muids\n")

        var recovered: [(muid: UInt64, name: String)] = []
        var matched = 0
        var examined = 0

        for k in knowns {
            print("── \(k.query)")
            print("   expected muid: \(k.muid)")

            guard let item = await bestMatch(for: k) else {
                print("   no result\n"); continue
            }

            let here = CLLocation(latitude: item.placemark.coordinate.latitude,
                                  longitude: item.placemark.coordinate.longitude)
            let metres = here.distance(from: CLLocation(latitude: k.lat, longitude: k.lon))
            print("   matched:  \(item.name ?? "unnamed")  (\(Int(metres)) m from expected)")
            if metres > 150 {
                print("   ⚠︎  probably a different branch — treat the comparison below with suspicion")
            }

            var raw: String?
            if #available(macOS 15.0, iOS 18.0, *) {
                raw = item.identifier?.rawValue
            }

            guard let rawValue = raw else {
                print("   identifier: nil (unavailable on this OS, or absent for this result)\n")
                continue
            }

            examined += 1
            print("   identifier rawValue: \(rawValue)")
            print("   length: \(rawValue.count) chars")

            let hits = analyse(rawValue: rawValue, expected: k.muid)
            if hits.isEmpty {
                print("   ✗ no relationship to the muid found")
            } else {
                matched += 1
                for h in hits { print("   ✓ \(h)") }
                recovered.append((k.muid, item.name ?? k.query))
            }

            if let url = item.url { print("   url: \(url.absoluteString)") }
            print("")
        }

        print(String(repeating: "─", count: 60))
        print("identifiers examined: \(examined) of \(knowns.count)")
        print("with a recoverable muid: \(matched)")
        print("")

        if matched == examined && examined > 0 {
            print("VERDICT: MapKit exposes the muid. The pipeline is clean end to end —")
            print("resolve with MKLocalSearch, deliver with a guide link, no scraping anywhere.")
        } else if matched > 0 {
            print("VERDICT: partial. Some identifiers yield a muid and some do not.")
            print("Look at which ones failed before designing around this.")
        } else {
            print("VERDICT: MapKit's identifier is NOT the muid, at least not in any obvious")
            print("encoding. Print the rawValues above and compare by hand before concluding —")
            print("then consider whether MKMapItemRequest round-trips an identifier into a")
            print("place that Maps itself will accept in a guide.")
        }

        if !recovered.isEmpty {
            print("\nEnd-to-end check — open this on an iPhone; it should be a guide of \(recovered.count):")
            print(guideLink(title: "MapKit Probe", places: recovered))
        }
    }
}
