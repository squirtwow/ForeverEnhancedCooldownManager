// Writes Media/Skull.tga, the mark the DoTs band shows on your target's
// portrait once the band covers the rest of its health (DotsBand.lua). Plain
// Node, no packages, and the same bytes every run, so the file can always be
// made again from here.
//
//   node Tools/GenerateSkull.mjs
//
// Ours on purpose. Whether this client has a skull of its own at
// Interface\TargetingFrame\UI-TargetingFrame-Skull has never been checked in
// game, and there is no way for an addon to ask whether a texture file loaded,
// so a missing one would simply draw nothing and the tick would look broken.
// This file is read by name, like Media/Wave.tga, and ships with the addon.
//
// 64 by 64, a power of two. Every pixel is white: the shape is carried in the
// alpha alone, so DotsBand.lua tints it (bone) rather than this file choosing
// a colour. The shape is a front-on skull drawn from distance fields, so its
// edges are soft at any size the portrait happens to be:
//
//   the cranium   an ellipse across the top two thirds
//   the jaw       a narrower rounded block under it, with a chin
//   cut out       two eye sockets, a nose, and the gaps between four teeth
//
// The cut-outs are holes, not dark paint, so the portrait shows through them
// and the mark reads as a skull over whatever is behind it.
import { writeFileSync, readFileSync, existsSync } from 'node:fs';

const MEDIA = new URL('../Media/Skull.tga', import.meta.url);

const W = 64, H = 64;
const FEATHER = 1.3; // how soft every edge is, in pixels

// The cranium, the jaw and the chin, in pixels from the top left.
const SKULL = { x: 32, y: 27, rx: 21, ry: 20 };
const JAW = { x: 32, y: 48, rx: 13, ry: 9, round: 5 };
// The holes: both eye sockets, the nose, and the teeth gaps.
const EYES = [{ x: 23, y: 26, rx: 7.5, ry: 8 }, { x: 41, y: 26, rx: 7.5, ry: 8 }];
const NOSE = { x: 32, y: 38, rx: 3.2, ry: 4.4 };
const MOUTH = { top: 43, bottom: 56, half: 11.5 }; // where the teeth gaps run
const TEETH = [-7.5, -2.5, 2.5, 7.5]; // each gap's middle, from the skull's own middle
const GAP = 1.1; // half a gap's width

const clamp = v => (v < 0 ? 0 : v > 1 ? 1 : v);
const smoothstep = t => (t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t));
// How far inside a shape a point is, turned into 0 to 1 across FEATHER pixels.
const edge = d => smoothstep(d / FEATHER + .5);
// An ellipse's own distance field, in pixels, positive inside.
function inEllipse(x, y, e) {
  const dx = (x - e.x) / e.rx, dy = (y - e.y) / e.ry;
  return (1 - Math.sqrt(dx * dx + dy * dy)) * Math.min(e.rx, e.ry);
}
// A rounded block's, the same way round.
function inBlock(x, y, b) {
  const dx = Math.abs(x - b.x) - (b.rx - b.round), dy = Math.abs(y - b.y) - (b.ry - b.round);
  const ox = Math.max(dx, 0), oy = Math.max(dy, 0);
  return b.round - (Math.sqrt(ox * ox + oy * oy) + Math.min(Math.max(dx, dy), 0));
}

// One pixel's alpha, 0 to 1. The bone is the cranium and the jaw together;
// then the sockets, the nose and the gaps between the teeth are taken out of
// it, so what is left is a skull with holes rather than a painted-on face.
function alphaAt(x, y) {
  const bone = Math.max(edge(inEllipse(x, y, SKULL)), edge(inBlock(x, y, JAW)));
  if (bone <= 0) return 0;
  let hole = 0;
  for (const eye of EYES) hole = Math.max(hole, edge(inEllipse(x, y, eye)));
  hole = Math.max(hole, edge(inEllipse(x, y, NOSE)));
  if (y >= MOUTH.top && y <= MOUTH.bottom && Math.abs(x - SKULL.x) <= MOUTH.half) {
    // Each gap is a soft vertical slot, and the row the teeth start and end
    // on fades so the mouth does not cut the chin off square.
    const ends = Math.min(edge(y - MOUTH.top), edge(MOUTH.bottom - y));
    for (const tooth of TEETH) {
      hole = Math.max(hole, Math.min(ends, edge(GAP - Math.abs(x - (SKULL.x + tooth)))));
    }
  }
  return clamp(bone * (1 - hole));
}

// An uncompressed 32 bit TGA, BGRA, written out last row first with the
// descriptor's origin bit clear (0x08): the same way round as every other
// texture this addon ships, which is the only row order proved on this client
// (Tools/GenerateWave.mjs explains why at length). The skull is close to
// symmetric top to bottom anyway, so the wrong way up would barely show,
// which is exactly why it is worth checking rather than assuming.
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
      // Each pixel is sampled at its own middle, so a shape centred on 32 in
      // a 64 wide picture comes out the same on both sides (pixel 0's middle
      // is .5 and pixel 63's is 63.5, which stand the same distance out).
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
check('every pixel is white, so the addon tints it', `${file[18]} ${file[19]} ${file[20]}`, '255 255 255');

// The shape itself, read back out of the file.
check('the forehead is solid bone', alpha(32, 12), 255);
check('both eye sockets are holes', `${alpha(23, 26)} ${alpha(41, 26)}`, '0 0');
check('the bone between them is solid', alpha(32, 24), 255);
check('the nose is a hole', alpha(32, 38), 0);
check('the chin is solid', alpha(32, 54), 255);
// Pixel 24's middle is 24.5, which is the left gap's own middle; pixel 27's
// is 27.5, which is the tooth between that gap and the next.
check('a tooth gap is a hole and the tooth beside it is not', `${alpha(24, 50)} ${alpha(27, 50)}`, '0 255');
check('the corners are clear', `${alpha(0, 0)} ${alpha(63, 0)} ${alpha(0, 63)} ${alpha(63, 63)}`, '0 0 0 0');
check('and the very edges all round are clear',
  `${alpha(32, 0)} ${alpha(32, 63)} ${alpha(0, 32)} ${alpha(63, 32)}`, '0 0 0 0');
// Left and right are the same picture, which is what makes it read as a face.
let lopsided = 0;
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W / 2; x++) {
    if (Math.abs(alpha(x, y) - alpha(W - 1 - x, y)) > 1) lopsided++;
  }
}
check('it is the same on both sides', lopsided, 0);
// Enough of the square is bone to read as a skull, and not so much that it is
// a white block with holes in it. A skull is mostly its own holes: the two
// sockets, the nose and the gaps take about a fifth of the shape back out
// again, and the corners of the square are always clear, so about a quarter
// of it being bone is what a drawn skull comes to. Anything under a fifth is
// too faint to read at a 58 pixel portrait and anything over a half is a
// block with a face scratched into it.
let bone = 0;
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) bone += alpha(x, y) / 255;
}
const share = bone / (W * H);
check('between a fifth and a half of the square is bone', share > .2 && share < .5, true);
console.log(`${failed === 0 ? 'all checks passed' : `${failed} FAILED`} (bone ${(share * 100).toFixed(1)}% of the square)`);
process.exit(failed === 0 ? 0 : 1);
