import { copyFile, mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';

const require = createRequire(import.meta.url);
const workerPath = require.resolve('pdfjs-dist/legacy/build/pdf.worker.mjs');
const publicDir = resolve(process.cwd(), 'public');
await mkdir(publicDir, { recursive: true });
await copyFile(workerPath, resolve(publicDir, 'pdf.worker.mjs'));
console.log('PDF.js worker copied to public/pdf.worker.mjs');
