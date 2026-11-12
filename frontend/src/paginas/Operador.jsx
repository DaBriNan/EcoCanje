import { useState } from 'react';
import { api } from '../api.js';
import { Aviso, ErrorCampo, Estado, fecha, useAccion, useDatos } from '../comun.jsx';

const PESTANAS = { entregas: 'Entregas', canjes: 'Canjes', materiales: 'Materiales', recompensas: 'Recompensas', reporte: 'Reporte' };

export default function Operador() {
  const [p, setP] = useState('entregas');
  const accion = useAccion();
  return (
    <main className="contenido">
      <nav className="pestanas" aria-label="Secciones">
        {Object.entries(PESTANAS).map(([k, v]) => (
          <button key={k} className={p === k ? 'activa' : 'secundario'} aria-current={p === k ? 'page' : undefined}
            onClick={() => { setP(k); accion.cerrar(); }}>{v}</button>
        ))}
      </nav>
      <Aviso aviso={accion.aviso} cerrar={accion.cerrar} />
      {p === 'entregas' && <Entregas a={accion} />}
      {p === 'canjes' && <Canjes a={accion} />}
      {p === 'materiales' && <Materiales a={accion} />}
      {p === 'recompensas' && <Recompensas a={accion} />}
      {p === 'reporte' && <Reporte />}
    </main>
  );
}

const PASOS = {
  registrada: 'Pesa cada material en la báscula y captura el peso real; luego "Confirmar pesaje".',
  pesada: 'Revisa que cada material corresponda a lo declarado y esté limpio; valida o rechaza con motivo.',
  validada: 'Al acreditar se calculan los puntos con la tarifa fijada al registrar y se suman al ciudadano.',
};
const filaVacia = () => ({ material_id: '', peso_kg: '' });

function Entregas({ a }) {
  const materiales = useDatos('/materiales');
  const nombre = (id) => materiales.datos?.find((m) => m.id === id)?.nombre ?? `material #${id}`;
  const tarifa = (id) => materiales.datos?.find((m) => m.id === Number(id))?.puntos_por_kg;
  const [filtro, setFiltro] = useState('');
  const [ciudadano, setCiudadano] = useState('');
  const consulta = new URLSearchParams({ ...(filtro && { estado: filtro }), ...(/^\d+$/.test(ciudadano) && { user_id: ciudadano }) });
  const lista = useDatos(`/entregas${consulta.toString() ? `?${consulta}` : ''}`);
  const [usuario, setUsuario] = useState('');
  const [filas, setFilas] = useState([filaVacia()]);
  const [pesos, setPesos] = useState({});
  const [motivo, setMotivo] = useState({});
  const cambiarFila = (i, campo, valor) => setFilas(filas.map((x, j) => (j === i ? { ...x, [campo]: valor } : x)));
  const estimado = filas.reduce((t, x) => t + Math.round((Number(x.peso_kg) || 0) * (tarifa(x.material_id) || 0)), 0);

  const registrar = async (e) => {
    e.preventDefault();
    const r = await a.ejecutar(() => api('POST', '/entregas', {
      user_id: Number(usuario), detalles: filas.map((x) => ({ material_id: Number(x.material_id), peso_kg: Number(x.peso_kg) })),
    }), (x) => `Entrega #${x.id} registrada con ${x.detalles.length} material(es).`);
    if (r) { setUsuario(''); setFilas([filaVacia()]); lista.cargar(); }
  };
  const paso = async (e, ruta, cuerpo, texto) => {
    const r = await a.ejecutar(() => api('PATCH', `/entregas/${e.id}/${ruta}`, cuerpo), texto);
    if (r !== undefined) lista.cargar();
  };

  return (
    <>
      <form className="tarjeta" onSubmit={registrar}>
        <h2>Registrar entrega</h2>
        <p className="ayuda">Captura el número del ciudadano (lo ve en su pantalla) y una fila por cada material que trae, con el peso que declara.</p>
        <label className="corto">Número de ciudadano<input type="number" min="1" required value={usuario} onChange={(e) => setUsuario(e.target.value)} />
          <ErrorCampo campos={a.campos} nombre="user_id" /></label>
        {filas.map((x, i) => (
          <div className="fila" key={i}>
            <label>{`Material ${i + 1}`}<select required value={x.material_id} onChange={(e) => cambiarFila(i, 'material_id', e.target.value)}>
              <option value="">Elige…</option>
              {materiales.datos?.map((m) => (
                <option key={m.id} value={m.id} disabled={filas.some((y, j) => j !== i && Number(y.material_id) === m.id)}>
                  {m.nombre} ({m.puntos_por_kg} pts/kg)</option>
              ))}
            </select><ErrorCampo campos={a.campos} nombre={`detalles.${i}.material_id`} /></label>
            <label>{`Peso declarado ${i + 1} (kg)`}<input type="number" step="0.1" min="0.1" max="200" required value={x.peso_kg}
              onChange={(e) => cambiarFila(i, 'peso_kg', e.target.value)} />
              <ErrorCampo campos={a.campos} nombre={`detalles.${i}.peso_kg`} /></label>
            {filas.length > 1 && <button type="button" className="secundario quitar" onClick={() => setFilas(filas.filter((_, j) => j !== i))}>Quitar</button>}
          </div>
        ))}
        <div className="acciones">
          <button type="button" className="secundario" disabled={filas.length >= 10} onClick={() => setFilas([...filas, filaVacia()])}>Agregar material</button>
          <span className="ayuda">Puntos estimados: <strong>{estimado}</strong> (se confirman con el peso en báscula)</span>
        </div>
        <button disabled={a.ocupado}>Registrar entrega</button>
      </form>

      <section className="tarjeta">
        <div className="titulo-fila">
          <h2>Entregas</h2>
          <input type="search" inputMode="numeric" pattern="\d*" placeholder="Buscar por número de ciudadano" aria-label="Buscar por id de ciudadano"
            value={ciudadano} onChange={(e) => setCiudadano(e.target.value.trim())} />
          <select aria-label="Filtrar por estado" value={filtro} onChange={(e) => setFiltro(e.target.value)}>
            <option value="">Todas</option>
            {['registrada', 'pesada', 'validada', 'acreditada', 'rechazada'].map((x) => <option key={x}>{x}</option>)}
          </select>
        </div>
        {!lista.datos ? <p>Cargando…</p> : lista.datos.data.length === 0 ? <p>Sin entregas.</p> : (
          <ul className="lista">
            {lista.datos.data.map((e) => (
              <li key={e.id} className="bloque">
                <div><strong>#{e.id}</strong> ciudadano {e.user_id} · <Estado valor={e.estado} /> <small>{fecha(e.created_at)}</small>
                  {e.motivo_rechazo && <small> · {e.motivo_rechazo}</small>}</div>
                <table className="detalle">
                  <thead><tr><th>Material</th><th>{e.estado === 'registrada' ? 'Declarado' : 'Peso'}</th>
                    {e.estado === 'registrada' && <th>Peso en báscula</th>}<th>Puntos</th></tr></thead>
                  <tbody>{e.detalles.map((d) => (
                    <tr key={d.id}>
                      <td>{nombre(d.material_id)}</td>
                      <td>{Number(d.peso_kg).toFixed(1)} kg</td>
                      {e.estado === 'registrada' && <td><input type="number" step="0.1" min="0.1" max="200"
                        aria-label={`Peso real de ${nombre(d.material_id)} (declarado ${d.peso_kg} kg)`} placeholder={`${d.peso_kg}`}
                        value={pesos[d.id] ?? ''} onChange={(x) => setPesos({ ...pesos, [d.id]: x.target.value })} /> kg</td>}
                      <td>{e.estado === 'acreditada' ? d.puntos : '—'}</td>
                    </tr>
                  ))}</tbody>
                </table>
                {PASOS[e.estado] && <p className="ayuda">{PASOS[e.estado]}</p>}
                <div className="acciones">
                  {e.estado === 'registrada' && <button disabled={a.ocupado} onClick={() => paso(e, 'pesar', {
                    detalles: e.detalles.map((d) => ({ id: d.id, peso_kg: Number(pesos[d.id] || d.peso_kg) })),
                  }, `Entrega #${e.id} pesada.`)}>Confirmar pesaje</button>}
                  {e.estado === 'pesada' && <button disabled={a.ocupado} onClick={() => paso(e, 'validar', undefined, `Entrega #${e.id} validada.`)}>Validar</button>}
                  {e.estado === 'validada' && <button disabled={a.ocupado} onClick={() => paso(e, 'acreditar', undefined, (x) => `Entrega #${e.id} acreditada: ${x.detalles.reduce((t, d) => t + (d.puntos || 0), 0)} puntos.`)}>Acreditar puntos</button>}
                  {['registrada', 'pesada', 'validada'].includes(e.estado) && (<>
                    <input aria-label={`Motivo de rechazo de #${e.id}`} placeholder="Motivo de rechazo" maxLength={200}
                      value={motivo[e.id] ?? ''} onChange={(x) => setMotivo({ ...motivo, [e.id]: x.target.value })} />
                    <button className="peligro" disabled={a.ocupado || !motivo[e.id]}
                      onClick={() => paso(e, 'rechazar', { motivo: motivo[e.id] }, `Entrega #${e.id} rechazada.`)}>Rechazar</button>
                  </>)}
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}

function Canjes({ a }) {
  const lista = useDatos('/canjes');
  const paso = async (c, ruta, texto) => {
    const r = await a.ejecutar(() => api('PATCH', `/canjes/${c.id}/${ruta}`), texto);
    if (r !== undefined) lista.cargar();
  };
  return (
    <section className="tarjeta">
      <h2>Canjes</h2>
      {!lista.datos ? <p>Cargando…</p> : lista.datos.data.length === 0 ? <p>Sin canjes.</p> : (
        <table><thead><tr><th>#</th><th>Ciudadano</th><th>Puntos</th><th>Estado</th><th>Acciones</th></tr></thead>
          <tbody>{lista.datos.data.map((c) => (
            <tr key={c.id}><td>{c.id}</td><td>{c.user_id}</td><td>{c.puntos}</td><td><Estado valor={c.estado} /></td>
              <td className="acciones">
                {c.estado === 'solicitado' && <button disabled={a.ocupado} onClick={() => paso(c, 'aprobar', `Canje #${c.id} aprobado.`)}>Aprobar</button>}
                {c.estado === 'aprobado' && <button disabled={a.ocupado} onClick={() => paso(c, 'entregar', `Canje #${c.id} entregado.`)}>Entregar</button>}
                {['solicitado', 'aprobado'].includes(c.estado) && (
                  <button className="peligro" disabled={a.ocupado} onClick={() => paso(c, 'cancelar', `Canje #${c.id} cancelado; puntos devueltos.`)}>Cancelar</button>)}
              </td></tr>
          ))}</tbody>
        </table>
      )}
    </section>
  );
}

function Materiales({ a }) {
  const lista = useDatos('/materiales');
  const [nuevo, setNuevo] = useState({ nombre: '', puntos_por_kg: '' });
  const [edicion, setEdicion] = useState({});
  const [baja, setBaja] = useState(null);
  const [ficha, setFicha] = useState(null);

  const crear = async (e) => {
    e.preventDefault();
    const r = await a.ejecutar(() => api('POST', '/materiales', { nombre: nuevo.nombre, puntos_por_kg: Number(nuevo.puntos_por_kg) }),
      (x) => `Material "${x.nombre}" creado.`);
    if (r) { setNuevo({ nombre: '', puntos_por_kg: '' }); lista.cargar(); }
  };
  const guardar = async (m) => {
    const x = edicion[m.id] || {};
    let ok = true;
    if (x.nombre && x.nombre !== m.nombre) ok = (await a.ejecutar(() => api('PUT', `/materiales/${m.id}`, { nombre: x.nombre }))) !== undefined;
    if (ok && x.tarifa && Number(x.tarifa) !== m.puntos_por_kg) ok = (await a.ejecutar(() => api('POST', `/materiales/${m.id}/tarifas`, { puntos_por_kg: Number(x.tarifa) }))) !== undefined;
    if (ok) { a.setAviso({ tipo: 'ok', texto: `Material "${x.nombre || m.nombre}" actualizado.` }); setEdicion({ ...edicion, [m.id]: undefined }); lista.cargar(); }
  };
  const darDeBaja = async (m) => {
    const r = await a.ejecutar(() => api('DELETE', `/materiales/${m.id}`), `Material "${m.nombre}" dado de baja (se conserva su historial).`);
    setBaja(null); if (r !== undefined) lista.cargar();
  };
  const abrirFicha = async (m) => {
    const doc = await api('GET', `/materiales/${m.id}/ficha`).catch(() => null);
    setFicha({ id: m.id, nombre: m.nombre, texto: Object.entries(doc?.atributos || {}).map(([k, v]) => `${k}=${v ?? ''}`).join('\n') });
  };
  const guardarFicha = async () => {
    const atributos = Object.fromEntries(ficha.texto.split('\n').map((l) => l.trim()).filter(Boolean).map((l) => {
      const i = l.indexOf('='); return i < 0 ? [l, ''] : [l.slice(0, i).trim(), l.slice(i + 1).trim()];
    }));
    const r = await a.ejecutar(() => api('PUT', `/materiales/${ficha.id}/ficha`, { atributos }), `Ficha de "${ficha.nombre}" guardada en MongoDB.`);
    if (r) setFicha(null);
  };

  return (
    <>
      <form className="tarjeta" onSubmit={crear}>
        <h2>Nuevo material</h2>
        <div className="fila">
          <label>Nombre<input required maxLength={80} value={nuevo.nombre} onChange={(e) => setNuevo({ ...nuevo, nombre: e.target.value })} />
            <ErrorCampo campos={a.campos} nombre="nombre" /></label>
          <label>Puntos por kg<input type="number" min="1" max="1000" required value={nuevo.puntos_por_kg} onChange={(e) => setNuevo({ ...nuevo, puntos_por_kg: e.target.value })} />
            <ErrorCampo campos={a.campos} nombre="puntos_por_kg" /></label>
        </div>
        <button disabled={a.ocupado}>Crear</button>
      </form>

      {ficha && (
        <section className="tarjeta">
          <h2>Ficha técnica de {ficha.nombre}</h2>
          <label>Atributos (uno por línea, clave=valor; claves en minúsculas y guion bajo)
            <textarea rows={5} value={ficha.texto} onChange={(e) => setFicha({ ...ficha, texto: e.target.value })} /></label>
          <div className="acciones"><button disabled={a.ocupado} onClick={guardarFicha}>Guardar ficha</button>
            <button className="secundario" onClick={() => setFicha(null)}>Cerrar</button></div>
        </section>
      )}

      <section className="tarjeta">
        <h2>Materiales activos</h2>
        {!lista.datos ? <p>Cargando…</p> : (
          <ul className="lista">
            {lista.datos.map((m) => {
              const x = edicion[m.id];
              return (
                <li key={m.id} className="bloque">
                  {x ? (
                    <div className="acciones">
                      <input aria-label="Nombre" value={x.nombre} maxLength={80} onChange={(e) => setEdicion({ ...edicion, [m.id]: { ...x, nombre: e.target.value } })} />
                      <input aria-label="Puntos por kg" type="number" min="1" max="1000" value={x.tarifa} onChange={(e) => setEdicion({ ...edicion, [m.id]: { ...x, tarifa: e.target.value } })} />
                      <button disabled={a.ocupado} onClick={() => guardar(m)}>Guardar</button>
                      <button className="secundario" onClick={() => setEdicion({ ...edicion, [m.id]: undefined })}>Cancelar</button>
                    </div>
                  ) : (
                    <div><strong>{m.nombre}</strong> <small>{m.puntos_por_kg} pts/kg</small></div>
                  )}
                  {!x && (
                    <div className="acciones">
                      <button className="secundario" onClick={() => setEdicion({ ...edicion, [m.id]: { nombre: m.nombre, tarifa: m.puntos_por_kg } })}>Editar</button>
                      <button className="secundario" onClick={() => abrirFicha(m)}>Ficha</button>
                      {baja === m.id ? (<>
                        <button className="peligro" disabled={a.ocupado} onClick={() => darDeBaja(m)}>Confirmar baja</button>
                        <button className="secundario" onClick={() => setBaja(null)}>No</button>
                      </>) : <button className="peligro" onClick={() => setBaja(m.id)}>Dar de baja</button>}
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </section>
    </>
  );
}

function Recompensas({ a }) {
  const lista = useDatos('/recompensas');
  const vacio = { nombre: '', tipo: 'tarjeta_regalo', costo_puntos: '', stock: '' };
  const [f, setF] = useState(vacio);
  const [editando, setEditando] = useState(null);
  const [baja, setBaja] = useState(null);

  const guardar = async (e) => {
    e.preventDefault();
    const cuerpo = { ...f, costo_puntos: Number(f.costo_puntos), stock: Number(f.stock) };
    const r = await a.ejecutar(() => (editando ? api('PUT', `/recompensas/${editando}`, cuerpo) : api('POST', '/recompensas', cuerpo)),
      (x) => `Recompensa "${x.nombre}" ${editando ? 'actualizada' : 'creada'}.`);
    if (r) { setF(vacio); setEditando(null); lista.cargar(); }
  };
  const darDeBaja = async (r) => {
    const x = await a.ejecutar(() => api('DELETE', `/recompensas/${r.id}`), `Recompensa "${r.nombre}" dada de baja.`);
    setBaja(null); if (x !== undefined) lista.cargar();
  };

  return (
    <>
      <form className="tarjeta" onSubmit={guardar}>
        <h2>{editando ? `Editar recompensa #${editando}` : 'Nueva recompensa'}</h2>
        <div className="fila">
          <label>Nombre<input required maxLength={100} value={f.nombre} onChange={(e) => setF({ ...f, nombre: e.target.value })} />
            <ErrorCampo campos={a.campos} nombre="nombre" /></label>
          <label>Tipo<select value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value })}>
            <option value="tarjeta_regalo">Tarjeta de regalo</option><option value="vale_despensa">Vale de despensa</option></select></label>
          <label>Costo (puntos)<input type="number" min="1" required value={f.costo_puntos} onChange={(e) => setF({ ...f, costo_puntos: e.target.value })} />
            <ErrorCampo campos={a.campos} nombre="costo_puntos" /></label>
          <label>Stock<input type="number" min="0" required value={f.stock} onChange={(e) => setF({ ...f, stock: e.target.value })} />
            <ErrorCampo campos={a.campos} nombre="stock" /></label>
        </div>
        <div className="acciones"><button disabled={a.ocupado}>{editando ? 'Guardar cambios' : 'Crear'}</button>
          {editando && <button type="button" className="secundario" onClick={() => { setEditando(null); setF(vacio); }}>Cancelar</button>}</div>
      </form>
      <section className="tarjeta">
        <h2>Recompensas disponibles</h2>
        {!lista.datos ? <p>Cargando…</p> : lista.datos.length === 0 ? <p>No hay recompensas activas con stock.</p> : (
          <ul className="lista">
            {lista.datos.map((r) => (
              <li key={r.id} className="bloque">
                <div><strong>{r.nombre}</strong> <small>{r.tipo.replace('_', ' ')} · {r.costo_puntos} pts · stock {r.stock}</small></div>
                <div className="acciones">
                  <button className="secundario" onClick={() => { setEditando(r.id); setF({ nombre: r.nombre, tipo: r.tipo, costo_puntos: r.costo_puntos, stock: r.stock }); }}>Editar</button>
                  {baja === r.id ? (<>
                    <button className="peligro" disabled={a.ocupado} onClick={() => darDeBaja(r)}>Confirmar baja</button>
                    <button className="secundario" onClick={() => setBaja(null)}>No</button>
                  </>) : <button className="peligro" onClick={() => setBaja(r.id)}>Dar de baja</button>}
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}

function Reporte() {
  const [mes, setMes] = useState(new Date().toISOString().slice(0, 7));
  const r = useDatos(`/reportes/mensual?mes=${mes}`);
  return (
    <section className="tarjeta">
      <div className="titulo-fila"><h2>Reporte mensual</h2>
        <input type="month" aria-label="Mes" value={mes} onChange={(e) => setMes(e.target.value)} /></div>
      {r.error ? <p className="error-campo">{r.error}</p> : !r.datos ? <p>Cargando…</p> : (<>
        <div className="cifras">
          <div><span className="cifra">{r.datos.puntos_otorgados}</span> puntos otorgados</div>
          <div><span className="cifra">{r.datos.puntos_canjeados}</span> puntos canjeados</div>
        </div>
        <table><thead><tr><th>Material</th><th>Kilos</th><th>Puntos</th></tr></thead>
          <tbody>{r.datos.por_material.map((m) => <tr key={m.nombre}><td>{m.nombre}</td><td>{Number(m.kilos).toFixed(1)}</td><td>{m.puntos}</td></tr>)}</tbody>
        </table>
      </>)}
    </section>
  );
}
