// Gera os ícones do PWA a partir de um SVG da marca (estrela dourada sobre verde-floresta).
// Uso: npm run icons
import sharp from 'sharp'
import { mkdir, writeFile } from 'node:fs/promises'

const FOREST = '#173d2c'
const GOLD = '#c5a15b'

// Estrela de quatro pontas (✦) desenhada com curvas, centrada em (256,256).
const star = (r) => {
  const c = 256
  const k = r * 0.2
  return `M${c} ${c - r} C${c + k * 0.55} ${c - k * 1.6} ${c + k * 1.6} ${c - k * 0.55} ${c + r} ${c} C${c + k * 1.6} ${c + k * 0.55} ${c + k * 0.55} ${c + k * 1.6} ${c} ${c + r} C${c - k * 0.55} ${c + k * 1.6} ${c - k * 1.6} ${c + k * 0.55} ${c - r} ${c} C${c - k * 1.6} ${c - k * 0.55} ${c - k * 0.55} ${c - k * 1.6} ${c} ${c - r} Z`
}

const svg = ({ rounded, frame = true, starR = 118 }) => `
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <defs>
    <radialGradient id="g" cx="50%" cy="38%" r="75%">
      <stop offset="0" stop-color="#24543d"/><stop offset="1" stop-color="${FOREST}"/>
    </radialGradient>
  </defs>
  <rect width="512" height="512" rx="${rounded ? 112 : 0}" fill="url(#g)"/>
  ${frame ? `<rect x="92" y="92" width="328" height="328" rx="92" fill="none" stroke="${GOLD}" stroke-width="9" opacity=".95"/>` : ''}
  <path d="${star(starR)}" fill="${GOLD}"/>
  <path d="${star(34).replaceAll('256', '0')}" fill="${GOLD}" opacity=".0"/>
</svg>`

const png = (opts, size) => sharp(Buffer.from(svg(opts))).resize(size, size).png({ compressionLevel: 9 }).toBuffer()

// ICO mínimo contendo um PNG de 32px.
const ico = (pngBuf, size) => {
  const header = Buffer.alloc(22)
  header.writeUInt16LE(0, 0); header.writeUInt16LE(1, 2); header.writeUInt16LE(1, 4)
  header.writeUInt8(size, 6); header.writeUInt8(size, 7); header.writeUInt8(0, 8); header.writeUInt8(0, 9)
  header.writeUInt16LE(1, 10); header.writeUInt16LE(32, 12)
  header.writeUInt32LE(pngBuf.length, 14); header.writeUInt32LE(22, 18)
  return Buffer.concat([header, pngBuf])
}

await mkdir('public/icons', { recursive: true })
await writeFile('public/icons/icon-192.png', await png({ rounded: true }, 192))
await writeFile('public/icons/icon-512.png', await png({ rounded: true }, 512))
// maskable: fundo sem cantos arredondados e marca dentro da zona segura (80%)
await writeFile('public/icons/maskable-512.png', await png({ rounded: false, frame: false, starR: 104 }, 512))
await writeFile('src/app/apple-icon.png', await png({ rounded: false }, 180))
await writeFile('src/app/icon.png', await png({ rounded: true }, 192))
await writeFile('src/app/favicon.ico', ico(await png({ rounded: true, frame: false, starR: 150 }, 32), 32))
await writeFile('public/icons/brand.svg', svg({ rounded: true }).trim())
console.log('Ícones gerados em public/icons e src/app')
