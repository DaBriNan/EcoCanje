import { useState } from 'react';
import { api } from '../api.js';
import { Aviso, Estado, fecha, useAccion, useDatos } from '../comun.jsx';

export default function Ciudadano() {
  const saldo = useDatos('/saldo');
  const materiales = useDatos('/materiales');
  const recompensas = useDatos('/recompensas');
  const canjes = useDatos('/canjes');
  const entregas = useDatos('/entregas');
  const historial = useDatos('/historial');
  const { aviso, cerrar, ocupado, ejecutar } = useAccion();
  const [confirmar, setConfirmar] = useState(null);

  const canjear = async (r) => {
    const ok = await ejecutar(() => api('POST', '/canjes', { recompensa_id: r.id }),
      `Canje solicitado: ${r.nombre} (${r.costo_puntos} puntos). Un operador lo aprobará.`);
    setConfirmar(null);
    if (ok) { saldo.cargar(); recompensas.cargar(); canjes.cargar(); }
  };

  return (
    <main className="contenido">
      <Aviso aviso={aviso} cerrar={cerrar} />
      <section className="tarjeta resumen">
        <h2>Mi saldo</h2>
        {saldo.error ? <p className="error-campo">{saldo.error}</p> : !saldo.datos ? <p>Cargando…</p> : (
          <div className="cifras">
            <div><span className="cifra">{saldo.datos.saldo}</span> puntos disponibles</div>
            <div><span className="cifra">{saldo.datos.vence_en_30_dias}</span> vencen en 30 días</div>
            <div><span className="cifra">{saldo.datos.tope_diario_restante}</span> por acreditar hoy</div>
          </div>
        )}
      </section>

      <section className="tarjeta">
        <h2>Recompensas</h2>
        {!recompensas.datos ? <p>Cargando…</p> : recompensas.datos.length === 0 ? <p>No hay recompensas disponibles.</p> : (
          <ul className="lista">
            {recompensas.datos.map((r) => (
              <li key={r.id}>
                <div><strong>{r.nombre}</strong> <small>{r.tipo.replace('_', ' ')} · {r.stock} disponibles</small></div>
                {confirmar === r.id ? (
                  <span className="acciones">
                    <button disabled={ocupado} onClick={() => canjear(r)}>Confirmar {r.costo_puntos} pts</button>
                    <button className="secundario" onClick={() => setConfirmar(null)}>Cancelar</button>
                  </span>
                ) : (
                  <button disabled={ocupado || (saldo.datos && saldo.datos.saldo < r.costo_puntos)} onClick={() => setConfirmar(r.id)}>
                    Canjear · {r.costo_puntos} pts
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="tarjeta">
        <h2>Tarifas por material</h2>
        {!materiales.datos ? <p>Cargando…</p> : (
          <table><thead><tr><th>Material</th><th>Puntos por kg</th></tr></thead>
            <tbody>{materiales.datos.map((m) => <tr key={m.id}><td>{m.nombre}</td><td>{m.puntos_por_kg ?? '—'}</td></tr>)}</tbody>
          </table>
        )}
      </section>

      <section className="tarjeta">
        <h2>Mis canjes</h2>
        {!canjes.datos ? <p>Cargando…</p> : canjes.datos.data.length === 0 ? <p>Aún no tienes canjes.</p> : (
          <table><thead><tr><th>#</th><th>Puntos</th><th>Estado</th><th>Fecha</th></tr></thead>
            <tbody>{canjes.datos.data.map((c) => <tr key={c.id}><td>{c.id}</td><td>{c.puntos}</td><td><Estado valor={c.estado} /></td><td>{fecha(c.created_at)}</td></tr>)}</tbody>
          </table>
        )}
      </section>

      <section className="tarjeta">
        <h2>Mis entregas</h2>
        {!entregas.datos ? <p>Cargando…</p> : entregas.datos.data.length === 0 ? <p>Aún no tienes entregas.</p> : (
          <table><thead><tr><th>#</th><th>Kilos</th><th>Puntos</th><th>Estado</th><th>Fecha</th></tr></thead>
            <tbody>{entregas.datos.data.map((e) => (
              <tr key={e.id}><td>{e.id}</td>
                <td>{e.detalles.reduce((a, d) => a + Number(d.peso_kg), 0).toFixed(1)}</td>
                <td>{e.detalles.reduce((a, d) => a + (d.puntos || 0), 0)}</td>
                <td><Estado valor={e.estado} /></td><td>{fecha(e.created_at)}</td></tr>
            ))}</tbody>
          </table>
        )}
      </section>

      <section className="tarjeta">
        <h2>Historial de movimientos</h2>
        {historial.error ? <p className="error-campo">{historial.error}</p> : !historial.datos ? <p>Cargando…</p>
          : historial.datos.datos.length === 0 ? <p>Sin movimientos registrados.</p> : (
            <ul className="lista compacta">
              {historial.datos.datos.map((m, i) => <li key={i}><span>{m.tipo}</span><small>{fecha(m.ocurrido_en)}</small></li>)}
            </ul>
          )}
      </section>
    </main>
  );
}
