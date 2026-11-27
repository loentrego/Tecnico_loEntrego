// =====================================================================
//  Documentación técnica LoEntrego
//  Las tablas y relaciones salen de datos/esquema.js, generado desde la base
//  real con db/exportar-esquema.sql: si cambia el esquema, se regenera y listo.
// =====================================================================
(() => {
  'use strict';
  const $ = (s) => document.querySelector(s);
  const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const E = window.ESQUEMA || { tablas: [], enums: {}, vistas: [] };

  // ---------- Áreas: cómo se agrupan las tablas ----------
  const AREAS = [
    { id: 'acceso', nombre: 'Acceso', color: '#3422A8', tablas: ['usuarios', 'sesiones', 'intentos_ingreso', 'suscripciones_push'], txt: 'Quién entra, desde dónde y con qué rol.' },
    { id: 'territorio', nombre: 'Territorio', color: '#2160C4', tablas: ['municipios', 'localidades', 'tarifas', 'zonas_reparto', 'zona_repartidores'], txt: 'Municipios, localidades, zonas de reparto y tarifas (PostGIS).' },
    { id: 'comercios', nombre: 'Comercios', color: '#5A48D6', tablas: ['comercios', 'metricas_comercio_dia'], txt: 'Los clientes de LoEntrego, su punto de recogida y sus métricas.' },
    { id: 'repartidores', nombre: 'Repartidores', color: '#4F8DFF', tablas: ['repartidores', 'documentos_repartidor', 'jornadas', 'metricas_repartidor_dia'], txt: 'Quién reparte, sus documentos, jornadas y métricas.' },
    { id: 'pedidos', nombre: 'Pedidos', color: '#B5DB2E', tablas: ['pedidos', 'pedido_eventos', 'asignaciones', 'evidencias', 'calificaciones'], txt: 'El centro: cada pedido, su historial y cómo terminó.' },
    { id: 'dinero', nombre: 'Dinero', color: '#FF8A1F', tablas: ['cierres_caja', 'liquidaciones', 'liquidacion_pedidos', 'pagos_repartidor'], txt: 'Recaudo contraentrega, cierres de caja, liquidaciones y pagos.' },
    { id: 'captacion', nombre: 'Captación', color: '#C3B9FF', tablas: ['solicitudes_comercio', 'postulaciones_repartidor', 'mensajes_contacto', 'enlaces_registro', 'registros_por_enlace'], txt: 'Formularios de la web y enlaces de registro del panel.' },
    { id: 'redes', nombre: 'Redes y reputación', color: '#D63A4C', tablas: ['metricas_redes', 'resenas'], txt: 'Google Business, Instagram y Facebook para el Resumen.' },
    { id: 'notificaciones', nombre: 'Notificaciones', color: '#12092E', tablas: ['plantillas', 'notificaciones'], txt: 'Push y correo, con su estado de envío.' },
    { id: 'sistema', nombre: 'Sistema', color: '#5D5889', tablas: ['archivos', 'estado_canales', 'mantenimientos', 'ajustes', 'auditoria'], txt: 'Archivos, página de mantenimiento, ajustes y auditoría.' },
  ];
  const areaDe = {};
  AREAS.forEach((a) => a.tablas.forEach((t) => (areaDe[t] = a)));

  // ---------- Qué guarda cada tabla ----------
  const DESC = {
    usuarios: 'Las cuentas de acceso: admin, comercio o repartidor. El comercio es solo su cuenta, sin dueño ni responsable. Usuario, clave (hash), nombre, celular y tema.',
    sesiones: 'Una por dispositivo. Guarda el hash del token de refresco y cuándo vence o se revocó.',
    intentos_ingreso: 'Cada intento de inicio de sesión, exitoso o no. Sirve para bloquear fuerza bruta.',
    suscripciones_push: 'Suscripciones Web Push de la AppWeb para mandar notificaciones.',
    municipios: 'Bogotá, Funza y Soacha, con su límite y si hay cobertura.',
    localidades: 'Localidades de Bogotá, comunas de Soacha y cuadrantes de Funza. Referencia para reportes.',
    tarifas: 'Tarifa de envío por municipio con vigencia. El pedido copia la vigente al crearse.',
    zonas_reparto: 'Las zonas que se dibujan en el panel. Deciden a qué repartidor va cada pedido.',
    zona_repartidores: 'Qué repartidores atienden cada zona (muchos a muchos).',
    comercios: 'Comercios, ecommerce y entidades públicas que envían con LoEntrego, con su cuenta para liquidar.',
    metricas_comercio_dia: 'Números de cada comercio por día: pedidos, entregados, recaudo, tarifas y tiempo de entrega.',
    metricas_repartidor_dia: 'Números de cada repartidor por día: entregas, efectivo cobrado, horas conectado y calificación.',
    repartidores: 'Datos del repartidor: documento, estado, fecha de ingreso y contacto de emergencia.',
    documentos_repartidor: 'Cédula y antecedentes, con fecha de vencimiento.',
    jornadas: 'Cuándo empezó y terminó a trabajar cada repartidor. No se guarda su ubicación.',
    pedidos: 'Cada envío: destinatario, dirección, municipio, zona, cobro contraentrega, tarifa, repartidor y estado.',
    pedido_eventos: 'Historial de estados con hora y usuario (la mini-ruta de la AppWeb).',
    asignaciones: 'Dato auxiliar: cada cambio de repartidor del pedido con la hora y quién lo hizo. Se llena sola.',
    evidencias: 'Fotos y firmas de la entrega o del intento.',
    calificaciones: 'Estrellas y comentario del cliente o del comercio sobre la entrega.',
    cierres_caja: 'Cuánto cobró el repartidor en el día y cuánto entregó. La diferencia se calcula sola.',
    liquidaciones: 'Lo que se le paga al comercio por periodo: recaudo menos tarifas.',
    liquidacion_pedidos: 'Qué pedidos entran en cada liquidación. Un pedido se liquida una sola vez.',
    pagos_repartidor: 'Pago al repartidor por periodo: entregas por valor más ajustes.',
    solicitudes_comercio: 'Formulario "Únete" de la web. Se sigue hasta que se convierte en comercio.',
    postulaciones_repartidor: 'Personas que quieren repartir con LoEntrego.',
    mensajes_contacto: 'Formulario de contacto de la web.',
    enlaces_registro: 'Enlaces que genera el panel para invitar comercios o repartidores, con usos y vencimiento.',
    registros_por_enlace: 'Quién se registró con cada enlace.',
    metricas_redes: 'Una foto diaria de cada red: seguidores, alcance, interacciones y calificación.',
    resenas: 'Reseñas públicas de Google y Facebook, con su respuesta.',
    plantillas: 'Textos de los mensajes (push y correo) con variables.',
    notificaciones: 'Cada mensaje enviado o por enviar, con su estado y el id del proveedor.',
    archivos: 'Ficha de cada archivo guardado en el almacenamiento de objetos.',
    estado_canales: 'Lo que muestra la página de mantenimiento para cada canal.',
    mantenimientos: 'Ventanas de mantenimiento con su hora estimada de regreso.',
    ajustes: 'Valores generales: pago por entrega, horario, correo de contacto.',
    auditoria: 'Quién cambió qué, con el antes y el después.',
  };

  // ---------- Portada: cifras ----------
  const nFk = E.tablas.reduce((s, t) => s + t.columnas.filter((c) => c.fk).length, 0);
  const nCol = E.tablas.reduce((s, t) => s + t.columnas.length, 0);
  $('#cover-stats').innerHTML = [
    [E.tablas.length, 'tablas'], [nCol, 'columnas'], [nFk, 'relaciones'], [E.vistas.length, 'vistas'],
  ].map(([n, l]) => `<span><b>${n}</b>${l}</span>`).join('');

  // ---------- Áreas ----------
  $('#dominios').innerHTML = AREAS.map((a) => `
    <a class="dom" href="#a-${a.id}" style="--c:${a.color}">
      <span class="dom-n">${a.tablas.length}</span>
      <b>${a.nombre}</b>
      <p>${a.txt}</p>
    </a>`).join('');

  // ---------- Tablas ----------
  const porNombre = Object.fromEntries(E.tablas.map((t) => [t.nombre, t]));
  const tipoCorto = (t) => t
    .replace('timestamp with time zone', 'timestamptz')
    .replace('character varying', 'varchar')
    .replace('double precision', 'double');
  const filaCol = (c) => {
    const k = [];
    if (c.pk) k.push('<i class="k pk">PK</i>');
    if (c.fk) k.push(`<a class="k fk" href="#t-${c.fk.tabla}" title="Apunta a ${c.fk.tabla}.${c.fk.col}">→ ${c.fk.tabla}</a>`);
    if (c.uq) k.push('<i class="k uq">Único</i>');
    return `<li data-busca="${esc(c.nombre)}"><span class="col">${c.nn ? '<i class="k nn" title="Obligatoria">•</i>' : '<i class="k nn off"></i>'}${esc(c.nombre)}</span><code class="tipo">${esc(tipoCorto(c.tipo))}</code><span class="keys">${k.join('')}</span></li>`;
  };
  // A quién apuntan desde otras tablas (relaciones inversas)
  const entrantes = {};
  E.tablas.forEach((t) => t.columnas.forEach((c) => { if (c.fk) (entrantes[c.fk.tabla] ||= []).push(t.nombre); }));

  $('#tablas-lista').innerHTML = AREAS.map((a) => `
    <div class="area" id="a-${a.id}" style="--c:${a.color}">
      <h3 class="area-t"><span></span>${a.nombre}<small>${a.tablas.length} tablas</small></h3>
      <div class="tbls">
        ${a.tablas.filter((n) => porNombre[n]).map((n) => {
          const t = porNombre[n];
          const usan = [...new Set(entrantes[n] || [])].filter((x) => x !== n);
          return `<article class="tbl" id="t-${n}" data-busca="${esc(n)}">
            <header><h4>${n}</h4><span>${t.columnas.length} col.</span></header>
            <p class="tbl-d">${esc(DESC[n] || '')}</p>
            <ul>${t.columnas.map(filaCol).join('')}</ul>
            ${usan.length ? `<p class="tbl-in">La usan: ${usan.map((u) => `<a href="#t-${u}">${u}</a>`).join(' ')}</p>` : ''}
          </article>`;
        }).join('')}
      </div>
    </div>`).join('');

  // Tablas que no estén en ninguna área (por si el esquema crece): se avisa en consola
  const sinArea = E.tablas.map((t) => t.nombre).filter((n) => !areaDe[n]);
  if (sinArea.length) console.warn('Tablas sin área:', sinArea);

  $('#enums').innerHTML = Object.entries(E.enums || {}).sort().map(([k, v]) =>
    `<div class="enum"><code>${esc(k)}</code><p>${v.map((x) => `<span>${esc(x)}</span>`).join('')}</p></div>`).join('');

  // Buscador de tablas y columnas
  $('#tabla-filtro').addEventListener('input', (e) => {
    const q = e.target.value.trim().toLowerCase();
    document.querySelectorAll('.tbl').forEach((t) => {
      const cols = [...t.querySelectorAll('li')];
      const enNombre = t.dataset.busca.includes(q);
      let alguna = false;
      cols.forEach((li) => { const m = q && li.dataset.busca.includes(q); li.classList.toggle('hit', !!m); alguna ||= m; });
      t.hidden = q && !enNombre && !alguna;
    });
    document.querySelectorAll('.area').forEach((a) => { a.hidden = ![...a.querySelectorAll('.tbl')].some((t) => !t.hidden); });
  });

  // ---------- Relaciones ----------
  const rels = [];
  E.tablas.forEach((t) => t.columnas.forEach((c) => c.fk && rels.push([t.nombre, c.nombre, c.fk.tabla, c.fk.col])));
  rels.sort((a, b) => a[0].localeCompare(b[0]) || a[1].localeCompare(b[1]));
  $('#rel-tabla tbody').innerHTML = rels.map(([t, c, d, dc]) => `
    <tr data-busca="${t} ${c} ${d}">
      <td><a href="#t-${t}"><span class="dot" style="--c:${areaDe[t]?.color}"></span>${t}</a></td>
      <td><code>${c}</code></td><td class="flecha">→</td>
      <td><a href="#t-${d}"><span class="dot" style="--c:${areaDe[d]?.color}"></span>${d}</a><small>.${dc}</small></td>
    </tr>`).join('');
  const filtrar = (input, filas) => $(input).addEventListener('input', (e) => {
    const q = e.target.value.trim().toLowerCase();
    document.querySelectorAll(filas).forEach((r) => (r.hidden = q && !r.dataset.busca.toLowerCase().includes(q)));
  });
  filtrar('#rel-filtro', '#rel-tabla tbody tr');

  // ---------- API (sale de datos/entradas.js: una sola fuente) ----------
  const ES = window.ENTRADAS || { FRONTS: [], EXTRA: [], TIPOS: {} };
  const rutasApi = new Map();
  ES.FRONTS.forEach((f) => f.pantallas.forEach((pa) => pa.llamadas.forEach((l) => {
    const k = l.metodo + ' ' + l.ruta.split('?')[0];
    const r = rutasApi.get(k) || { m: l.metodo, ruta: l.ruta, quien: new Set(), que: l.nombre, tablas: l.tablas, id: l.id, grupo: f.nombre };
    r.quien.add(f.nombre); rutasApi.set(k, r);
  })));
  // el login también lo usa el panel admin
  const kl = 'POST /api/login'; if (rutasApi.has(kl)) rutasApi.get(kl).quien.add('Panel admin');
  const gruposApi = {};
  rutasApi.forEach((r) => (gruposApi[r.grupo] ||= []).push(r));
  gruposApi['Sistema e integraciones'] = ES.EXTRA.map(([m, ruta, q, que, t]) => ({ m, ruta, quien: new Set([q]), que, tablas: t }));
  $('#api-tabla tbody').innerHTML = Object.entries(gruposApi).map(([g, filas]) => `
    <tr class="grupo-fila"><th colspan="5" class="grupo">${esc(g)}</th></tr>
    ${filas.map((r) => `<tr data-busca="${esc(`${g} ${r.ruta} ${[...r.quien].join(' ')} ${r.que} ${r.tablas}`)}">
      <td><span class="metodo m-${r.m.toLowerCase()}">${r.m}</span></td>
      <td>${r.id ? `<a href="#ll-${r.id}"><code>${esc(r.ruta)}</code></a>` : `<code>${esc(r.ruta)}</code>`}</td>
      <td>${[...r.quien].join(', ')}</td><td>${esc(r.que)}</td><td class="t-tablas">${esc(r.tablas)}</td></tr>`).join('')}`).join('');
  $('#api-filtro').addEventListener('input', (e) => {
    const q = e.target.value.trim().toLowerCase();
    document.querySelectorAll('#api-tabla tbody tr:not(.grupo-fila)').forEach((r) => (r.hidden = q && !r.dataset.busca.toLowerCase().includes(q)));
  });

  // ---------- Entradas y salidas ----------
  const T = ES.TIPOS;
  const defecto = { texto: '', entero: 0, decimal: 0, booleano: false, 'fecha-hora': '2026-11-23T09:00:00-05:00', fecha: '2026-11-23', uuid: 'uuid', lista: [], objeto: {} };
  // Arma un JSON de ejemplo con la lista de campos (soporta "a.b", "a[]" y tipos compartidos)
  function construir(campos, prof = 0) {
    const raiz = {};
    for (const [nombre, tipo, req, ej] of campos) {
      const partes = nombre.split('.');
      let o = raiz;
      partes.forEach((seg, k) => {
        const lista = seg.endsWith('[]'), key = seg.replace('[]', ''), ultimo = k === partes.length - 1;
        if (!ultimo) {
          if (lista) { o[key] ||= []; if (!o[key].length || typeof o[key][0] !== 'object') o[key] = [{}]; o = o[key][0]; }
          else { o[key] = (o[key] && typeof o[key] === 'object') ? o[key] : {}; o = o[key]; }
          return;
        }
        let v;
        if (T[tipo] && prof < 3) v = construir(T[tipo].campos, prof + 1);
        else if (ej !== null && ej !== undefined) v = ej;
        else if (/\|/.test(tipo)) v = `<${tipo}>`;
        else v = req ? (defecto[tipo] ?? null) : null;
        o[key] = lista ? (T[tipo] ? [v] : (Array.isArray(v) ? v : [v])) : v;
      });
    }
    return raiz;
  }
  const jsonBonito = (o) => esc(JSON.stringify(o, null, 2))
    .replace(/&quot;([^&]+?)&quot;:/g, '<span class="j-k">"$1"</span>:')
    .replace(/: &quot;(.*?)&quot;/g, ': <span class="j-s">"$1"</span>')
    .replace(/: (-?\d[\d.]*)/g, ': <span class="j-n">$1</span>')
    .replace(/: (true|false|null)/g, ': <span class="j-b">$1</span>');
  const tipoLink = (t) => T[t] ? `<a href="#tipo-${t}" class="t-ref">${t}</a>` : esc(t);
  const tablaCampos = (campos) => `<table class="campos"><thead><tr><th>Campo</th><th>Tipo</th><th></th><th>Nota</th></tr></thead><tbody>${
    campos.map(([n, t, req, , nota]) => `<tr><td><code>${esc(n)}</code></td><td>${tipoLink(t)}</td><td>${req ? '<i class="k nn" title="Obligatorio">•</i>' : '<small>opc.</small>'}</td><td>${esc(nota || '')}</td></tr>`).join('')}</tbody></table>`;
  const cuerpo = (def, titulo) => {
    if (!def) return `<div class="io-vacio"><b>${titulo}</b><p>Sin cuerpo.</p></div>`;
    const campos = typeof def === 'string' ? T[def].campos : def;
    const nombre = typeof def === 'string' ? ` · estructura ${tipoLink(def)}` : '';
    return `<div class="io"><b>${titulo}${nombre}</b><pre class="json">${jsonBonito(construir(campos))}</pre>
      <details class="io-campos"><summary>Ver campo por campo (${campos.length})</summary>${tablaCampos(campos)}</details></div>`;
  };
  const resumenEnvio = (def) => !def ? 'sin cuerpo' : typeof def === 'string' ? def : def.map((c) => c[0].split('.')[0].replace('[]', '')).filter((v, i, a) => a.indexOf(v) === i).join(', ');
  const todasLlamadas = {};
  ES.FRONTS.forEach((f) => f.pantallas.forEach((pa) => pa.llamadas.forEach((l) => (todasLlamadas[l.id] = l))));
  const destino = (id) => id === 'local' ? '<span class="dest d-local">En el navegador</span>'
    : id === 'externo' ? '<span class="dest d-ext">Abre otra app</span>'
    : todasLlamadas[id] ? `<a class="dest d-api" href="#ll-${id}"><span class="metodo m-${todasLlamadas[id].metodo.toLowerCase()}">${todasLlamadas[id].metodo}</span>${esc(todasLlamadas[id].nombre)}</a>` : esc(id);

  // Diagrama de secuencia: Pantalla → API → Base de datos y de vuelta
  const secuencia = (pa) => !pa.llamadas.length ? '' : `
    <div class="seq" role="img" aria-label="Diagrama de secuencia de ${esc(pa.nombre)}">
      <div class="seq-h">Pantalla</div><div class="seq-h">API</div><div class="seq-h">Base de datos</div>
      ${pa.llamadas.map((l, i) => `
        <div class="seq-n" style="grid-row: span 4">${i + 1}</div>
        <div class="seq-m der" style="grid-column: 2 / 4"><span><span class="metodo m-${l.metodo.toLowerCase()}">${l.metodo}</span> <code>${esc(l.ruta)}</code></span><small>envía: ${esc(resumenEnvio(l.envia))}</small></div>
        <div class="seq-m der db" style="grid-column: 3 / 5"><span>consulta / guarda</span><small>${esc(l.tablas)}</small></div>
        <div class="seq-m izq db" style="grid-column: 3 / 5"><span>filas</span></div>
        <div class="seq-m izq ok" style="grid-column: 2 / 4"><span>200 · ${esc(typeof l.recibe === 'string' ? l.recibe : resumenEnvio(l.recibe))}</span>${l.errores?.length ? `<small>errores: ${l.errores.map((e) => e[0]).join(', ')}</small>` : ''}</div>`).join('')}
    </div>`;

  const nCtrl = ES.FRONTS.reduce((s, f) => s + f.pantallas.reduce((a, p) => a + p.controles.length, 0), 0);
  const nLl = Object.keys(todasLlamadas).length;
  $('#io-cifras').innerHTML = [[ES.FRONTS.length, 'frontends'], [ES.FRONTS.reduce((s, f) => s + f.pantallas.length, 0), 'pantallas'], [nCtrl, 'campos y botones'], [nLl, 'llamadas a la API'], [Object.keys(T).length, 'estructuras']]
    .map(([n, l]) => `<span><b>${n}</b>${l}</span>`).join('');

  // Diagrama general: frontends → API → base
  $('#io-mapa').innerHTML = `
    <div class="iom-col">${ES.FRONTS.map((f) => `<a class="iom-f" href="#fe-${f.id}" style="--c:${f.color}"><b>${f.nombre}</b><small>${f.repo}</small><span>${f.pantallas.reduce((a, p) => a + p.controles.length, 0)} controles · ${f.pantallas.reduce((a, p) => a + p.llamadas.length, 0)} llamadas</span></a>`).join('')}</div>
    <div class="iom-flechas" aria-hidden="true"><i>JSON →</i><i>← JSON</i></div>
    <div class="iom-api"><b>API</b><small>app.loentrego.com/api</small>
      <ul><li><code>/api/publico/*</code> sin sesión</li><li><code>/api/login</code> · <code>/api/yo</code></li><li><code>/api/pedidos</code> · <code>/api/ruta</code></li><li><code>/api/admin/*</code> solo admin</li></ul></div>
    <div class="iom-flechas" aria-hidden="true"><i>SQL →</i><i>← filas</i></div>
    <div class="iom-db"><b>PostgreSQL</b><small>+ PostGIS</small><span>${E.tablas.length} tablas · ${E.vistas.length} vistas</span></div>`;

  $('#io-lista').innerHTML = ES.FRONTS.map((f) => `
    <div class="fe" id="fe-${f.id}" style="--c:${f.color}">
      <h3 class="fe-t"><span></span>${f.nombre}<small>${f.repo} · ${f.pantallas.length} pantallas</small></h3>
      <p class="fe-d">${esc(f.txt)}</p>
      ${f.pantallas.map((pa) => `
        <details class="pant" id="pa-${pa.id}">
          <summary><b>${esc(pa.nombre)}</b><small>${esc(pa.archivo)}</small><span class="pant-c">${pa.controles.length} controles · ${pa.llamadas.length} llamadas</span></summary>
          <div class="pant-in">
            ${pa.nota ? `<p class="pant-nota">${esc(pa.nota)}</p>` : ''}
            ${secuencia(pa)}
            <h4 class="h4">Campos y botones</h4>
            <div class="tabla-wrap"><table class="tabla ctrl"><thead><tr><th>Control</th><th>Etiqueta</th><th>Campo</th><th>Regla</th><th>Va a</th></tr></thead><tbody>
              ${pa.controles.map(([t, e, c, r, d]) => `<tr data-busca="${esc(`${e} ${c}`)}"><td><span class="ctl">${esc(t)}</span></td><td>${esc(e)}</td><td>${c === '—' ? '<small>—</small>' : `<code>${esc(c)}</code>`}</td><td>${esc(r)}</td><td>${destino(d)}</td></tr>`).join('')}
            </tbody></table></div>
            ${pa.llamadas.map((l) => `
              <article class="ll" id="ll-${l.id}">
                <header><span class="metodo m-${l.metodo.toLowerCase()}">${l.metodo}</span><code>${esc(l.ruta)}</code><b>${esc(l.nombre)}</b><span class="ll-auth">${esc(l.auth)}</span></header>
                <p class="ll-cuando">${esc(l.cuando)}</p>
                <div class="io-grid">${cuerpo(l.envia, 'Envía')}${cuerpo(l.recibe, 'Recibe')}</div>
                <p class="ll-pie"><span>Tablas: <code>${esc(l.tablas)}</code></span>${l.errores?.length ? `<span>Errores: ${l.errores.map(([c, d]) => `<b>${c}</b> ${esc(d)}`).join(' · ')} · forma <a href="#tipo-Error" class="t-ref">Error</a></span>` : ''}</p>
              </article>`).join('')}
          </div>
        </details>`).join('')}
    </div>`).join('');

  $('#io-tipos').innerHTML = Object.entries(T).map(([n, t]) => `
    <article class="tipo-card" id="tipo-${n}"><header><code>${n}</code></header><p>${esc(t.desc)}</p>
      <pre class="json">${jsonBonito(construir(t.campos))}</pre>
      <details class="io-campos"><summary>Ver campo por campo (${t.campos.length})</summary>${tablaCampos(t.campos)}</details></article>`).join('');

  // Abrir todo / cerrar todo, y abrir la pantalla si se llega por enlace
  $('#io-abrir').addEventListener('click', (e) => {
    const abrir = e.currentTarget.getAttribute('aria-pressed') !== 'true';
    document.querySelectorAll('.pant').forEach((d) => (d.open = abrir));
    e.currentTarget.setAttribute('aria-pressed', String(abrir));
    e.currentTarget.textContent = abrir ? 'Cerrar todas' : 'Abrir todas';
  });
  const abrirDestino = () => { const el = location.hash ? document.querySelector(location.hash) : null; const d = el?.closest('details.pant'); if (d) { d.open = true; el.scrollIntoView(); } };
  window.addEventListener('hashchange', abrirDestino); abrirDestino();
  $('#io-filtro').addEventListener('input', (e) => {
    const q = e.target.value.trim().toLowerCase();
    document.querySelectorAll('.pant').forEach((d) => {
      const filas = [...d.querySelectorAll('.ctrl tbody tr')];
      let alguna = false;
      filas.forEach((r) => { const m = !q || r.dataset.busca.toLowerCase().includes(q); r.hidden = !m; alguna ||= m && !!q; });
      const enPant = q && d.textContent.toLowerCase().includes(q);
      d.hidden = q && !enPant;
      if (q) d.open = alguna || enPant;
    });
  });

  // ---------- Índice: resalta la sección que se está leyendo ----------
  const links = [...document.querySelectorAll('.toc a')];
  const io = new IntersectionObserver((entries) => {
    entries.forEach((en) => {
      if (!en.isIntersecting) return;
      links.forEach((a) => a.toggleAttribute('aria-current', a.getAttribute('href') === '#' + en.target.id));
    });
  }, { rootMargin: '-40% 0px -55% 0px' });
  document.querySelectorAll('.sec').forEach((s) => io.observe(s));
})();
