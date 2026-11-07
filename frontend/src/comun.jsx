import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from './api.js';

// Mensaje de confirmación o error, anunciado a lectores de pantalla.
export function Aviso({ aviso, cerrar }) {
  if (!aviso) return null;
  return (
    <div className={`aviso ${aviso.tipo}`} role={aviso.tipo === 'error' ? 'alert' : 'status'}>
      <span>{aviso.texto}</span>
      <button type="button" className="cerrar" onClick={cerrar} aria-label="Cerrar mensaje">×</button>
    </div>
  );
}

// Ejecuta una operación y produce un aviso; devuelve los errores de validación por campo.
export function useAccion() {
  const [aviso, setAviso] = useState(null);
  const [ocupado, setOcupado] = useState(false);
  const [campos, setCampos] = useState({});
  const ejecutar = useCallback(async (fn, exito) => {
    setOcupado(true); setCampos({});
    try {
      const r = await fn();
      if (exito) setAviso({ tipo: 'ok', texto: typeof exito === 'function' ? exito(r) : exito });
      return r;
    } catch (e) {
      setCampos(e.campos || {});
      setAviso({ tipo: 'error', texto: e.message || 'Error inesperado' });
      return undefined;
    } finally { setOcupado(false); }
  }, []);
  return { aviso, setAviso, cerrar: () => setAviso(null), ocupado, campos, ejecutar };
}

// Carga una ruta GET y permite recargarla.
// Solo la respuesta de la consulta vigente actualiza el estado: si la ruta cambia (por ejemplo, al escribir en una
// búsqueda) mientras otra solicitud sigue en curso, la respuesta vieja se descarta aunque llegue después.
export function useDatos(ruta) {
  const [datos, setDatos] = useState(null);
  const [error, setError] = useState(null);
  const vigente = useRef(0);
  const cargar = useCallback(() => {
    const n = ++vigente.current;
    setError(null);
    api('GET', ruta)
      .then((d) => { if (n === vigente.current) setDatos(d); })
      .catch((e) => { if (n === vigente.current) setError(e.message); });
  }, [ruta]);
  useEffect(cargar, [cargar]);
  return { datos, error, cargar };
}

export const ErrorCampo = ({ campos, nombre }) =>
  campos?.[nombre] ? <small className="error-campo">{campos[nombre][0]}</small> : null;

export const Estado = ({ valor }) => <span className={`estado estado-${valor}`}>{valor}</span>;

export const fecha = (iso) => (iso ? new Date(iso).toLocaleString('es-MX', { dateStyle: 'short', timeStyle: 'short' }) : '—');
