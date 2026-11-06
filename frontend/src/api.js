// Cliente de la API. Mismo origen (/api), token Bearer en sessionStorage: no hay cookies de sesión,
// por lo que no aplica CSRF; el token se pierde al cerrar la pestaña y expira en 8 h en el servidor.
const CLAVE = 'ecocanje.sesion';

export const sesion = {
  leer: () => { try { return JSON.parse(sessionStorage.getItem(CLAVE)); } catch { return null; } },
  guardar: (s) => sessionStorage.setItem(CLAVE, JSON.stringify(s)),
  borrar: () => sessionStorage.removeItem(CLAVE),
};

export class ErrorApi extends Error {
  constructor(estado, mensaje, campos) { super(mensaje); this.estado = estado; this.campos = campos || {}; }
}

let alExpirar = () => {};
export const enExpiracion = (fn) => { alExpirar = fn; };

export async function api(metodo, ruta, cuerpo) {
  const s = sesion.leer();
  const r = await fetch(`/api${ruta}`, {
    method: metodo,
    headers: {
      Accept: 'application/json',
      ...(cuerpo !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...(s?.token ? { Authorization: `Bearer ${s.token}` } : {}),
    },
    body: cuerpo !== undefined ? JSON.stringify(cuerpo) : undefined,
  });
  if (r.status === 204) return null;
  const datos = await r.json().catch(() => ({}));
  if (r.ok) return datos;
  if (r.status === 401 && s?.token) { sesion.borrar(); alExpirar(); }
  const mensajes = {
    401: 'Credenciales inválidas o sesión expirada.', 403: 'No tienes permiso para esta acción.',
    404: 'No encontrado.', 429: 'Demasiados intentos; espera un minuto.', 503: 'Servicio no disponible, intenta más tarde.',
  };
  throw new ErrorApi(r.status, datos.message || mensajes[r.status] || `Error ${r.status}`, datos.errors);
}
