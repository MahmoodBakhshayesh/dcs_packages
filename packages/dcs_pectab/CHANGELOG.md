## 0.1.5

* BP barcodes: `X` marker (AEA 4.3) as well as `B`, kept on rewrite (`marker`); optional second cell (`pos2`);
  `pectab-setup.md` §8 form with an alphanumeric type (`FABRC01D022232` = type `R`, cells C01 + D02) tried
  after the manual / web forms, so their parses are unchanged (`FABRC012232` still reads as the web short form).
* `BpCodec.literalOf` — BP literal word in the table (`50PASSENGER`), still kept verbatim as `UnknownElement`.

## 0.1.4

* BP barcode rotation is `rotationDeg` (0 / 90 / 180 / 270), stepped ±90° in the builder. Long form: `L` = 90°,
  `R` = 180° (AEA). Short form: `R` = 90°, `L` = 270° (web). `rotate180` remains as a getter/setter for 180°.

## 0.1.3

* Paste cleanup: line breaks and a short label before the preamble (`copied: BTT1039…`) are dropped before parsing;
  never cuts into `#` segments, so raw streams still round-trip.
* Web-designer BP barcode form `B[R|L]{row}{col}{ww}{hh}` (`FABRE422232`) parses as a PDF417 `BpBarcode`
  (`shortWidth`, `shortOrient`), is drawn (≥ 45 × 18 mm, rising from its row) and re-serializes in the same form when
  moved. The manual form (`FAB6Q252033`) is unchanged.

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
