import { useEffect, useState } from 'react';
import { api, enExpiracion, sesion } from './api.js';
import { Aviso, ErrorCampo, useAccion } from './comun.jsx';
import Ciudadano from './paginas/Ciudadano.jsx';
import Operador from './paginas/Operador.jsx';

const VERSION = import.meta.env.VITE_VERSION || 'dev';

function Acceso({ entrar }) {
  const [modo, setModo] = useState('login');
  const [f, setF] = useState({ name: '', email: '', password: '' });
  const { aviso, cerrar, ocupado, campos, ejecutar } = useAccion();
  const cambiar = (e) => setF({ ...f, [e.target.name]: e.target.value });

  const enviar = async (e) => {
    e.preventDefault();
    const r = await ejecutar(() => (modo === 'login'
      ? api('POST', '/login', { email: f.email, password: f.password })
      : api('POST', '/registro', f).then((x) => ({ ...x, rol: 'ciudadano' }))));
    if (r) entrar({ token: r.token, rol: r.rol, email: f.email });
  };

  return (
    <main className="acceso">
      <h1>EcoCanje</h1>
      <p className="subtitulo">Centro de acopio y reciclaje con canje de puntos</p>
      <form onSubmit={enviar} className="tarjeta">
        <h2>{modo === 'login' ? 'Iniciar sesión' : 'Crear cuenta de ciudadano'}</h2>
        <Aviso aviso={aviso} cerrar={cerrar} />
        {modo === 'registro' && (
          <label>Nombre<input name="name" value={f.name} onChange={cambiar} required maxLength={100} autoComplete="name" />
            <ErrorCampo campos={campos} nombre="name" /></label>
        )}
        <label>Correo<input name="email" type="email" value={f.email} onChange={cambiar} required autoComplete="email" />
          <ErrorCampo campos={campos} nombre="email" /></label>
        <label>Contraseña<input name="password" type="password" value={f.password} onChange={cambiar} required
          minLength={modo === 'registro' ? 10 : undefined} autoComplete={modo === 'login' ? 'current-password' : 'new-password'} />
          <ErrorCampo campos={campos} nombre="password" /></label>
        <button disabled={ocupado}>{ocupado ? 'Enviando…' : modo === 'login' ? 'Entrar' : 'Registrarme'}</button>
        <button type="button" className="enlace" onClick={() => { setModo(modo === 'login' ? 'registro' : 'login'); cerrar(); }}>
          {modo === 'login' ? '¿No tienes cuenta? Regístrate' : 'Ya tengo cuenta'}
        </button>
      </form>
    </main>
  );
}

export default function App() {
  const [s, setS] = useState(sesion.leer());
  const [expirada, setExpirada] = useState(false);
  useEffect(() => enExpiracion(() => { setS(null); setExpirada(true); }), []);

  const entrar = (x) => { sesion.guardar(x); setS(x); setExpirada(false); };
  const salir = async () => { await api('POST', '/logout').catch(() => {}); sesion.borrar(); setS(null); };

  return (
    <>
      {expirada && !s && <div className="aviso error" role="alert">Tu sesión expiró; vuelve a iniciar sesión.</div>}
      {!s ? <Acceso entrar={entrar} /> : (
        <div className="marco">
          <header>
            <strong>EcoCanje</strong>
            <span className="quien">{s.email} · {s.rol}</span>
            <button className="secundario" onClick={salir}>Salir</button>
          </header>
          {s.rol === 'operador' ? <Operador /> : <Ciudadano />}
        </div>
      )}
      <footer>EcoCanje · interfaz {VERSION}</footer>
    </>
  );
}
