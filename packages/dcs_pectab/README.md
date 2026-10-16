# dcs_pectab

Lossless **AEA PECTAB** codec for boarding-pass (BP) and bag-tag (BT) print templates used by DCS.

Pure Dart (no Flutter). Parse → serialize equals the input byte-for-byte for every stream; unknown /
ambiguous bytes are kept verbatim. Only edited elements are re-serialized.

## Spec

Format truth lives in the DCS app design docs (product owner's "Manual Pectab"):

- [`dcs/design/pectab-builder/SPEC.md`](../../../dcs/design/pectab-builder/SPEC.md) — BP grid, BT
  orientation, BOX/LINE, data (CP/BTP), printer answers, open questions Q1–Q6
- [`ARCHITECTURE.md`](../../../dcs/design/pectab-builder/ARCHITECTURE.md) — model, round-trip rules,
  geometry, catalog, lint

Sibling path assumes this monorepo sits next to `../dcs` (same layout as other `dcs_*` packages).

## Install (git)

```yaml
dependencies:
  dcs_pectab:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_pectab
      ref: dcs_pectab-v0.1.0   # pin a tag once P10 lands
```

## Status

Skeleton only (`0.1.0-dev`). Tickets P2–P10 add tokenizer, BP/BT codecs, templates, round-trip
tests, geometry, catalog, lint, and sample-data parsing; then tag `dcs_pectab-v0.1.0`.

## More information

Part of [dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages).
