## 0.1.2

* `PectabShape` + `PectabGeometry.shapesOf` / `mirrorShapeOf` / `btCharsOf`: oriented printed boxes (anchor, local
  rect, rotation) used for drawing, hit-testing and handles. `boundsOf` is now their AABB.
* BP barcode anchored at the bottom of its row and rising upward (manual p.6); width by type (PDF417 ≈ 2.2 × h, QR
  square, 1-D ≈ 2.5 × h). The manual's `FAB6Q252033` now lies on the coupon.
* BT text length from its characters (literal / alias target / catalog max) instead of `stroke × 4`; centre / right
  alignment; rotation about the anchor. Barcodes centred across at `WW` mm; lines across the tag.
* Mirror copy = point reflection through (mirror point, tag width / 2), i.e. the element turned 180°.
* Lint: `info` severity (length below catalog max, items not in the catalog, BT duplicates); BT catalog check skips
  literal / alias / line / logo slots; BT width check uses the header tag width; no duplicate BP text overrun warning.

## 0.1.1

* BT header fields: `tagWidth10`, `mirrorPointMm`, continuation / auto / color / elemRef.
* Mirror ghost uses AEA formula (`2*mirrorPoint − along`, `tagWidth − across`) + `mirrorOrientCode`.
* BT kinds: `K` text, `R`/`T` RFID; BP text: optional `magStripe` + `steeringCmd`.

## 0.1.0

* Initial tagged release: lossless PECTAB codec (BP/BT/TT), geometry, catalog, lint, AEA answers, sample data (CP/BTP).

## 0.1.0-dev

* P1–P10 development.
