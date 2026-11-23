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
    { id: 'comercios', nombre: 'Comercios', color: '#5A48D6', tablas: ['comercios', 'comercio_usuarios', 'puntos_recogida'], txt: 'Los clientes de LoEntrego y dónde se recoge.' },
    { id: 'repartidores', nombre: 'Repartidores', color: '#4F8DFF', tablas: ['repartidores', 'documentos_repartidor', 'jornadas', 'intercambios'], txt: 'Quién reparte, sus documentos, jornadas e intercambios.' },
    { id: 'pedidos', nombre: 'Pedidos', color: '#B5DB2E', tablas: ['pedidos', 'pedido_eventos', 'asignaciones', 'evidencias', 'calificaciones'], txt: 'El centro: cada pedido, su historial y cómo terminó.' },
    { id: 'dinero', nombre: 'Dinero', color: '#FF8A1F', tablas: ['cierres_caja', 'liquidaciones', 'liquidacion_pedidos', 'pagos_repartidor'], txt: 'Recaudo contraentrega, cierres de caja, liquidaciones y pagos.' },
    { id: 'captacion', nombre: 'Captación', color: '#C3B9FF', tablas: ['solicitudes_comercio', 'postulaciones_repartidor', 'mensajes_contacto', 'enlaces_registro', 'registros_por_enlace'], txt: 'Formularios de la web y enlaces de registro del panel.' },
    { id: 'redes', nombre: 'Redes y reputación', color: '#D63A4C', tablas: ['metricas_redes', 'resenas'], txt: 'Google Business, Instagram y Facebook para el Resumen.' },
    { id: 'notificaciones', nombre: 'Notificaciones', color: '#12092E', tablas: ['plantillas', 'notificaciones'], txt: 'WhatsApp, push, SMS y correo, con su estado de envío.' },
    { id: 'sistema', nombre: 'Sistema', color: '#5D5889', tablas: ['archivos', 'estado_canales', 'mantenimientos', 'ajustes', 'auditoria'], txt: 'Archivos, página de mantenimiento, ajustes y auditoría.' },
  ];
  const areaDe = {};
  AREAS.forEach((a) => a.tablas.forEach((t) => (areaDe[t] = a)));

  // ---------- Qué guarda cada tabla ----------
  const DESC = {
    usuarios: 'Todas las personas que entran: admin, comercio o repartidor. Usuario, clave (hash), nombre, celular y tema.',
    sesiones: 'Una por dispositivo. Guarda el hash del token de refresco y cuándo vence o se revocó.',
    intentos_ingreso: 'Cada intento de inicio de sesión, exitoso o no. Sirve para bloquear fuerza bruta.',
    suscripciones_push: 'Suscripciones Web Push de la AppWeb para mandar notificaciones.',
    municipios: 'Bogotá, Funza y Soacha, con su límite y si hay cobertura.',
    localidades: 'Localidades de Bogotá, comunas de Soacha y cuadrantes de Funza. Referencia para reportes.',
    tarifas: 'Tarifa de envío por municipio con vigencia. El pedido copia la vigente al crearse.',
    zonas_reparto: 'Las zonas que se dibujan en el panel. Deciden a qué repartidor va cada pedido.',
    zona_repartidores: 'Qué repartidores atienden cada zona (muchos a muchos).',
    comercios: 'Comercios, ecommerce y entidades públicas que envían con LoEntrego, con su cuenta para liquidar.',
    comercio_usuarios: 'Qué usuarios manejan cada comercio (dueño y operadores).',
    puntos_recogida: 'Direcciones donde el repartidor recoge los pedidos del comercio.',
    repartidores: 'Datos del repartidor: documento, vehículo, placa, estado y cuenta para pagarle.',
    documentos_repartidor: 'Cédula, licencia, SOAT y tecnomecánica, con fecha de vencimiento.',
    jornadas: 'Cuándo empezó y terminó a trabajar cada repartidor. No se guarda su ubicación.',
    intercambios: 'Solicitudes para pasar una zona o un pedido de un repartidor a otro.',
    pedidos: 'Cada envío: destinatario, dirección, municipio, zona, cobro contraentrega, tarifa, repartidor y estado.',
    pedido_eventos: 'Historial de estados con hora y usuario (la mini-ruta de la AppWeb).',
    asignaciones: 'Qué repartidor tuvo el pedido y desde cuándo (automático, manual o intercambio).',
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
    plantillas: 'Textos de los mensajes (WhatsApp, correo…) con variables.',
    notificaciones: 'Cada mensaje enviado o por enviar, con su estado y el id del proveedor.',
    archivos: 'Ficha de cada archivo guardado en el almacenamiento de objetos.',
    estado_canales: 'Lo que muestra la página de mantenimiento para cada canal.',
    mantenimientos: 'Ventanas de mantenimiento con su hora estimada de regreso.',
    ajustes: 'Valores generales: pago por entrega, horario, WhatsApp de atención.',
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

  // ---------- API ----------
  const API = [
    ['Públicas', [
      ['GET', '/api/salud', 'Todos', 'Responde si la API y la base están arriba (para el monitoreo).', '—'],
      ['POST', '/api/publico/solicitudes', 'Web', 'Formulario "Únete": guarda la solicitud del comercio.', 'solicitudes_comercio'],
      ['POST', '/api/publico/contacto', 'Web', 'Formulario de contacto.', 'mensajes_contacto'],
      ['POST', '/api/publico/postulaciones', 'Web', 'Postulación de un repartidor.', 'postulaciones_repartidor'],
      ['GET', '/api/publico/canales', 'Mantenimiento', 'Estado de cada canal y hora estimada de regreso.', 'estado_canales, mantenimientos'],
      ['POST', '/api/publico/calificar/:token', 'Cliente final', 'Califica la entrega desde el enlace de WhatsApp.', 'calificaciones'],
    ]],
    ['Sesión', [
      ['POST', '/api/login', 'Todos', 'Inicia sesión (ya conectado en la AppWeb). Devuelve tokens y rol.', 'usuarios, sesiones, intentos_ingreso'],
      ['POST', '/api/refrescar', 'Todos', 'Cambia el token de refresco por uno nuevo.', 'sesiones'],
      ['POST', '/api/salir', 'Todos', 'Cierra la sesión del dispositivo.', 'sesiones'],
      ['GET', '/api/yo', 'Todos', 'Datos del usuario y de su comercio o perfil de repartidor.', 'usuarios, comercios, repartidores'],
      ['POST', '/api/registro/:token', 'Invitado', 'Crea la cuenta con un enlace de registro del panel.', 'enlaces_registro, usuarios'],
      ['POST', '/api/push', 'AppWeb', 'Guarda la suscripción de notificaciones del dispositivo.', 'suscripciones_push'],
    ]],
    ['Comercio', [
      ['GET', '/api/pedidos', 'Comercio', 'Sus pedidos, con filtros por estado y fecha.', 'pedidos'],
      ['POST', '/api/pedidos', 'Comercio', 'Nuevo pedido: geocodifica la dirección; la base pone tarifa, zona y repartidor.', 'pedidos'],
      ['GET', '/api/pedidos/:codigo', 'Comercio', 'Detalle con historial, evidencias y calificación.', 'pedidos, pedido_eventos, evidencias'],
      ['POST', '/api/pedidos/:id/cancelar', 'Comercio', 'Cancela un pedido que aún no se recoge.', 'pedidos'],
      ['POST', '/api/pedidos/:id/reintentar', 'Comercio', 'Crea un nuevo intento de un pedido no entregado.', 'pedidos'],
      ['GET', '/api/tarifas', 'Comercio', 'Tarifas vigentes por municipio.', 'tarifas'],
      ['GET', '/api/liquidaciones', 'Comercio', 'Sus liquidaciones y el detalle por pedido.', 'liquidaciones, liquidacion_pedidos'],
    ]],
    ['Repartidor', [
      ['GET', '/api/ruta', 'Repartidor', 'Sus pedidos del día, en orden.', 'pedidos'],
      ['POST', '/api/pedidos/:id/estado', 'Repartidor', 'Avanza el estado (deslizar para confirmar) o marca no entregado con motivo.', 'pedidos, pedido_eventos'],
      ['POST', '/api/pedidos/:id/evidencias', 'Repartidor', 'Sube foto o firma de la entrega.', 'archivos, evidencias'],
      ['POST', '/api/jornada', 'Repartidor', 'Inicia o termina la jornada.', 'jornadas'],
      ['GET', '/api/caja', 'Repartidor', 'Cobrado, pendiente por cobrar y cierre del día.', 'pedidos, cierres_caja'],
    ]],
    ['Admin', [
      ['GET', '/api/admin/resumen?periodo=', 'Admin', 'Cifras del Resumen: hoy, 1 mes, 6 meses, 1 año o histórico.', 'v_resumen_diario, metricas_redes'],
      ['GET', '/api/admin/buscar?q=', 'Admin', 'Búsqueda global: pedidos, comercios, repartidores.', 'pedidos, comercios, usuarios'],
      ['GET', '/api/admin/pedidos', 'Admin', 'Todos los pedidos con filtros; reasignar repartidor.', 'pedidos, asignaciones'],
      ['GET', '/api/admin/comercios', 'Admin', 'Comercios con sus estadísticas; crear y editar.', 'v_comercios, comercios'],
      ['GET', '/api/admin/repartidores', 'Admin', 'Repartidores con estadísticas, documentos y vencimientos.', 'v_repartidores, documentos_repartidor'],
      ['GET', '/api/admin/zonas', 'Admin', 'Zonas de reparto como GeoJSON (las que dibuja el mapa).', 'zonas_reparto, zona_repartidores'],
      ['PUT', '/api/admin/zonas/:id', 'Admin', 'Crea o edita una zona; recorta las vecinas.', 'zonas_reparto, auditoria'],
      ['GET', '/api/admin/mapa/demanda', 'Admin', 'Pedidos por localidad para la capa Calor.', 'v_demanda_localidad'],
      ['POST', '/api/admin/enlaces', 'Admin', 'Genera un enlace de registro para comercio o repartidor.', 'enlaces_registro'],
      ['POST', '/api/admin/intercambios', 'Admin', 'Pasa una zona o un pedido de un repartidor a otro.', 'intercambios, asignaciones'],
      ['POST', '/api/admin/cierres', 'Admin', 'Registra lo que entregó el repartidor al cerrar caja.', 'cierres_caja'],
      ['POST', '/api/admin/liquidaciones', 'Admin', 'Arma, aprueba y marca como pagada una liquidación.', 'liquidaciones, liquidacion_pedidos'],
      ['GET', '/api/admin/solicitudes', 'Admin', 'Solicitudes de la web y su seguimiento.', 'solicitudes_comercio, mensajes_contacto'],
      ['PUT', '/api/admin/canales', 'Admin', 'Cambia lo que muestra la página de mantenimiento.', 'estado_canales, mantenimientos'],
    ]],
    ['Webhooks', [
      ['POST', '/webhooks/whatsapp', 'Meta', 'Estado de los mensajes enviados (entregado, leído, fallido).', 'notificaciones'],
    ]],
  ];
  $('#api-tabla tbody').innerHTML = API.map(([g, filas]) => `
    <tr class="grupo-fila"><th colspan="5" class="grupo">${g}</th></tr>
    ${filas.map(([m, r, q, d, t]) => `<tr data-busca="${esc(`${g} ${r} ${q} ${d} ${t}`)}">
      <td><span class="metodo m-${m.toLowerCase()}">${m}</span></td><td><code>${esc(r)}</code></td><td>${q}</td><td>${d}</td><td class="t-tablas">${t}</td></tr>`).join('')}`).join('');
  $('#api-filtro').addEventListener('input', (e) => {
    const q = e.target.value.trim().toLowerCase();
    document.querySelectorAll('#api-tabla tbody tr:not(.grupo-fila)').forEach((r) => (r.hidden = q && !r.dataset.busca.toLowerCase().includes(q)));
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
