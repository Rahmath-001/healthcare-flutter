import { describe, expect, it } from "vitest";

import { detectContentType, stripMetadata } from "./content_inspection";

/** Minimal but structurally valid fixtures, built rather than checked in. */
function jpegWithExif(): Buffer {
  const exifPayload = Buffer.from("Exif\0\0GPSLatitude 12.9716 GPSLongitude 77.5946", "ascii");
  const app1 = Buffer.concat([
    Buffer.from([0xff, 0xe1]),
    lengthPrefix(exifPayload),
    exifPayload,
  ]);

  const comment = Buffer.from("Taken on Priya's iPhone", "ascii");
  const com = Buffer.concat([Buffer.from([0xff, 0xfe]), lengthPrefix(comment), comment]);

  // APP0/JFIF is a format header, not metadata about a person: it must survive.
  const jfif = Buffer.from("JFIF\0\0\0\0\0\0", "binary");
  const app0 = Buffer.concat([Buffer.from([0xff, 0xe0]), lengthPrefix(jfif), jfif]);

  const scan = Buffer.from([0xff, 0xda, 0x00, 0x08, 1, 1, 0, 0, 0x3f, 0x00, 0xaa, 0xbb, 0xff, 0xd9]);

  return Buffer.concat([Buffer.from([0xff, 0xd8]), app0, app1, com, scan]);
}

function lengthPrefix(payload: Buffer): Buffer {
  const b = Buffer.alloc(2);
  b.writeUInt16BE(payload.length + 2);
  return b;
}

function pngChunk(type: string, payload: Buffer): Buffer {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(payload.length);
  // The CRC is not validated by the stripper, so a placeholder is honest here.
  return Buffer.concat([len, Buffer.from(type, "ascii"), payload, Buffer.alloc(4)]);
}

function pngWithText(): Buffer {
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", Buffer.alloc(13)),
    pngChunk("tEXt", Buffer.from("Author\0Priya Sharma", "ascii")),
    pngChunk("eXIf", Buffer.from("GPS 12.9716,77.5946", "ascii")),
    pngChunk("IDAT", Buffer.from([1, 2, 3, 4])),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

describe("detectContentType", () => {
  it("identifies the formats the product accepts", () => {
    expect(detectContentType(Buffer.from("%PDF-1.7\n%\xe2\xe3\xcf\xd3", "binary"))).toBe(
      "application/pdf"
    );
    expect(detectContentType(jpegWithExif())).toBe("image/jpeg");
    expect(detectContentType(pngWithText())).toBe("image/png");

    const heic = Buffer.concat([
      Buffer.alloc(4),
      Buffer.from("ftypheic", "ascii"),
      Buffer.alloc(16),
    ]);
    expect(detectContentType(heic)).toBe("image/heic");
  });

  it("refuses a file that lies about what it is", () => {
    // The oldest trick there is: a .pdf that is really HTML with a script in
    // it, which a doctor's browser will happily render.
    const html = Buffer.from("<html><script>alert(1)</script></html>", "ascii");
    expect(detectContentType(html)).toBeNull();
  });

  it("refuses executables and archives outright", () => {
    expect(detectContentType(Buffer.from("MZ\x90\x00\x03\x00\x00\x00\x04\x00\x00\x00", "binary"))).toBeNull();
    expect(detectContentType(Buffer.from("PK\x03\x04\x14\x00\x00\x00\x08\x00\x00\x00", "binary"))).toBeNull();
    expect(detectContentType(Buffer.from("\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00", "binary"))).toBeNull();
  });

  it("refuses a truncated file rather than guessing", () => {
    expect(detectContentType(Buffer.from([0xff, 0xd8]))).toBeNull();
    expect(detectContentType(Buffer.alloc(0))).toBeNull();
  });
});

describe("stripMetadata", () => {
  it("removes EXIF and comments from a JPEG", () => {
    const original = jpegWithExif();
    expect(original.includes("GPSLatitude")).toBe(true);

    const { data, metadataStripped } = stripMetadata(original, "image/jpeg");

    expect(metadataStripped).toBe(true);
    expect(data.includes("GPSLatitude")).toBe(false);
    expect(data.includes("Priya")).toBe(false);
    expect(data.length).toBeLessThan(original.length);
  });

  it("keeps the JPEG readable — header, JFIF and scan data survive", () => {
    const { data } = stripMetadata(jpegWithExif(), "image/jpeg");

    expect(data.subarray(0, 2)).toEqual(Buffer.from([0xff, 0xd8]));
    // APP0/JFIF describes the format, not the photographer.
    expect(data.includes("JFIF")).toBe(true);
    // Entropy-coded image data after SOS is copied verbatim.
    expect(data.includes(Buffer.from([0xaa, 0xbb]))).toBe(true);
    expect(detectContentType(data)).toBe("image/jpeg");
  });

  it("removes text and EXIF chunks from a PNG but keeps the image", () => {
    const original = pngWithText();
    const { data, metadataStripped } = stripMetadata(original, "image/png");

    expect(metadataStripped).toBe(true);
    expect(data.includes("Priya Sharma")).toBe(false);
    expect(data.includes("GPS 12.9716")).toBe(false);
    expect(data.includes("IHDR")).toBe(true);
    expect(data.includes("IDAT")).toBe(true);
    expect(data.includes("IEND")).toBe(true);
    expect(detectContentType(data)).toBe("image/png");
  });

  it("is idempotent — stripping a clean file changes nothing", () => {
    const once = stripMetadata(jpegWithExif(), "image/jpeg").data;
    const twice = stripMetadata(once, "image/jpeg").data;
    expect(twice).toEqual(once);
  });

  it("reports honestly that PDF and HEIC were not rewritten", () => {
    // Both need a container parser to strip safely. Saying so lets the caller
    // record what actually happened instead of assuming it did.
    const pdf = Buffer.from("%PDF-1.7\n/Author (Priya)\n", "binary");
    const result = stripMetadata(pdf, "application/pdf");
    expect(result.metadataStripped).toBe(false);
    expect(result.data).toEqual(pdf);
  });
});
