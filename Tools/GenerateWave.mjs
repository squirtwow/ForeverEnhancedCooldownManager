// Writes Media/Wave.tga, the one texture the Resource fill's surface is drawn
// from (Fill.lua). Plain Node, no packages, and the same bytes every run, so
// the file can always be made again from here.
//
//   node Tools/GenerateWave.mjs
//
// 256 by 256, both powers of two, which is what the game needs to tile a
// texture past its own edge. Four bands of 64 rows, stacked, every one off
// the same curve so they line up when they are drawn over each other:
//
//   rows   0 to  63   above the surface  (1 above the curve, 0 below)
//   rows  64 to 127   below the surface  (the other way round)
//   rows 128 to 191   the crest's glow   (bright on the curve, fading off it)
//   rows 192 to 255   clear, kept spare
//
// Two full waves across the width, so the left edge meets the right and the
// band scrolls for ever without a seam. Every pixel is white: the shape is
// carried in the alpha alone, so Fill.lua tints each band with the power's
// colour, black or white as it needs (SetVertexColor).
import { writeFileSync, readFileSync, existsSync } from 'node:fs';

const MEDIA = new URL('../Media/Wave.tga', import.meta.url);

const W = 256, H = 256, BAND = 64;
const WAVES = 2; // full waves across the width: what makes it tile
const CENTRE = 32, AMP = 17; // the curve's middle row, and how far it swings
const FEATHER = 3.2; // how soft the edge between light and dark is, in rows
const CORE = 5, HALO = 14, HALO_A = .40; // the crest's bright core and the glow around it
// The glow has to be nothing at all by the time it reaches the band's own top
// and bottom rows, because Fill.lua draws exactly those 64 rows and nothing
// past them: a glow still going when the rows run out ends in a hard straight
// line across the icon, one at the fill's own level and one a band above it,
// which is the straight bar this whole look exists to get rid of. The halo
// alone is still a quarter solid at both edges (0.22 at the top, 0.24 at the
// foot), so the last rows fade it out. The curve never comes within 14 rows
// of either edge, so the bright core itself is never touched.
const EDGE = 12; // rows the glow fades over at each end of its band

const curveY = x => CENTRE + AMP * Math.sin(2 * Math.PI * WAVES * x / W);
const clamp = v => (v < 0 ? 0 : v > 1 ? 1 : v);
const smoothstep = t => (t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t));
const gauss = (d, s) => Math.exp(-(d * d) / (2 * s * s));

// One pixel's alpha, 0 to 1: which band the row is in decides which shape it
// takes. Nothing is pre-multiplied.
function alphaAt(x, y) {
  if (y < BAND) return smoothstep((curveY(x) - y) / FEATHER);
  if (y < BAND * 2) return smoothstep((y - BAND - curveY(x)) / FEATHER);
  if (y < BAND * 3) {
    const row = y - BAND * 2;
    const d = Math.abs(row - curveY(x));
    const edge = smoothstep(Math.min(row, BAND - 1 - row) / EDGE);
    return clamp(Math.max(gauss(d, CORE), HALO_A * gauss(d, HALO))) * edge;
  }
  return 0;
}

// An uncompressed 32 bit TGA, BGRA. The picture is laid out top down above
// (row 0 is its top, where Fill.lua's texture coordinates expect band 0) and
// written out last row first, with the descriptor's origin bit clear (0x08).
// That is what every other texture this addon ships does, and it is the only
// row order proved on this client: Media/TourArrow.tga is written that way,
// its widest row is first in the file, and it is a triangle pointing up in
// game (Bars.lua's ARROW, TestHelp's arrow check). Whether the client also
// honours the top down bit (0x20) has never been seen here, and the wave
// would be upside down if it does not: the crest's glow would sit under the
// water line and the darkening under the fill instead of above it.
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
      pixels[at + 3] = Math.max(0, Math.min(255, Math.round(alphaAt(x, y) * 255)));
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
const alpha = (x, y) => raw(x, H - 1 - y);
function raw(x, row) { return file[18 + ((row * W + x) * 4) + 3]; }

console.log(`${MEDIA.pathname.replace(/^\//, '')}: ${wrote} bytes`);
check('the file is the header and one pixel each', file.length, 18 + W * H * 4);
check('written where the addon looks for it', existsSync(MEDIA), true);
check('no ID field, no colour map, plain uncompressed colour', `${file[0]} ${file[1]} ${file[2]}`, '0 0 2');
check('the colour map fields are all nothing', `${file.readUInt16LE(3)} ${file.readUInt16LE(5)} ${file[7]}`, '0 0 0');
check('no origin offset', `${file.readUInt16LE(8)} ${file.readUInt16LE(10)}`, '0 0');
check('256 by 256, both powers of two', `${file.readUInt16LE(12)} ${file.readUInt16LE(14)}`, '256 256');
check('32 bits a pixel, 8 of them alpha, rows from the bottom up', `${file[16]} 0x${file[17].toString(16)}`, '32 0x8');
// Written the same way up as every other texture the addon ships, which is
// the only way round this client is known to read (see write, above): the
// spare band, which is the foot of the picture, comes first in the file, and
// the above band's solid top row comes last.
check('the spare band is the first row in the file, so the rows go bottom up', `${raw(32, 0)} ${raw(32, 63)}`, '0 0');
check('and the picture\'s own top row is the last in the file', raw(32, H - 1), 255);

// The curve at x = 32 is at its highest: 32 + 17 = row 49 of its band.
check('the curve stands at row 49 a quarter of the way across', Math.round(curveY(32)), 49);
check('band 0 is solid well above the curve', alpha(32, 0), 255);
check('band 0 is clear well below it', alpha(32, 60), 0);
check('band 1 is clear at the top of its band', alpha(32, BAND), 0);
check('band 1 is solid at the bottom of its band', alpha(32, BAND * 2 - 1), 255);
check('band 2 is brightest on the curve itself', alpha(32, BAND * 2 + 49), 255);
check('band 2 has faded well off the curve', alpha(32, BAND * 2 + 10) < 40, true);
// Fill.lua draws the crest's 64 rows and nothing past them, so a glow still
// going at the first or last of them ends in a straight line across the icon.
let edge = 0, core = 255;
for (let x = 0; x < W; x++) {
  edge = Math.max(edge, alpha(x, BAND * 2), alpha(x, BAND * 3 - 1));
  core = Math.min(core, alpha(x, BAND * 2 + Math.round(curveY(x))));
}
check('band 2 is nothing at all at both ends of its own band, so the glow never cuts off in a line', edge, 0);
check('and the curve itself is still solid all the way along', core >= 250, true);
check('band 3 is left clear', alpha(32, 200) + alpha(128, 240), 0);

// It tiles: two waves across the width, so the pattern repeats every 128
// pixels and the right edge meets the left.
let seam = 0, offBand = 0;
for (let y = 0; y < H; y++) {
  for (let x = 0; x < 128; x++) if (alpha(x, y) !== alpha(x + 128, y)) seam++;
}
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const at = 18 + ((y * W + x) * 4);
    if (file[at] !== 255 || file[at + 1] !== 255 || file[at + 2] !== 255) offBand++;
  }
}
check('every pixel repeats after 128 across, so it tiles with no seam', seam, 0);
check('every pixel is white, with the shape in the alpha alone', offBand, 0);

if (failed) {
  console.log(`\n${failed} check${failed === 1 ? '' : 's'} failed.`);
  process.exit(1);
}
console.log('\nMedia/Wave.tga written and checked.');
