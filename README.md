# MapKit muid probe

## Result — 16 August 2026

**MapKit exposes the muid.** `MKMapItem.identifier.rawValue` is `I` followed by the
muid in uppercase hex. Five of five matched, each within 7 m of the expected
coordinate.

```
Dishoom Shoreditch    I43FA2531C5B5D635   →  4898268440419489333
Wright Brothers       I655EEDD5976A0811   →  7304537147265648657
Elliot's              I94FE63725FB590E2   →  10736127904580997346
Arabica               I52BEC654CD7F9E76   →  5962421024212360822
Black & Blue          I137AF3B095BD9DE0   →  1403702173631356384

muid = UInt64(rawValue.dropFirst(), radix: 16)
```

The delivery chain is therefore clean end to end: `MKLocalSearch` → identifier →
muid → guide link → populated guide in Apple Maps, with no scraping and no private
endpoints anywhere in it.

Caveat: all five are London businesses with strong Apple coverage. Chains,
non-English names and thin-coverage regions are where `MKLocalSearch` will return a
confident wrong match — and a wrong muid ships silently under Apple's own label.

---


Answers the last open question in the Reels-to-Guides feasibility work: **does MapKit
hand a third-party app the same place identifier Apple Maps uses internally?**

Guide links only populate in the Maps app when each place is identified by an Apple
`muid` paired with `lsp 9902`. Coordinate-only payloads render fine on
`maps.apple.com` and arrive empty on device. So the whole pipeline depends on being
able to obtain a `muid` legitimately.

The five ground-truth muids in `Probe.swift` were captured from Apple Maps' own web
client on 16 August 2026, and are confirmed working — guide links built from them
populate correctly on iPhone.

## What it does

For each known place: runs `MKLocalSearch` biased to its coordinate, takes the
nearest result, reads `MKMapItem.identifier.rawValue`, and tests whether the muid is
recoverable from it — as decimal, as hex, or embedded in a base64 or hex payload as a
fixed64 or a protobuf varint, either endianness.

If any muids come back, it prints a guide link built from them. Open that on an
iPhone: if it populates, the pipeline is proven end to end.

## Running it

No Mac required — push this folder to a repo and trigger **MapKit muid probe** from
the Actions tab. Everything is in the run log.

With a Mac:

```bash
swift run muidprobe
```

## Reading the result

- **All identifiers yield a muid** — pipeline is clean. Resolve with MKLocalSearch,
  deliver with a guide link, no scraping anywhere in the product.
- **None do** — MapKit's identifier is a different namespace. Before concluding,
  check whether `MKMapItemRequest` round-trips an identifier back into a place that
  Maps will accept, and compare the printed rawValues by hand; the probe only detects
  encodings it knows to look for.
- **Some do** — find out what distinguishes the failures. Chains and multi-branch
  businesses are the likely dividing line.

A match farther than 150 m from the expected coordinate is flagged; that usually
means a different branch was matched and the comparison is meaningless for that row.
