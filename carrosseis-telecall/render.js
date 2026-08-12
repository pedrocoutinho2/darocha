/* ============================================================
   render.js — renderiza os carrosséis Telecall com Playwright.

   Uso:
     node render.js --post=1 --ratio=4x5
     node render.js --post=all --ratio=all
     node render.js --post=1 --images=real          (usa os JPGs reais)
     node render.js --post=1 --contact=false         (pula o contact sheet)

   Saída:
     output/post-1/4x5/slide-01.png ...
     output/preview-post-1.png       (contact sheet, só no 4x5)

   Renderiza em deviceScaleFactor:2 (supersampling) e faz downscale
   para 1080 de largura via canvas, para bordas e tipografia nítidas.
   ============================================================ */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const CHROME =
  process.env.PW_CHROMIUM ||
  '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

const POSTS = {
  '1': { dir: 'post-1-vertical-saude', slug: 'post-1', title: 'Vertical Saúde' },
  '2': { dir: 'post-2-telefonia-corporativa', slug: 'post-2', title: 'Telefonia Corporativa' },
};
const RATIOS = { '4x5': { w: 1080, h: 1350 }, '1x1': { w: 1080, h: 1080 } };

function arg(name, def) {
  const p = process.argv.find((a) => a.startsWith(`--${name}=`));
  return p ? p.split('=').slice(1).join('=') : def;
}

async function downscale(helper, buf, w, h) {
  const dataUrl = 'data:image/png;base64,' + buf.toString('base64');
  const out = await helper.evaluate(
    async ({ dataUrl, w, h }) => {
      const img = new Image();
      img.src = dataUrl;
      await img.decode();
      const c = document.createElement('canvas');
      c.width = w;
      c.height = h;
      const ctx = c.getContext('2d');
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(img, 0, 0, w, h);
      return c.toDataURL('image/png');
    },
    { dataUrl, w, h }
  );
  return Buffer.from(out.split(',')[1], 'base64');
}

async function contactSheet(helper, buffers, outPath) {
  const items = buffers
    .map(
      (buf, i) =>
        `<figure><img src="data:image/png;base64,${buf.toString('base64')}"><figcaption>${String(i + 1).padStart(2, '0')}</figcaption></figure>`
    )
    .join('');
  await helper.setContent(`<!DOCTYPE html><html><head><style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:#0e1622;padding:56px 48px;display:flex;gap:28px;align-items:flex-start;
         font-family:system-ui,sans-serif;width:max-content}
    figure{display:flex;flex-direction:column;gap:14px;align-items:center}
    img{height:600px;width:auto;border-radius:10px;box-shadow:0 14px 40px rgba(0,0,0,.45)}
    figcaption{color:#9fb0c4;font-size:22px;letter-spacing:3px}
  </style></head><body>${items}</body></html>`);
  await helper.evaluate(() =>
    Promise.all([...document.images].map((im) => im.decode().catch(() => {})))
  );
  const box = await helper.evaluate(() => {
    const b = document.body;
    return { w: b.scrollWidth, h: b.scrollHeight };
  });
  await helper.setViewportSize({ width: box.w, height: box.h });
  await helper.screenshot({ path: outPath, clip: { x: 0, y: 0, width: box.w, height: box.h } });
}

async function renderPost(browser, postKey, ratioKey, images, doContact) {
  const post = POSTS[postKey];
  const { w, h } = RATIOS[ratioKey];
  const ctx = await browser.newContext({
    viewport: { width: w, height: h },
    deviceScaleFactor: 2,
  });
  await ctx.addInitScript(
    ([ratio, imgs]) => {
      document.documentElement.setAttribute('data-ratio', ratio);
      document.documentElement.setAttribute('data-images', imgs);
    },
    [ratioKey, images]
  );
  const page = await ctx.newPage();
  const url = 'file://' + path.resolve(__dirname, post.dir, 'index.html');
  await page.goto(url, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);

  const sections = await page.$$('section.card');
  const outDir = path.resolve(__dirname, 'output', post.slug, ratioKey);
  fs.mkdirSync(outDir, { recursive: true });

  const helper = await ctx.newPage();
  await helper.setContent('<!DOCTYPE html><body></body>');

  const buffers = [];
  for (let i = 0; i < sections.length; i++) {
    const buf = await sections[i].screenshot({ type: 'png' });
    const small = await downscale(helper, buf, w, h);
    const name = `slide-${String(i + 1).padStart(2, '0')}.png`;
    fs.writeFileSync(path.join(outDir, name), small);
    buffers.push(small);
  }
  console.log(`  ${post.slug} ${ratioKey}: ${buffers.length} slides -> ${path.relative(__dirname, outDir)}`);

  if (doContact && ratioKey === '4x5') {
    const preview = path.resolve(__dirname, 'output', `preview-${post.slug}.png`);
    await contactSheet(helper, buffers, preview);
    console.log(`  contact sheet -> ${path.relative(__dirname, preview)}`);
  }

  await ctx.close();
}

(async () => {
  const postArg = arg('post', '1');
  const ratioArg = arg('ratio', '4x5');
  const images = arg('images', 'placeholder');
  const doContact = arg('contact', 'true') !== 'false';

  const postKeys = postArg === 'all' ? ['1', '2'] : [postArg];
  const ratioKeys = ratioArg === 'all' ? ['4x5', '1x1'] : [ratioArg];

  console.log(`Renderizando posts=[${postKeys}] ratios=[${ratioKeys}] images=${images}`);
  const browser = await chromium.launch({ executablePath: CHROME });
  try {
    for (const p of postKeys) {
      for (const r of ratioKeys) {
        await renderPost(browser, p, r, images, doContact);
      }
    }
  } finally {
    await browser.close();
  }
  console.log('OK');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
