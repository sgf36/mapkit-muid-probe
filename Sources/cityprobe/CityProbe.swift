import Foundation
import MapKit
import CoreLocation

// The muid probe answered a format question: MKMapItem.identifier IS the muid.
// That does not vary by city. What varies is RESOLUTION QUALITY — whether
// MKLocalSearch returns the right business given a name phrased the way a reel
// phrases it, with no coordinate to lean on.
//
// So this probe deliberately withholds the crutch the first one used. Queries are
// bare place names as they appear on screen in a reel; the only hint is a
// city-sized region, which is the most a reel realistically tells you.
//
// Apple resolves a muid to its own canonical record and overrides your label, so a
// wrong match ships silently under a confident name. That is what we are hunting.

struct City {
    let name: String
    let lat: CLLocationDegrees
    let lon: CLLocationDegrees
    let queries: [String]
}

let cities: [City] = [
    City(name: "Rome", lat: 41.8967, lon: 12.4822, queries: [
        "Roscioli",                    // three venues, near-identical names
        "Da Enzo al 29",               // numeral in the name
        "Tonnarello",                  // multiple branches now
        "Bonci Pizzarium",
        "Sant'Eustachio Il Caffè",     // apostrophe and a grave accent
        "Forno Campo de' Fiori",       // internal apostrophe
        "Otaleg",                      // small, low-coverage
        "Trattoria Da Teo",
        "Giolitti",                    // chain-ish, many imitators
        "La Pergola",                  // generic words, hotel restaurant
    ]),
    City(name: "Tokyo", lat: 35.6812, lon: 139.7671, queries: [
        "Ichiran Shibuya",             // chain with dozens of branches
        "Fuunji",                      // romanised, no kanji given
        "Nakiryu",
        "Kagari Ginza",
        "Sushi Saito",
        "Tsuta",                       // short romanisation, ambiguous
        "Afuri Harajuku",
        "Den",                         // one syllable, worst case
    ]),
]

// MARK: - Text normalisation

func normalise(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive],
              locale: Locale(identifier: "en_US_POSIX"))
     .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
     .split(separator: " ").joined(separator: " ")
}

/// Content words from a query — drops short and generic tokens.
func tokens(_ s: String) -> Set<String> {
    let stop: Set<String> = ["the", "da", "de", "di", "il", "la", "al", "and",
                             "cafe", "caffe", "trattoria", "ristorante", "bar"]
    return Set(normalise(s).split(separator: " ")
        .map(String.init)
        .filter { $0.count > 2 && !stop.contains($0) })
}

func shareToken(_ a: String, _ b: String) -> Bool {
    !tokens(a).isDisjoint(with: tokens(b))
}

// MARK: - Search

struct Candidate {
    let name: String
    let address: String
    let category: String
    let muid: UInt64?
    let metresFromCentre: Double
}

func search(_ query: String, in city: City) async -> [Candidate] {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    request.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon),
        latitudinalMeters: 20_000, longitudinalMeters: 20_000)   // city, not street

    let centre = CLLocation(latitude: city.lat, longitude: city.lon)
    do {
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
            var muid: UInt64?
            if #available(macOS 15.0, iOS 18.0, *),
               let raw = item.identifier?.rawValue, raw.hasPrefix("I") {
                muid = UInt64(raw.dropFirst(), radix: 16)
            }
            let here = CLLocation(latitude: item.placemark.coordinate.latitude,
                                  longitude: item.placemark.coordinate.longitude)
            return Candidate(
                name: item.name ?? "unnamed",
                address: item.placemark.title ?? "—",
                category: item.pointOfInterestCategory?.rawValue
                    .replacingOccurrences(of: "MKPOICategory", with: "") ?? "—",
                muid: muid,
                metresFromCentre: here.distance(from: centre))
        }
    } catch {
        print("    search failed: \(error.localizedDescription)")
        return []
    }
}

// MARK: - Guide link

enum Proto {
    static func varint(_ value: UInt64) -> [UInt8] {
        var v = value; var out: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F); v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }
    static func tag(_ f: Int, _ w: Int) -> [UInt8] { varint(UInt64(f << 3 | w)) }
    static func lenDelim(_ f: Int, _ b: [UInt8]) -> [UInt8] { tag(f,2) + varint(UInt64(b.count)) + b }
    static func string(_ f: Int, _ s: String) -> [UInt8] { lenDelim(f, Array(s.utf8)) }
    static func vint(_ f: Int, _ v: UInt64) -> [UInt8] { tag(f,0) + varint(v) }
}

func guideLink(title: String, places: [(muid: UInt64, name: String)]) -> String {
    var body = Proto.string(1, title)
    for p in places {
        let loc = Proto.vint(1, 9902) + Proto.vint(2, p.muid)
                + Proto.string(3, "") + Proto.string(5, p.name)
        body += Proto.lenDelim(2, loc)
    }
    let b64 = Data(body).base64EncodedString()
    return "https://maps.apple.com/guide?_col="
        + (b64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? b64)
}

// MARK: - Run

@main
struct CityProbe {
    static func main() async {
        print("MapKit resolution probe — messy cities, no coordinate hint")
        print("Query = the place name as a reel would state it. Region = the whole city.\n")

        var totalQueries = 0
        var empty: [String] = []
        var suspect: [String] = []       // top result shares no word with the query
        var ambiguous: [String] = []     // several results look like the same name
        var noIdentifier: [String] = []

        for city in cities {
            print(String(repeating: "═", count: 62))
            print("\(city.name)\n")

            var topHits: [(muid: UInt64, name: String)] = []

            for query in city.queries {
                totalQueries += 1
                print("── \"\(query)\"")
                let results = await search(query, in: city)

                guard let top = results.first else {
                    print("   ✗ no results\n")
                    empty.append("\(city.name): \(query)")
                    continue
                }

                let sameName = results.filter { shareToken($0.name, query) }
                print("   \(results.count) result(s), \(sameName.count) sharing the query name")

                for (i, c) in results.prefix(3).enumerated() {
                    let marker = i == 0 ? "→" : " "
                    let id = c.muid.map(String.init) ?? "no identifier"
                    print("   \(marker) \(c.name)  ·  \(c.category)")
                    print("      \(c.address)")
                    print("      muid \(id)  ·  \(Int(c.metresFromCentre / 100) * 100) m from centre")
                }

                if !shareToken(top.name, query) {
                    print("   ⚠︎ top result shares no word with the query — likely wrong")
                    suspect.append("\(city.name): \"\(query)\" → \(top.name)")
                }
                if sameName.count > 1 {
                    print("   ⚠︎ \(sameName.count) candidates share the name — needs user confirmation")
                    ambiguous.append("\(city.name): \"\(query)\" × \(sameName.count)")
                }
                if top.muid == nil {
                    print("   ⚠︎ no identifier — this place cannot go in a guide")
                    noIdentifier.append("\(city.name): \(query)")
                } else if shareToken(top.name, query) {
                    topHits.append((top.muid!, top.name))
                }
                print("")
            }

            if !topHits.isEmpty {
                print("\(city.name) guide from top hits (\(topHits.count) places) — open on iPhone:")
                print(guideLink(title: "Probe · \(city.name)", places: topHits))
                print("")
            }
        }

        print(String(repeating: "═", count: 62))
        print("SUMMARY  ·  \(totalQueries) queries\n")
        func report(_ label: String, _ items: [String]) {
            print("\(label): \(items.count)")
            for i in items { print("   · \(i)") }
        }
        report("No results", empty)
        report("Top result looks wrong", suspect)
        report("Ambiguous — multiple same-name candidates", ambiguous)
        report("No identifier (unusable in a guide)", noIdentifier)

        let clean = totalQueries - empty.count - suspect.count - ambiguous.count - noIdentifier.count
        print("\nUnambiguous, identifiable, plausible: \(clean) of \(totalQueries)")
        print("\nAmbiguity is not failure — it is the case that needs a confirmation screen.")
        print("Open the guide links above and check the pins are the right businesses;")
        print("only a human can score that, and it is the number that matters.")
    }
}
