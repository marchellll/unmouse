# BoundaryLabeling

Collision-free floating labels with **non-crossing straight leaders** for Swift.

## Strategy C — Floating Hints + 2-Opt Untangling

1. Seed each label beside its target (cycle of N/E/S/W/diagonal offsets)  
2. Separate overlapping boxes with AABB minimum-translation vectors  
3. When two leaders cross, **swap their frames** (2-opt) if total length drops  
4. Repeat overlap + untangle for a few iterations  

Labels stay near their UI targets — no exile to screen margins.

## Usage

```swift
import BoundaryLabeling

let placed = BoundaryLabeler.layout(
    sites: [
        LabelSite(id: "a", point: CGPoint(x: 120, y: 400), tag: "A"),
        LabelSite(id: "b", point: CGPoint(x: 130, y: 405), tag: "B"),
    ],
    bounds: CGRect(x: 0, y: 0, width: 1280, height: 800)
)

for label in placed {
    // label.frame  — badge rect
    // label.leader — [target, labelEdge]
}
```

## Publishing later

Self-contained SwiftPM package under `Packages/BoundaryLabeling`. Move to its own repo, tag `0.1.0`, replace Unmouse’s `path:` dependency with the git URL.

## License

MIT
