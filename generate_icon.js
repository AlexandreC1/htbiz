const sharp = require('sharp');

// Generate HTBIZ app icon - Haiti-inspired warm Caribbean palette
// Deep ocean blue + golden amber, with a stylized "H" storefront motif

const size = 1024;
const r = size / 2;

// Create SVG icon
const svg = `
<svg width="${size}" height="${size}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <!-- Background gradient: deep Caribbean blue -->
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1B4F72"/>
      <stop offset="100%" style="stop-color:#0E3A5C"/>
    </linearGradient>
    <!-- Gold accent gradient -->
    <linearGradient id="gold" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#F0B74A"/>
      <stop offset="100%" style="stop-color:#E09830"/>
    </linearGradient>
    <!-- Subtle warm glow -->
    <radialGradient id="glow" cx="50%" cy="40%" r="50%">
      <stop offset="0%" style="stop-color:#1E5F8A;stop-opacity:0.6"/>
      <stop offset="100%" style="stop-color:#0E3A5C;stop-opacity:0"/>
    </radialGradient>
  </defs>

  <!-- Rounded square background -->
  <rect width="${size}" height="${size}" rx="220" ry="220" fill="url(#bg)"/>
  <rect width="${size}" height="${size}" rx="220" ry="220" fill="url(#glow)"/>

  <!-- Stylized storefront / building shape -->
  <!-- Roof / triangle top -->
  <polygon points="512,180 280,380 744,380" fill="url(#gold)" opacity="0.95"/>

  <!-- Building body -->
  <rect x="310" y="380" width="404" height="340" rx="12" fill="white" opacity="0.95"/>

  <!-- Door / entrance -->
  <rect x="440" y="500" width="144" height="220" rx="72" fill="url(#bg)" opacity="0.9"/>

  <!-- Windows -->
  <rect x="345" y="420" width="70" height="60" rx="8" fill="url(#bg)" opacity="0.7"/>
  <rect x="609" y="420" width="70" height="60" rx="8" fill="url(#bg)" opacity="0.7"/>

  <!-- Gold accent line at base -->
  <rect x="280" y="710" width="464" height="12" rx="6" fill="url(#gold)"/>

  <!-- Small Haitian-inspired sun rays above roof (subtle) -->
  <line x1="512" y1="130" x2="512" y2="165" stroke="#F0B74A" stroke-width="6" stroke-linecap="round" opacity="0.8"/>
  <line x1="460" y1="140" x2="475" y2="170" stroke="#F0B74A" stroke-width="5" stroke-linecap="round" opacity="0.6"/>
  <line x1="564" y1="140" x2="549" y2="170" stroke="#F0B74A" stroke-width="5" stroke-linecap="round" opacity="0.6"/>
  <line x1="415" y1="160" x2="440" y2="185" stroke="#F0B74A" stroke-width="4" stroke-linecap="round" opacity="0.4"/>
  <line x1="609" y1="160" x2="584" y2="185" stroke="#F0B74A" stroke-width="4" stroke-linecap="round" opacity="0.4"/>

  <!-- HTBIZ text -->
  <text x="512" y="830" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-weight="bold" font-size="88" fill="white" letter-spacing="8" opacity="0.95">HTBIZ</text>
</svg>
`;

async function generate() {
  const iconBuffer = Buffer.from(svg);

  // Generate main icon (1024x1024)
  await sharp(iconBuffer)
    .resize(1024, 1024)
    .png()
    .toFile('assets/icon/app_icon.png');

  // Generate foreground for adaptive icon (with padding)
  await sharp(iconBuffer)
    .resize(1024, 1024)
    .png()
    .toFile('assets/icon/app_icon_foreground.png');

  // Generate a simple background
  const bgSvg = `
  <svg width="1024" height="1024" xmlns="http://www.w3.org/2000/svg">
    <rect width="1024" height="1024" fill="#1B4F72"/>
  </svg>`;

  await sharp(Buffer.from(bgSvg))
    .resize(1024, 1024)
    .png()
    .toFile('assets/icon/app_icon_background.png');

  console.log('Icons generated successfully!');
}

generate().catch(console.error);
