/**
 * Content inspection for uploaded clinical documents.
 *
 * Two jobs, both of which must happen server-side because the client's claims
 * about a file are exactly as trustworthy as the client:
 *
 *  1. **Identify the file from its bytes**, not its extension or its
 *     `Content-Type`. A `.pdf` that is really an HTML document with a script in
 *     it is the oldest trick there is, and a doctor's browser will happily
 *     render it.
 *  2. **Strip embedded metadata.** A photograph of a prescription taken on a
 *     phone carries the GPS coordinates of the clinic, the device serial, and
 *     the exact capture time in its EXIF block. None of that is clinical data
 *     and all of it is personal data under the DPDP Act, so it is removed
 *     before the file is readable by anyone.
 *
 * What this deliberately is **not** is an antivirus. Detecting malware needs a
 * maintained signature database, which is a vendor relationship, not a
 * function. `scanForMalware` is the seam where one goes; until it is wired the
 * pipeline is honest about being format validation only.
 */

export type DetectedType = "application/pdf" | "image/jpeg" | "image/png" | "image/heic";

/**
 * Identifies a file from its leading bytes.
 *
 * Returns null for anything unrecognised, which the caller treats as a
 * rejection — an allow-list, so a format nobody vetted cannot arrive by simply
 * not matching a deny rule.
 */
export function detectContentType(data: Buffer): DetectedType | null {
  if (data.length < 12) return null;

  // %PDF-
  if (data[0] === 0x25 && data[1] === 0x50 && data[2] === 0x44 && data[3] === 0x46) {
    return "application/pdf";
  }

  // JPEG: FF D8 FF
  if (data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff) {
    return "image/jpeg";
  }

  // PNG: 89 50 4E 47 0D 0A 1A 0A
  const PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (PNG.every((b, i) => data[i] === b)) {
    return "image/png";
  }

  // HEIC: an ISO-BMFF box whose type is `ftyp` with a HEIF-family brand.
  if (data.subarray(4, 8).toString("ascii") === "ftyp") {
    const brand = data.subarray(8, 12).toString("ascii");
    if (["heic", "heix", "hevc", "hevx", "mif1", "msf1"].includes(brand)) {
      return "image/heic";
    }
  }

  return null;
}

/**
 * Removes metadata segments that carry personal data.
 *
 * JPEG and PNG are handled losslessly by dropping the relevant segments or
 * chunks; the image data itself is untouched, so nothing is re-encoded and no
 * clinical detail is lost to compression.
 *
 * PDF and HEIC pass through unchanged. Rewriting either safely means parsing
 * the whole container, which needs a library and is a larger decision than this
 * function should make on its own — [metadataStripped] reports which happened so
 * the caller can record it rather than assume it.
 */
export function stripMetadata(
  data: Buffer,
  type: DetectedType
): { data: Buffer; metadataStripped: boolean } {
  switch (type) {
    case "image/jpeg":
      return { data: stripJpegMetadata(data), metadataStripped: true };
    case "image/png":
      return { data: stripPngMetadata(data), metadataStripped: true };
    case "application/pdf":
    case "image/heic":
      return { data, metadataStripped: false };
  }
}

/**
 * Drops every APP1..APP15 and COM marker segment from a JPEG.
 *
 * APP1 is where both EXIF (GPS, device, timestamp) and XMP live; APP13 carries
 * IPTC. The scan data after SOS is copied verbatim, so this is lossless.
 */
function stripJpegMetadata(data: Buffer): Buffer {
  const out: Buffer[] = [];
  let i = 0;

  // SOI
  if (data[0] !== 0xff || data[1] !== 0xd8) return data;
  out.push(data.subarray(0, 2));
  i = 2;

  while (i < data.length - 1) {
    if (data[i] !== 0xff) break;

    const marker = data[i + 1]!;

    // Start of scan: everything from here is entropy-coded image data.
    if (marker === 0xda) {
      out.push(data.subarray(i));
      return Buffer.concat(out);
    }

    // Standalone markers carry no length.
    if (marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd9) || marker === 0x01) {
      out.push(data.subarray(i, i + 2));
      i += 2;
      continue;
    }

    const length = data.readUInt16BE(i + 2);
    const segmentEnd = i + 2 + length;
    if (segmentEnd > data.length) break;

    const isAppSegment = marker >= 0xe1 && marker <= 0xef;
    const isComment = marker === 0xfe;

    // APP0 (JFIF) is kept: it is a format header, not metadata about a person.
    if (!isAppSegment && !isComment) {
      out.push(data.subarray(i, segmentEnd));
    }

    i = segmentEnd;
  }

  return Buffer.concat(out);
}

/**
 * Drops ancillary PNG chunks that can carry personal data.
 *
 * Critical chunks (uppercase first letter) are required to render the image and
 * are always kept. `tEXt`/`zTXt`/`iTXt` hold arbitrary text, `eXIf` holds a full
 * EXIF block, and `tIME` is a capture timestamp.
 */
function stripPngMetadata(data: Buffer): Buffer {
  const DROP = new Set(["tEXt", "zTXt", "iTXt", "eXIf", "tIME"]);
  const out: Buffer[] = [data.subarray(0, 8)];

  let i = 8;
  while (i + 8 <= data.length) {
    const length = data.readUInt32BE(i);
    const type = data.subarray(i + 4, i + 8).toString("ascii");
    const chunkEnd = i + 12 + length;
    if (chunkEnd > data.length) break;

    if (!DROP.has(type)) {
      out.push(data.subarray(i, chunkEnd));
    }

    i = chunkEnd;
    if (type === "IEND") break;
  }

  return Buffer.concat(out);
}

/**
 * Seam for a real antivirus.
 *
 * Returns `clean` today because format validation is all this pipeline
 * performs, and reporting a file as virus-scanned when nothing scanned it would
 * be worse than reporting nothing at all. Wiring a vendor here — a ClamAV
 * sidecar, or an object-scanning service — changes this function and nothing
 * else: callers already handle an `infected` verdict.
 */
export async function scanForMalware(
  _data: Buffer
): Promise<{ verdict: "clean" | "infected"; scanner: string }> {
  return { verdict: "clean", scanner: "none" };
}
