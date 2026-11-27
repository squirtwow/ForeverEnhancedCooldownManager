// Writes Media/Hatch.tga, the hatching the DoTs band draws other players'
// damage over time spells in (DotsBand.lua). Plain Node, no packages, and the
// same bytes every run, so the file can always be made again from here.
//
//   node Tools/GenerateHatch.mjs
//
// Why hatching at all. Your own spells are marked with a flat band, and other
// players' sit behind it. Two flat bands of the same colour would read as one
// band with a lighter end, which is exactly the thing a player would have to
// guess at, so theirs is hatched: a lean nothing else in the addon draws, at a
// lighter colour, and the part of it that shows past your own band is their
// share.
//
// 64 by 64, a power of two. Every pixel is white: the pattern is carried in
// the alpha alone, so DotsBand.lua colours it (the band's own colour, lighter)
// rather than this file choosing.
//
// The lean. A status bar draws its texture over the whole bar and crops it, so
// the hatching is stretched to the bar's own shape and never slides as the
// value moves. Your target frame's health bar is 126 by 20 (measured in game
// on 26 Nov 2026), so a tile 64 square is squashed to about a sixth of its
// height: a stripe has to be steep here to read as a lean there. These run 4
// across for 1 down, which comes out at about 30 degrees on a 126 by 20 bar.
// The pattern repeats every 4 pixels across and every 16 down, both of which
// divide 64, so the tile joins itself at every edge whatever is done with it.
import { writeFileSync, readFileSync, existsSync } from 'node:fs';

const MEDIA = new URL('../Media/Hatch.tga', import.meta.url);

const W = 64, H = 64;
const LEAN = 4; // how many across a stripe runs for each one down
const PERIOD = 16; // one stripe and the gap after it, along the lean
const INK = 6.4; // how much of that period is the stripe itself (40%)
const FEATHER = 1; // how soft a stripe's own edges are, in pixels

const clamp = v => (v < 0 ? 0 : v > 1 ? 1 : v);
const smoothstep = t => (t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t));

// One pixel's alpha, 0 to 1. Where in the repeat the pixel falls, then how far
// inside the stripe that is, softened across FEATHER so the lean does not come
// out as a staircase at whatever size the bar happens to be.
function alphaAt(x, y) {
  let at = (LEAN * x + y) % PERIOD;
  if (at < 0) at += PERIOD;
  // Distance from the stripe's middle, the short way round the repeat, so the
  // stripe is whole across the seam as well as inside the tile.
  const middle = INK / 2;
  let off = Math.abs(at - middle);
  if (off > PERIOD / 2) off = PERIOD - off;
  return clamp(smoothstep((middle - off) / FEATHER + .5));
}

// An uncompressed 32 bit TGA, BGRA, written out last row first with the
// descriptor's origin bit clear (0x08), as every other texture this addon
// ships is (Tools/GenerateWave.mjs explains why at length). Which way up it is
// hardly shows on a hatch, so nothing here leans on that: it is written the
// one way round this client is known to read.
function write() {
  const header = Buffer.alloc(18);
  header.writeUInt8(0, 0); // no ID field
  header.writeUInt8(0, 1); // no colour map
  header.writeUInt8(2, 2); // plain, uncompressed colour
  header.writeUInt16LE(0, 3); // colour map origin
  header.writeUInt16LE(0, 5); // colour map length
  header.writeUInt8(0, 7); // colour map depth
  header.writeUInt16LE(0, 8); // x origin
  header.writeUInt16LE(0, 10); // y origin
  header.writeUInt16LE(W, 12);
  header.writeUInt16LE(H, 14);
  header.writeUInt8(32, 16); // bits a pixel
  header.writeUInt8(0x08, 17); // 8 bits of alpha, rows from the bottom up
  const pixels = Buffer.alloc(W * H * 4);
  for (let y = 0; y < H; y++) {
    const row = (H - 1 - y) * W * 4; // the picture's row y, written bottom up
    for (let x = 0; x < W; x++) {
      const at = row + x * 4;
      pixels[at] = 255; // blue
      pixels[at + 1] = 255; // green
      pixels[at + 2] = 255; // red
      // Each pixel sampled at its own middle, as the skull's is.
      pixels[at + 3] = Math.max(0, Math.min(255, Math.round(alphaAt(x + .5, y + .5) * 255)));
    }
  }
  const file = Buffer.concat([header, pixels]);
  writeFileSync(MEDIA, file);
  return file.length;
}

// Read back what was written and prove it: nothing here trusts the buffer it
// just made.
let failed = 0;
function check(label, actual, expected) {
  const ok = String(actual) === String(expected);
  if (!ok) failed++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${label}: ${actual}${ok ? '' : ` (expected ${expected})`}`);
}

const wrote = write();
const file = readFileSync(MEDIA);
// One pixel of the picture, by its row from the top: the file holds the rows
// the other way up, so the row has to be turned round to read it back.
const alpha = (x, y) => file[18 + (((H - 1 - y) * W + x) * 4) + 3];

console.log(`${MEDIA.pathname.replace(/^\//, '')}: ${wrote} bytes`);
check('the file is the header and one pixel each', file.length, 18 + W * H * 4);
check('written where the addon looks for it', existsSync(MEDIA), true);
check('no ID field, no colour map, plain uncompressed colour', `${file[0]} ${file[1]} ${file[2]}`, '0 0 2');
check('the colour map fields are all nothing', `${file.readUInt16LE(3)} ${file.readUInt16LE(5)} ${file[7]}`, '0 0 0');
check('no origin offset', `${file.readUInt16LE(8)} ${file.readUInt16LE(10)}`, '0 0');
check('64 by 64, a power of two', `${file.readUInt16LE(12)} ${file.readUInt16LE(14)}`, '64 64');
check('32 bits a pixel, 8 of them alpha, rows from the bottom up', `${file[16]} 0x${file[17].toString(16)}`, '32 0x8');
check('every pixel is white, so the addon colours it', `${file[18]} ${file[19]} ${file[20]}`, '255 255 255');

// The pattern itself, read back out of the file. A stripe, then the gap after
// it, along the top row: the repeat is 4 pixels across, so one row holds 16 of
// them and no row is ever empty.
let solid = 0, clear = 0;
for (let x = 0; x < W; x++) {
  if (alpha(x, 0) === 255) solid++;
  if (alpha(x, 0) === 0) clear++;
}
check('the top row is stripes and gaps, not one block', solid > 0 && clear > 0, true);
// The lean: the stripes stand LEAN apart across and one apart every LEAN rows
// down, which is what makes a lean rather than a set of upright bars. Steep in
// the tile on purpose: a 126 by 20 bar squashes it to about 30 degrees.
const found = y => { for (let x = 0; x < W; x++) if (alpha(x, y) === 255) return x; return -1; };
const top = found(16), lower = found(20);
// Four rows down, a stripe stands one pixel to the left. The stripes repeat
// every LEAN across, so that is read inside one repeat.
check('a stripe stands one pixel along every four rows down, so it leans',
  `${top >= 0} ${lower >= 0} ${((top - lower) % LEAN + LEAN) % LEAN}`, 'true true 1');
check('and the stripes stand four apart across', `${alpha(top, 16)} ${alpha(top + LEAN, 16)}`, '255 255');
// It joins itself at every edge, so nothing of the tile shows as a seam
// whatever shape the bar it is drawn over turns out to be: the pattern repeats
// every LEAN across and every PERIOD down, and both divide 64.
let seams = 0;
for (let y = 0; y < H; y++) {
  for (let x = 0; x + LEAN < W; x++) if (Math.abs(alpha(x, y) - alpha(x + LEAN, y)) > 1) seams++;
}
for (let x = 0; x < W; x++) {
  for (let y = 0; y + PERIOD < H; y++) if (Math.abs(alpha(x, y) - alpha(x, y + PERIOD)) > 1) seams++;
}
check('the repeat divides the tile both ways, so it joins itself',
  `${W % LEAN} ${H % PERIOD} ${seams}`, '0 0 0');
// Enough ink to read as hatching over a health bar, and not so much that it is
// a solid band with scratches in it. Four tenths of the repeat is the stripe,
// and its soft edges take a little off that.
let ink = 0;
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) ink += alpha(x, y) / 255;
}
const share = ink / (W * H);
check('between a quarter and a half of it is stripe', share > .25 && share < .5, true);
console.log(`${failed === 0 ? 'all checks passed' : `${failed} FAILED`} (stripe ${(share * 100).toFixed(1)}% of the tile)`);
process.exit(failed === 0 ? 0 : 1);
