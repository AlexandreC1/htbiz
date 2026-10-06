const sharp = require('sharp');

// Generates the HTBIZ brand mark. Run with: node generate_icon.js
// Then: dart run flutter_launcher_icons && dart run flutter_native_splash:create
//
// Flat, two colours, no gradients or effects. The geometry is shared with the
// HTBizLogo widget (lib/widgets/htbiz_logo.dart), so keep the ratios in sync.

const size = 1024;

const navy = '#0E3A5C';
const gold = '#E8A838';

// H monogram, as fractions of the canvas. The whole H fits in a 0.46 x 0.42
// box, inside the 66% safe zone Android uses for adaptive icons and the
// Android 12 splash circle.
const boxW = size * 0.46;
const box = size * 0.42; // height
const stem = size * 0.104; // stem width
const bar = size * 0.09; // crossbar height
const gap = size * 0.016; // the crossbar floats free of the stems
const corner = size * 0.018; // a slight softening, not a pill
const left = (size - boxW) / 2;
const top = (size - box) / 2;
// Optical centre: a crossbar at the exact middle reads as sitting low.
const barTop = size / 2 - bar / 2 - size * 0.008;

const monogram = `
  <rect x="${left}" y="${top}" width="${stem}" height="${box}" rx="${corner}" fill="${gold}"/>
  <rect x="${left + boxW - stem}" y="${top}" width="${stem}" height="${box}" rx="${corner}" fill="${gold}"/>
  <rect x="${left + stem + gap}" y="${barTop}" width="${boxW - 2 * (stem + gap)}" height="${bar}" rx="${corner}" fill="${gold}"/>
`;

// Full-bleed square: iOS, legacy Android and the in-app splash. The OS applies
// its own corner mask, so the artwork itself has square corners.
const svgFull = `
<svg width="${size}" height="${size}" xmlns="http://www.w3.org/2000/svg">
  <rect width="${size}" height="${size}" fill="${navy}"/>
  ${monogram}
</svg>`;

// Transparent foreground: Android adaptive icon and native splash images.
const svgForeground = `
<svg width="${size}" height="${size}" xmlns="http://www.w3.org/2000/svg">
  ${monogram}
</svg>`;

const svgBackground = `
<svg width="${size}" height="${size}" xmlns="http://www.w3.org/2000/svg">
  <rect width="${size}" height="${size}" fill="${navy}"/>
</svg>`;

async function main() {
  await sharp(Buffer.from(svgFull)).png().toFile('assets/icon/app_icon.png');
  await sharp(Buffer.from(svgForeground)).png().toFile('assets/icon/app_icon_foreground.png');
  await sharp(Buffer.from(svgBackground)).png().toFile('assets/icon/app_icon_background.png');
  console.log('Icons written to assets/icon/');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
