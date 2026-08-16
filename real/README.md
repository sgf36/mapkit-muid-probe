# Drop real reel screenshots here

Any `.jpg`, `.png` or `.heic`. No naming convention, no manifest — the probe
prints everything Vision recognises in each one, in the order it found it, with
confidences.

There is no automatic score because there is no ground truth, and because
automated match-scoring has already proved unreliable in this project (a hyphen
in "Fu-unji" produced a false negative in our own scorer). The judgement is
human: look at whether the place name is in there, and whether anything
distinguishes it from the username, hashtags and music credit around it.

Then run the same files past a multimodal model and compare. That comparison is
the actual experiment — the synthetic fixtures only establish where Vision
starts to struggle, not where reels sit on that curve.

## Why this matters

Everything downstream of a place name is proven: MapKit resolves names to Apple
place IDs, and a guide link built from those IDs populates on device. Extraction
is the last unmeasured risk in the whole product, and it is the one that decides
whether the app feels magic or broken.

## A note on privacy

These are your screenshots and this repository is private, but pushing them does
put them on GitHub. If any are personal, run the probe locally on a Mac instead:

```bash
swift run ocrprobe
```

`real/` is otherwise ignored by git — see `.gitignore`. Remove the ignore line if
you do want them committed for CI.
