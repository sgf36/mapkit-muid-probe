import Foundation
import Vision

// On-device OCR (Apple's Vision framework) over graded reel-like frames.
// The multimodal arm reads the same files; the comparison is the point.
//
// Reports, per image: the best-matching recognised line, how close it is to the
// true place name, and how many other lines came back — because the noise volume
// is half the problem. A place name recovered alongside 14 lines of UI furniture
// still needs something downstream to know which line mattered.

struct Fixture: Decodable {
    let file: String
    let tier: String
    let tier_desc: String
    let expected: String
}

func normalise(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive],
              locale: Locale(identifier: "en_US_POSIX"))
     .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
     .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
     .trimmingCharacters(in: .whitespaces)
}

/// 0…1 similarity, 1 being identical after normalisation.
func similarity(_ a: String, _ b: String) -> Double {
    let x = Array(normalise(a)), y = Array(normalise(b))
    if x.isEmpty || y.isEmpty { return 0 }
    var prev = Array(0...y.count)
    var cur = [Int](repeating: 0, count: y.count + 1)
    for i in 1...x.count {
        cur[0] = i
        for j in 1...y.count {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1,
                         prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
        }
        prev = cur
    }
    return 1.0 - Double(prev[y.count]) / Double(max(x.count, y.count))
}

struct Reading {
    let lines: [(text: String, confidence: Float)]
    let best: (text: String, score: Double)?
}

func recognise(url: URL, expected: String, level: VNRequestTextRecognitionLevel,
               correction: Bool) -> Reading {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level
    request.usesLanguageCorrection = correction
    request.recognitionLanguages = ["en-GB", "en-US", "it-IT"]

    let handler = VNImageRequestHandler(url: url, options: [:])
    do { try handler.perform([request]) }
    catch { return Reading(lines: [], best: nil) }

    let lines: [(String, Float)] = (request.results ?? []).compactMap {
        guard let c = $0.topCandidates(1).first else { return nil }
        return (c.string, c.confidence)
    }
    let best = lines
        .map { (text: $0.0, score: similarity($0.0, expected)) }
        .max { $0.score < $1.score }
    return Reading(lines: lines, best: best)
}

@main
struct OCRProbe {
    static func main() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("fixtures")
        guard let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")),
              let fixtures = try? JSONDecoder().decode([Fixture].self, from: data) else {
            print("no fixtures/manifest.json — run tools/make_fixtures.py first")
            exit(1)
        }

        print("Vision OCR probe — \(fixtures.count) graded reel frames")
        print("Score is similarity between the true place name and the closest line OCR returned.\n")

        var byTier: [String: [Double]] = [:]
        var tierDesc: [String: String] = [:]
        var noiseTotal = 0

        for f in fixtures {
            let url = root.appendingPathComponent(f.file)
            tierDesc[f.tier] = f.tier_desc

            let accurate = recognise(url: url, expected: f.expected,
                                     level: .accurate, correction: true)
            let fast = recognise(url: url, expected: f.expected,
                                 level: .fast, correction: false)

            let a = accurate.best?.score ?? 0
            let ff = fast.best?.score ?? 0
            byTier[f.tier, default: []].append(a)
            noiseTotal += accurate.lines.count

            let mark = a >= 0.95 ? "✓" : (a >= 0.7 ? "~" : "✗")
            print("\(mark) [\(f.tier)] expected: \"\(f.expected)\"")
            print("    accurate: \"\(accurate.best?.text ?? "—")\"  score \(String(format: "%.2f", a))")
            print("    fast:     \"\(fast.best?.text ?? "—")\"  score \(String(format: "%.2f", ff))")
            print("    \(accurate.lines.count) lines recognised in total")
            if a < 0.95 {
                let others = accurate.lines.prefix(6).map { "\"\($0.text)\"" }.joined(separator: ", ")
                print("    saw: \(others)")
            }
            print("")
        }

        print(String(repeating: "═", count: 62))
        print("BY TIER  (mean similarity, accurate mode)\n")
        let order = ["t1-clean", "t2-outlined", "t3-shadow-busy", "t4-low-contrast", "t5-motion"]
        for tier in order {
            guard let scores = byTier[tier], !scores.isEmpty else { continue }
            let mean = scores.reduce(0, +) / Double(scores.count)
            let clean = scores.filter { $0 >= 0.95 }.count
            let bar = String(repeating: "█", count: Int(mean * 30))
                    + String(repeating: "·", count: 30 - Int(mean * 30))
            print(String(format: "  %-16s %@  %.2f   exact %d/%d",
                         (tier as NSString).utf8String!, bar, mean, clean, scores.count))
            print("                   \(tierDesc[tier] ?? "")")
        }

        let all = byTier.values.flatMap { $0 }
        let overall = all.reduce(0, +) / Double(all.count)
        let exact = all.filter { $0 >= 0.95 }.count
        print("\nOverall mean similarity: \(String(format: "%.2f", overall))")
        print("Recovered exactly: \(exact) of \(all.count)")
        print("Average lines of text per frame: \(noiseTotal / max(1, fixtures.count)) — "
            + "the place name is one of them, and OCR does not say which.")
    }
}
