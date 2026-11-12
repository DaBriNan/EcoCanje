// E03 desde la interfaz: CRUD de materiales y recompensas, flujo de entrega y canje, con dos roles.
// Uso (ver tests/interfaz/correr.sh): BASE=https://dev.ecocanje.test:8444 SEED_PW=... OUT=/out node e03.mjs
import { chromium } from 'playwright';

const BASE = process.env.BASE, OUT = process.env.OUT || '/out';
const marca = `UI-${Date.now().toString(36)}`;
let ok = 0, fallas = 0, n = 0;

async function paso(nombre, fn) {
  try { await fn(); ok++; console.log(`OK    ${nombre}`); }
  catch (e) { fallas++; console.log(`FALLA ${nombre}: ${String(e.message).split('\n')[0]}`); }
}
const captura = (p, nombre) => p.screenshot({ path: `${OUT}/${String(++n).padStart(2, '0')}-${nombre}.png`, fullPage: true });
const avisoOk = async (p, texto) => {
  const a = p.locator('.aviso.ok').filter({ hasText: texto });
  await a.waitFor({ timeout: 10000 });
};
const entrar = async (p, email, pw) => {
  await p.goto(BASE + '/');
  await p.getByLabel('Correo').fill(email);
  await p.getByLabel('Contraseña').fill(pw);
  await p.getByRole('button', { name: 'Entrar' }).click();
};

const navegador = await chromium.launch();
const ctxOp = await navegador.newContext({ ignoreHTTPSErrors: true, timezoneId: 'America/Mexico_City', locale: 'es-MX', viewport: { width: 1280, height: 900 } });
const ctxCi = await navegador.newContext({ ignoreHTTPSErrors: true, timezoneId: 'America/Mexico_City', locale: 'es-MX', viewport: { width: 390, height: 844 } }); // celular
const op = await ctxOp.newPage(), ci = await ctxCi.newPage();
const errores = [];
for (const p of [op, ci]) p.on('pageerror', (e) => errores.push(e.message));

console.log(`marca de la prueba: ${marca}`);

// --- Autenticación ---
await paso('contraseña incorrecta muestra error', async () => {
  await entrar(op, 'operador@ecocanje.test', 'incorrecta-123');
  await op.locator('.aviso.error').filter({ hasText: /Credenciales/ }).waitFor({ timeout: 10000 });
  await captura(op, 'login-rechazado');
});
await paso('operador inicia sesión', async () => {
  await entrar(op, 'operador@ecocanje.test', process.env.SEED_PW);
  await op.getByText('operador@ecocanje.test · operador').waitFor();
});

// --- CRUD de materiales ---
const mat = `Material ${marca}`;
await paso('validación en el cliente: el navegador bloquea tarifa 0', async () => {
  await op.getByRole('button', { name: 'Materiales' }).click();
  await op.getByLabel('Nombre').fill(mat);
  await op.getByLabel('Puntos por kg').fill('0');
  let enviada = false;
  const vigila = (r) => { if (r.url().endsWith('/api/materiales') && r.method() === 'POST') enviada = true; };
  op.on('request', vigila);
  await op.getByRole('button', { name: 'Crear' }).click();
  await op.waitForTimeout(800);
  op.off('request', vigila);
  const valido = await op.getByLabel('Puntos por kg').evaluate((e) => e.validity.valid);
  if (valido || enviada) throw new Error(`campo valido=${valido}, solicitud enviada=${enviada}`);
  await captura(op, 'validacion-cliente');
});
await paso('validación en el servidor: la API rechaza tarifa 0 aunque se evite la interfaz (422)', async () => {
  const r = await op.evaluate(async (nombre) => {
    const t = JSON.parse(sessionStorage.getItem('ecocanje.sesion')).token;
    const x = await fetch('/api/materiales', { method: 'POST', headers: { Authorization: `Bearer ${t}`, Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({ nombre, puntos_por_kg: 0 }) });
    return { status: x.status, campos: Object.keys((await x.json()).errors || {}) };
  }, mat);
  if (r.status !== 422 || !r.campos.includes('puntos_por_kg')) throw new Error(JSON.stringify(r));
});
await paso('crear material', async () => {
  await op.getByLabel('Puntos por kg').fill('7');
  await op.getByRole('button', { name: 'Crear' }).click();
  await avisoOk(op, `Material "${mat}" creado`);
  await op.locator('li').filter({ hasText: mat }).filter({ hasText: '7 pts/kg' }).waitFor();
});
await paso('editar nombre y tarifa del material', async () => {
  const fila = op.locator('li').filter({ hasText: mat });
  await fila.getByRole('button', { name: 'Editar' }).click();
  const ed = op.locator('li').filter({ has: op.getByRole('button', { name: 'Guardar' }) });
  await ed.getByLabel('Nombre').fill(`${mat} v2`);
  await ed.getByLabel('Puntos por kg').fill('9');
  await ed.getByRole('button', { name: 'Guardar' }).click();
  await avisoOk(op, 'actualizado');
  await op.locator('li').filter({ hasText: `${mat} v2` }).filter({ hasText: '9 pts/kg' }).waitFor();
  await captura(op, 'material-editado');
});
await paso('guardar ficha del material en MongoDB', async () => {
  await op.locator('li').filter({ hasText: `${mat} v2` }).getByRole('button', { name: 'Ficha' }).click();
  await op.getByLabel(/Atributos/).fill('color=gris\norigen=prueba_ui');
  await op.getByRole('button', { name: 'Guardar ficha' }).click();
  await avisoOk(op, 'guardada en MongoDB');
});

// --- CRUD de recompensas ---
const rec = `Vale ${marca}`;
await paso('crear recompensa', async () => {
  await op.getByRole('button', { name: 'Recompensas' }).click();
  await op.getByLabel('Nombre').fill(rec);
  await op.getByLabel('Tipo').selectOption('vale_despensa');
  await op.getByLabel('Costo (puntos)').fill('20');
  await op.getByLabel('Stock').fill('3');
  await op.getByRole('button', { name: 'Crear' }).click();
  await avisoOk(op, `Recompensa "${rec}" creada`);
});
await paso('editar stock de la recompensa', async () => {
  await op.locator('li').filter({ hasText: rec }).getByRole('button', { name: 'Editar' }).click();
  await op.getByLabel('Stock').fill('5');
  await op.getByRole('button', { name: 'Guardar cambios' }).click();
  await avisoOk(op, 'actualizada');
  await op.locator('li').filter({ hasText: rec }).filter({ hasText: 'stock 5' }).waitFor();
});

// --- Ciudadano se registra (vista de celular) ---
const correo = `${marca.toLowerCase()}@ecocanje.test`;
const pwCi = `Clave-${marca}-${Math.random().toString(36).slice(2, 10)}`;
let idCi;
await paso('ciudadano se registra desde la interfaz', async () => {
  await ci.goto(BASE + '/');
  await ci.getByRole('button', { name: '¿No tienes cuenta? Regístrate' }).click();
  await ci.getByLabel('Nombre').fill(`Ciudadano ${marca}`);
  await ci.getByLabel('Correo').fill(correo);
  await ci.getByLabel('Contraseña').fill(pwCi);
  await ci.getByRole('button', { name: 'Registrarme' }).click();
  await ci.getByText(`${correo} · ciudadano`).waitFor();
  idCi = await ci.evaluate(async () => {
    const t = JSON.parse(sessionStorage.getItem('ecocanje.sesion')).token;
    return (await (await fetch('/api/yo', { headers: { Authorization: `Bearer ${t}`, Accept: 'application/json' } })).json()).id;
  });
  if (!idCi) throw new Error('sin id');
  console.log(`      ciudadano id=${idCi}`);
});

// --- Flujo de entrega (operador) ---
await paso('el ciudadano ve su número y cómo ganar puntos', async () => {
  await ci.getByText(`Tu número de ciudadano: ${idCi}`).waitFor();
  await ci.getByText('Aún no tienes puntos').waitFor();
  await ci.locator('.faltan').first().waitFor();
});
await paso('registrar entrega de 4 kg del material nuevo', async () => {
  await op.getByRole('button', { name: 'Entregas' }).click();
  await op.getByLabel('Número de ciudadano').fill(String(idCi));
  await op.getByLabel('Material 1').selectOption({ label: `${mat} v2 (9 pts/kg)` });
  await op.getByLabel('Peso declarado 1 (kg)').fill('4');
  await op.getByText('Puntos estimados: 36').waitFor();
  await op.getByRole('button', { name: 'Registrar entrega' }).click();
  await avisoOk(op, 'registrada');
});
await paso('búsqueda de entregas por id de ciudadano', async () => {
  await op.getByLabel('Buscar por id de ciudadano').fill(String(idCi));
  // Espera a que llegue la lista filtrada: solo entregas de ese ciudadano (y al menos una)
  const otros = () => op.locator('li.bloque').filter({ hasNotText: `ciudadano ${idCi} ` }).count();
  const propias = () => op.locator('li.bloque').filter({ hasText: `ciudadano ${idCi} ` }).count();
  const fin = Date.now() + 10000;
  while ((await otros()) > 0 || (await propias()) === 0) {
    if (Date.now() > fin) throw new Error(`${await otros()} entregas de otros ciudadanos en el resultado`);
    await op.waitForTimeout(200);
  }
});
const filaEntrega = () => op.locator('li.bloque').filter({ hasText: `ciudadano ${idCi}` }).first();
await paso('pesar (5 kg reales), validar y acreditar', async () => {
  await filaEntrega().getByLabel(/Peso real/).fill('5');
  await filaEntrega().getByRole('cell', { name: `${mat} v2` }).waitFor();
  await filaEntrega().getByRole('button', { name: 'Confirmar pesaje' }).click();
  await avisoOk(op, 'pesada');
  await filaEntrega().getByRole('button', { name: 'Validar' }).click();
  await avisoOk(op, 'validada');
  await filaEntrega().getByRole('button', { name: 'Acreditar puntos' }).click();
  await avisoOk(op, 'acreditada');
  await filaEntrega().getByText('acreditada').waitFor();
  await captura(op, 'entrega-acreditada');
});

// --- Ciudadano ve su saldo y canjea ---
await paso('ciudadano ve 45 puntos (5 kg x 9)', async () => {
  await ci.reload();
  await ci.locator('.cifras div').first().filter({ hasText: '45' }).waitFor({ timeout: 10000 });
});
await paso('canje con confirmación', async () => {
  const fila = ci.locator('li').filter({ hasText: rec });
  await fila.getByRole('button', { name: /Canjear/ }).click();
  await fila.getByRole('button', { name: /Confirmar 20 pts/ }).click();
  await avisoOk(ci, 'Canje solicitado');
  await ci.locator('.cifras div').first().filter({ hasText: '25' }).waitFor({ timeout: 10000 });
  await captura(ci, 'ciudadano-canje-celular');
});

// --- Operador aprueba y entrega el canje ---
await paso('operador aprueba y entrega el canje', async () => {
  await op.getByRole('button', { name: 'Canjes' }).click();
  const fila = op.locator('tr').filter({ hasText: String(idCi) }).first();
  await fila.getByRole('button', { name: 'Aprobar' }).click();
  await avisoOk(op, 'aprobado');
  await op.locator('tr').filter({ hasText: String(idCi) }).first().getByRole('button', { name: 'Entregar' }).click();
  await avisoOk(op, 'entregado');
});
await paso('ciudadano ve el canje entregado y su historial en MongoDB', async () => {
  await ci.reload();
  await ci.locator('tr').filter({ hasText: 'entregado' }).first().waitFor({ timeout: 10000 });
  await ci.locator('section').filter({ hasText: 'Historial de movimientos' }).locator('li').first().waitFor({ timeout: 30000 });
});

// --- Bajas lógicas ---
await paso('baja lógica de recompensa con confirmación', async () => {
  await op.getByRole('button', { name: 'Recompensas' }).click();
  const fila = op.locator('li').filter({ hasText: rec });
  await fila.getByRole('button', { name: 'Dar de baja' }).click();
  await fila.getByRole('button', { name: 'Confirmar baja' }).click();
  await avisoOk(op, 'dada de baja');
  await op.locator('li').filter({ hasText: rec }).waitFor({ state: 'detached' });
});
await paso('baja lógica de material con confirmación', async () => {
  await op.getByRole('button', { name: 'Materiales' }).click();
  const fila = op.locator('li').filter({ hasText: `${mat} v2` });
  await fila.getByRole('button', { name: 'Dar de baja' }).click();
  await fila.getByRole('button', { name: 'Confirmar baja' }).click();
  await avisoOk(op, 'dado de baja');
  await captura(op, 'material-baja');
});
await paso('sesión expirada: token inválido devuelve al login con aviso', async () => {
  await ci.evaluate(() => { const s = JSON.parse(sessionStorage.getItem('ecocanje.sesion')); s.token = s.token.split('|')[0] + '|' + 'x'.repeat(40); /* mismo id, secreto incorrecto */ sessionStorage.setItem('ecocanje.sesion', JSON.stringify(s)); });
  await ci.reload();
  await ci.locator('.aviso.error').filter({ hasText: 'Tu sesión expiró' }).waitFor({ timeout: 10000 });
  await ci.getByRole('button', { name: 'Entrar' }).waitFor();
  await captura(ci, 'sesion-expirada');
});
await paso('volver a entrar tras la expiración', async () => {
  await ci.getByLabel('Correo').fill(correo);
  await ci.getByLabel('Contraseña').fill(pwCi);
  await ci.getByRole('button', { name: 'Entrar' }).click();
  await ci.getByText(`${correo} · ciudadano`).waitFor();
});
await paso('cerrar sesión', async () => {
  await ci.getByRole('button', { name: 'Salir' }).click();
  await ci.getByRole('button', { name: 'Entrar' }).waitFor();
});
await paso('sin errores de JavaScript en las páginas', async () => { if (errores.length) throw new Error(errores.join(' | ')); });

await navegador.close();
console.log(`Resultado: ${ok} correctas, ${fallas} fallidas (capturas en ${OUT})`);
process.exit(fallas ? 1 : 0);
