// Prueba de humo de solo lectura para prod: no crea ciudadanos, entregas, canjes ni catálogo.
// Lo único que escribe es el token de sesión del operador, que se borra al cerrar sesión.
// Uso: igual que e03.mjs (tests/interfaz/correr.sh elige esta prueba en prod).
import { chromium } from 'playwright';

const BASE = process.env.BASE, OUT = process.env.OUT || '/out', VERSION = process.env.VERSION_ESPERADA || '';
let ok = 0, fallas = 0;
async function paso(nombre, fn) {
  try { await fn(); ok++; console.log(`OK    ${nombre}`); }
  catch (e) { fallas++; console.log(`FALLA ${nombre}: ${String(e.message).split('\n')[0]}`); }
}

const navegador = await chromium.launch();
const ctx = await navegador.newContext({ ignoreHTTPSErrors: true, timezoneId: 'America/Mexico_City', locale: 'es-MX', viewport: { width: 1280, height: 900 } });
const p = await ctx.newPage();
const errores = []; p.on('pageerror', (e) => errores.push(e.message));
const escrituras = [];
p.on('request', (r) => {
  const u = new URL(r.url());
  if (r.method() !== 'GET' && !['/api/login', '/api/logout'].includes(u.pathname)) escrituras.push(`${r.method()} ${u.pathname}`);
});

await paso('la interfaz carga y muestra su versión', async () => {
  await p.goto(BASE + '/');
  await p.getByRole('button', { name: 'Entrar' }).waitFor();
  const pie = await p.locator('footer').innerText();
  if (VERSION && !pie.includes(VERSION)) throw new Error(`pie "${pie}" sin la versión ${VERSION}`);
  console.log(`      ${pie}`);
});
await paso('contraseña incorrecta se rechaza', async () => {
  await p.getByLabel('Correo').fill('operador@ecocanje.test');
  await p.getByLabel('Contraseña').fill('incorrecta-123');
  await p.getByRole('button', { name: 'Entrar' }).click();
  await p.locator('.aviso.error').filter({ hasText: /Credenciales/ }).waitFor({ timeout: 10000 });
});
await paso('el operador entra y ve su rol', async () => {
  await p.getByLabel('Contraseña').fill(process.env.SEED_PW);
  await p.getByRole('button', { name: 'Entrar' }).click();
  await p.getByText('operador@ecocanje.test · operador').waitFor();
});
for (const [pestana, senal] of [['Entregas', 'li.bloque'], ['Canjes', 'table tbody tr'], ['Materiales', 'li.bloque'], ['Recompensas', 'li.bloque'], ['Reporte', '.cifras']]) {
  await paso(`pestaña ${pestana} carga datos`, async () => {
    await p.getByRole('button', { name: pestana, exact: true }).click();
    await p.locator(senal).first().waitFor({ timeout: 15000 });
  });
}
await p.screenshot({ path: `${OUT}/humo-operador.png`, fullPage: true });
await paso('cerrar sesión', async () => {
  await p.getByRole('button', { name: 'Salir' }).click();
  await p.getByRole('button', { name: 'Entrar' }).waitFor();
});
await paso('sin escrituras de negocio ni errores de JavaScript', async () => {
  if (escrituras.length) throw new Error(`escrituras: ${escrituras.join(', ')}`);
  if (errores.length) throw new Error(errores.join(' | '));
});
await navegador.close();
console.log(`Resultado: ${ok} correctas, ${fallas} fallidas (capturas en ${OUT})`);
process.exit(fallas ? 1 : 0);
