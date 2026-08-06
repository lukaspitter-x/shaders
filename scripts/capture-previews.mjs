import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';

const repoRoot = path.resolve(import.meta.dirname, '..');
const appRoot = path.join(repoRoot, 'app');
const require = createRequire(path.join(appRoot, 'package.json'));
const { chromium } = require('playwright');
const outDir = path.join(repoRoot, 'docs', 'previews');
const sessionsPath = path.join(appRoot, 'src', 'data', 'sessions.json');
const baseUrl = process.env.PREVIEW_BASE_URL ?? 'http://localhost:5194/';

const shots = [
  ['thermal', 'xzdjef1x76n77', 'thermal-default', 0.9],
  ['thermal', '1q412da8jnokt', 'thermal-shadow', 1.4],
  ['thermal', 's4ar521db2fe1', 'thermal-fav-1', 2.0],
  ['thermal', '93kkiy17jnzau', 'thermal-fav-2-wip', 3.1],
  ['thermal-2', 'xzdjef1x76n77t2', 'thermal-2-default', 0.8],
  ['thermal-2', 's4ar521db2fe1t2', 'thermal-2-fav-1', 1.6],
  ['thermal-2', 'k8m9ta1t9p3zs', 'thermal-2-video-match', 2.2],
  ['thermal-2', '19u7htw19dzwxc', 'thermal-2-fav-2', 2.8],
  ['thermal-2', '1024rz0irermz', 'thermal-2-fog', 3.5],
  ['tube', '1auju9411a1wbt', 'tube-default', 0.7],
  ['tube', 'ttbvk0lgpeni', 'tube-fav-1', 1.7],
  ['tube', 'r2p7zu91v4tz', 'tube-closer', 2.7],
];

async function main() {
  const sessions = JSON.parse(await fs.readFile(sessionsPath, 'utf8'));
  await fs.mkdir(outDir, { recursive: true });

  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: { width: 1280, height: 860 },
    deviceScaleFactor: 1,
  });

  page.on('console', (message) => {
    if (message.type() === 'error') console.error(`[browser] ${message.text()}`);
  });

  for (const [shaderId, presetId, slug, seconds] of shots) {
    const patchedSessions = structuredClone(sessions);
    patchedSessions[shaderId].activePresetId = presetId;

    await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });
    await page.evaluate(
      ({ selected, store }) => {
        localStorage.setItem('shaders:selected', JSON.stringify(selected));
        localStorage.setItem('shaders:running', JSON.stringify(true));
        localStorage.setItem('shaders:fpsVisible', JSON.stringify(false));
        window.__previewStore = store;
      },
      { selected: shaderId, store: patchedSessions },
    );
    await page.route('**/api/sessions', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(patchedSessions),
      });
    });
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForSelector('main canvas');
    await page.waitForTimeout(Math.max(300, Math.round(seconds * 1000)));

    const canvas = page.locator('main canvas').first();
    await canvas.screenshot({ path: path.join(outDir, `${slug}.png`) });
    await page.unroute('**/api/sessions');
  }

  await browser.close();
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
