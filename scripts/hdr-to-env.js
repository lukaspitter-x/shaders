// Radiance .hdr (RGBE) -> tone-mapped .bmp (caller converts to jpg via sips).
// Usage: node hdr2jpg.js in.hdr out.bmp [maxWidth]
const fs = require('fs');

function decodeHdr(buf) {
  // Header: text lines until blank, then resolution line.
  let pos = 0;
  function line() {
    let end = pos;
    while (buf[end] !== 0x0a) end++;
    const s = buf.toString('ascii', pos, end);
    pos = end + 1;
    return s;
  }
  const magic = line();
  if (!magic.startsWith('#?')) throw new Error('not a radiance file');
  for (;;) {
    const l = line();
    if (l === '') break;
  }
  const res = line().trim().split(/\s+/); // e.g. -Y 1024 +X 2048
  const h = parseInt(res[1], 10);
  const w = parseInt(res[3], 10);
  const data = new Float32Array(w * h * 3);

  for (let y = 0; y < h; y++) {
    const rowStart = y * w * 3;
    if (buf[pos] === 2 && buf[pos + 1] === 2 && ((buf[pos + 2] << 8) | buf[pos + 3]) === w) {
      // New-style RLE: 4 separately RLE'd component planes.
      pos += 4;
      const planes = new Uint8Array(w * 4);
      for (let c = 0; c < 4; c++) {
        let x = 0;
        while (x < w) {
          let count = buf[pos++];
          if (count > 128) {
            count -= 128;
            const v = buf[pos++];
            for (let i = 0; i < count; i++) planes[c * w + x++] = v;
          } else {
            for (let i = 0; i < count; i++) planes[c * w + x++] = buf[pos++];
          }
        }
      }
      for (let x = 0; x < w; x++) {
        const e = planes[3 * w + x];
        const f = e ? Math.pow(2, e - 136) : 0;
        data[rowStart + x * 3] = planes[x] * f;
        data[rowStart + x * 3 + 1] = planes[w + x] * f;
        data[rowStart + x * 3 + 2] = planes[2 * w + x] * f;
      }
    } else {
      // Flat RGBE row.
      for (let x = 0; x < w; x++) {
        const r = buf[pos++], g = buf[pos++], b = buf[pos++], e = buf[pos++];
        const f = e ? Math.pow(2, e - 136) : 0;
        data[rowStart + x * 3] = r * f;
        data[rowStart + x * 3 + 1] = g * f;
        data[rowStart + x * 3 + 2] = b * f;
      }
    }
  }
  return { w, h, data };
}

function toneMap({ w, h, data }, maxW) {
  const scaleDown = Math.min(1, maxW / w);
  const ow = Math.round(w * scaleDown);
  const oh = Math.round(h * scaleDown);
  // Auto exposure from log-average luminance.
  let logSum = 0;
  let n = 0;
  for (let i = 0; i < data.length; i += 3) {
    const lum = 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
    logSum += Math.log(1e-6 + lum);
    n++;
  }
  const key = 0.18 / Math.exp(logSum / n);
  const px = new Uint8Array(ow * oh * 3);
  for (let oy = 0; oy < oh; oy++) {
    const sy = Math.min(h - 1, Math.round(oy / scaleDown));
    for (let ox = 0; ox < ow; ox++) {
      const sx = Math.min(w - 1, Math.round(ox / scaleDown));
      const si = (sy * w + sx) * 3;
      for (let c = 0; c < 3; c++) {
        let v = data[si + c] * key;
        v = v / (1 + v); // Reinhard
        v = Math.pow(v, 1 / 2.2);
        px[(oy * ow + ox) * 3 + c] = Math.max(0, Math.min(255, Math.round(v * 255)));
      }
    }
  }
  return { w: ow, h: oh, px };
}

function writeBmp(path, { w, h, px }) {
  const rowSize = Math.ceil((w * 3) / 4) * 4;
  const imgSize = rowSize * h;
  const buf = Buffer.alloc(54 + imgSize);
  buf.write('BM');
  buf.writeUInt32LE(54 + imgSize, 2);
  buf.writeUInt32LE(54, 10);
  buf.writeUInt32LE(40, 14);
  buf.writeInt32LE(w, 18);
  buf.writeInt32LE(h, 22);
  buf.writeUInt16LE(1, 26);
  buf.writeUInt16LE(24, 28);
  buf.writeUInt32LE(imgSize, 34);
  for (let y = 0; y < h; y++) {
    const dst = 54 + (h - 1 - y) * rowSize;
    for (let x = 0; x < w; x++) {
      const s = (y * w + x) * 3;
      buf[dst + x * 3] = px[s + 2];
      buf[dst + x * 3 + 1] = px[s + 1];
      buf[dst + x * 3 + 2] = px[s];
    }
  }
  fs.writeFileSync(path, buf);
}

const [, , input, output, maxW] = process.argv;
writeBmp(output, toneMap(decodeHdr(fs.readFileSync(input)), Number(maxW) || 1024));
console.log('ok', output);
