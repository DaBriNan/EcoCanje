// Escenario E06: ciudadano consulta catalogo, saldo (PostgreSQL) e historial (MongoDB).
// Variables: BASE (https://prod.ecocanje.test:8445/api), USUARIO, SEED_PW, PERFIL (rampa|humo)
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE;
const rampa = [
  { duration: '2m', target: 10 }, { duration: '3m', target: 30 }, { duration: '3m', target: 50 },
  { duration: '4m', target: 50 }, { duration: '1m', target: 0 },
];
export const options = {
  scenarios: { consulta: { executor: 'ramping-vus', startVUs: 0,
    stages: __ENV.PERFIL === 'humo' ? [{ duration: '20s', target: 2 }] : rampa, gracefulRampDown: '10s' } },
  thresholds: { 'http_req_duration{scenario:consulta}': ['p(95)<1000'], 'http_req_failed{scenario:consulta}': ['rate<0.01'] },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export function setup() {
  const r = http.post(`${BASE}/login`, JSON.stringify({ email: __ENV.USUARIO, password: __ENV.SEED_PW }),
    { headers: { 'Content-Type': 'application/json', Accept: 'application/json' } });
  if (r.status !== 200) throw new Error(`login fallo: ${r.status}`);
  return { token: r.json('token') };
}

export default function (d) {
  const h = { headers: { Authorization: `Bearer ${d.token}`, Accept: 'application/json' } };
  const rs = http.batch([
    ['GET', `${BASE}/materiales`, null, Object.assign({ tags: { ruta: 'materiales' } }, h)],
    ['GET', `${BASE}/recompensas`, null, Object.assign({ tags: { ruta: 'recompensas' } }, h)],
    ['GET', `${BASE}/saldo`, null, Object.assign({ tags: { ruta: 'saldo' } }, h)],
    ['GET', `${BASE}/historial`, null, Object.assign({ tags: { ruta: 'historial' } }, h)],
  ]);
  rs.forEach((r) => check(r, { 'status 200': (x) => x.status === 200 }));
  sleep(0.5);
}
