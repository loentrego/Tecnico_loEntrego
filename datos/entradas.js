// =====================================================================
//  Entradas y salidas de los frontends
//  Cada pantalla de cada frontend: todos sus campos y botones, a qué llamada
//  de la API van y la estructura exacta que se envía y se recibe.
//
//  Campos de una estructura: [nombre, tipo, obligatorio, ejemplo, nota]
//    · "a.b"     → objeto anidado
//    · "a[]"     → lista; "a[].b" → campo de cada elemento
//    · tipo puede ser el nombre de una estructura compartida (TIPOS)
//  Controles: [tipo, etiqueta, campo JSON, regla, llamada]
//    · llamada: id de la llamada a la API, o 'local' si no sale del navegador,
//      o 'externo' si abre otra app (WhatsApp, teléfono, correo, mapas)
// =====================================================================
window.ENTRADAS = (() => {
  'use strict';

  // ---------- Estructuras compartidas ----------
  const TIPOS = {
    Error: {
      desc: 'Toda respuesta con error (4xx/5xx) trae esta forma. El frontend muestra "mensaje".',
      campos: [
        ['error', 'texto', true, 'no_autorizado', 'Código estable para el código del frontend'],
        ['mensaje', 'texto', true, 'Usuario o contraseña incorrectos', 'Texto en español para mostrar'],
        ['campos', 'objeto', false, { celular: 'Debe tener 10 dígitos' }, 'Errores por campo (validación)'],
      ],
    },
    Sesion: {
      desc: 'Lo que devuelve el inicio de sesión. La AppWeb ya lee "rol", "token" y "mensaje".',
      campos: [
        ['rol', 'texto', true, 'comercio', 'admin · comercio · repartidor (decide a qué página entra)'],
        ['token', 'texto', true, 'eyJhbGciOi…', 'Token de acceso (15 min). Se guarda en localStorage "auth_token"'],
        ['refresco', 'texto', true, 'r_8f3a…', 'Token de refresco (30 días)'],
        ['usuario', 'Usuario', true, null, ''],
      ],
    },
    Usuario: {
      desc: 'El usuario que inició sesión.',
      campos: [
        ['id', 'uuid', true, '7d1c…', ''],
        ['nombre', 'texto', true, 'Tienda Central', ''],
        ['rol', 'texto', true, 'comercio', ''],
        ['tema', 'texto', true, 'auto', 'claro · oscuro · auto'],
        ['iniciales', 'texto', true, 'TC', 'Para el círculo de la cuenta'],
      ],
    },
    PedidoResumen: {
      desc: 'Una fila de la lista de pedidos (comercio, repartidor y admin).',
      campos: [
        ['id', 'uuid', true, 'a41f…', ''],
        ['codigo', 'texto', true, 'LOE-0001042', ''],
        ['nombre', 'texto', true, 'Andrea Gómez', 'Quien recibe'],
        ['direccion', 'texto', true, 'Calle 72 #10-34', ''],
        ['zona', 'texto', true, 'bogota', 'Municipio: bogota · funza · soacha'],
        ['cobro', 'entero', true, 45000, 'Pesos. 0 = ya pagado'],
        ['estado', 'texto', true, 'en_camino', 'por_recoger · recogido · en_camino · entregado · no_entregado · cancelado'],
        ['actualizado', 'fecha-hora', true, '2026-11-23T09:40:00-05:00', ''],
      ],
    },
    PedidoDetalle: {
      desc: 'Un pedido completo, con su historial.',
      campos: [
        ['id', 'uuid', true, 'a41f…', ''],
        ['codigo', 'texto', true, 'LOE-0001042', ''],
        ['nombre', 'texto', true, 'Andrea Gómez', ''],
        ['telefono', 'texto', true, '3001234567', '10 dígitos'],
        ['direccion', 'texto', true, 'Calle 72 #10-34', ''],
        ['notas', 'texto', false, 'Entregar en portería', ''],
        ['zona', 'texto', true, 'bogota', ''],
        ['tarifa', 'entero', true, 10000, 'Envío congelado al crear'],
        ['cobro', 'entero', true, 45000, ''],
        ['estado', 'texto', true, 'en_camino', ''],
        ['motivo', 'texto', false, null, 'Solo si no_entregado: no_contesta · direccion · rechazado · ausente · otro'],
        ['comercio.nombre', 'texto', true, 'Tienda Central', ''],
        ['comercio.direccion', 'texto', true, 'Calle 80 #15-20', 'Dónde se recoge'],
        ['repartidor.nombre', 'texto', false, 'Camilo Restrepo', 'Vacío si aún no hay'],
        ['historial[]', 'lista', true, null, 'Un elemento por cambio de estado'],
        ['historial[].estado', 'texto', true, 'recogido', ''],
        ['historial[].hora', 'fecha-hora', true, '2026-11-23T08:40:00-05:00', 'La AppWeb muestra HH:MM'],
        ['puede_editar', 'booleano', true, false, 'true solo mientras está por_recoger'],
      ],
    },
    ZonaFeature: {
      desc: 'Una zona de reparto en GeoJSON (RFC 7946), igual que window.LEMapa.zonasGeoJSON().',
      campos: [
        ['type', 'texto', true, 'Feature', ''],
        ['id', 'texto', true, 'chapinero', ''],
        ['properties.nombre', 'texto', true, 'Chapinero', 'Máx. 40 caracteres'],
        ['properties.municipio', 'texto', true, 'bogota', ''],
        ['properties.repartidores[]', 'lista', true, ['r1'], 'Al menos uno'],
        ['properties.capacidad_diaria', 'entero', true, 12, 'Pedidos al día por repartidor'],
        ['properties.prioridad', 'entero', true, 0, ''],
        ['geometry.type', 'texto', true, 'Polygon', 'Polygon o MultiPolygon'],
        ['geometry.coordinates', 'lista', true, [[[-74.0571, 4.6203], ['…']]], '[longitud, latitud], WGS84'],
      ],
    },
    FichaComercio: {
      desc: 'Comercio en las listas y fichas del panel.',
      campos: [
        ['id', 'uuid', true, '0db0…', ''],
        ['nombre', 'texto', true, 'Tienda Central', ''],
        ['tipo', 'texto', true, 'ecommerce', 'comercio · ecommerce · sector_publico'],
        ['estado', 'texto', true, 'activo', ''],
        ['localidad', 'texto', false, 'Chapinero', ''],
        ['pedidos', 'entero', true, 128, 'En el periodo'],
        ['entregados', 'entero', true, 121, ''],
        ['recaudo', 'entero', true, 3450000, 'Pesos'],
        ['ultimo_pedido', 'fecha-hora', false, '2026-11-23T09:18:00-05:00', ''],
      ],
    },
    FichaRepartidor: {
      desc: 'Repartidor en las listas y fichas del panel.',
      campos: [
        ['id', 'uuid', true, 'r1', ''],
        ['nombre', 'texto', true, 'Camilo Restrepo', ''],
        ['estado', 'texto', true, 'activo', ''],
        ['vehiculo', 'texto', true, 'moto', ''],
        ['zonas[]', 'lista', true, ['Chapinero'], ''],
        ['entregas', 'entero', true, 96, 'En el periodo'],
        ['no_entregas', 'entero', true, 4, ''],
        ['activos', 'entero', true, 3, 'Pedidos en curso ahora'],
        ['calificacion', 'decimal', false, 4.8, '1 a 5'],
      ],
    },
  };

  const auth = 'Token';            // Authorization: Bearer <token>
  const pub = 'Pública';

  const FRONTS = [
    // =================================================================
    {
      id: 'web', nombre: 'Web pública', repo: 'frontend_mainweb', color: '#3422A8',
      txt: 'Inicio, Únete, Nosotros y Contacto. Casi todo es informativo; solo "Únete" envía datos.',
      pantallas: [
        {
          id: 'web-comun', nombre: 'Partes comunes (todas las páginas)', archivo: 'index.html · Pages/*.html',
          controles: [
            ['casilla', 'Menú (hamburguesa, celular)', '—', 'Abre y cierra el menú', 'local'],
            ['botón', 'Copiar correo', '—', 'Copia al portapapeles', 'local'],
            ['botón', 'Copiar teléfono', '—', 'Copia al portapapeles', 'local'],
            ['botón', 'Copiar ubicación', '—', 'Copia al portapapeles', 'local'],
            ['enlace', 'WhatsApp (pie y botón flotante)', '—', 'wa.me con mensaje', 'externo'],
          ],
          llamadas: [],
        },
        {
          id: 'web-inicio', nombre: 'Inicio · mapa de cobertura', archivo: 'index.html',
          controles: [
            ['botón', 'Toda la zona', 'municipio = null', 'Filtra el mapa', 'cobertura'],
            ['botón', 'Bogotá', 'municipio = "bogota"', 'Filtra el mapa', 'cobertura'],
            ['botón', 'Funza', 'municipio = "funza"', 'Filtra el mapa', 'cobertura'],
            ['botón', 'Soacha', 'municipio = "soacha"', 'Filtra el mapa', 'cobertura'],
            ['botón', 'Alejar mapa / Acercar mapa', '—', 'Zoom', 'local'],
            ['enlace', 'ventas@ (correo)', '—', 'mailto:', 'externo'],
          ],
          llamadas: [
            {
              id: 'cobertura', nombre: 'Cobertura y tarifas', metodo: 'GET', ruta: '/api/publico/cobertura', auth: pub,
              cuando: 'Al cargar la página (hoy los valores están fijos en el HTML: $10.000 por municipio).',
              envia: null,
              recibe: [
                ['municipios[]', 'lista', true, null, ''],
                ['municipios[].id', 'texto', true, 'bogota', ''],
                ['municipios[].nombre', 'texto', true, 'Bogotá', ''],
                ['municipios[].tarifa', 'entero', true, 10000, 'Tarifa vigente'],
                ['municipios[].activo', 'booleano', true, true, ''],
                ['actualizado', 'fecha-hora', true, '2026-11-23T00:00:00-05:00', ''],
              ],
              tablas: 'municipios, tarifas', errores: [],
            },
          ],
        },
        {
          id: 'web-unete', nombre: 'Únete · formulario de aliados', archivo: 'Pages/indexunete.html',
          controles: [
            ['botón', 'Todas / Bogotá / Funza / Soacha', 'municipio', 'Filtra el mapa', 'cobertura'],
            ['acordeón', 'Cobertura y tarifa', '—', 'Abre la respuesta', 'local'],
            ['acordeón', 'Tamaño máximo por paquete', '—', 'Abre la respuesta', 'local'],
            ['texto', 'Nombre del comercio', 'comercio', 'Obligatorio · 2 a 80 caracteres', 'solicitud'],
            ['texto', 'Ubicación de despacho', 'ubicacion', 'Obligatorio · 5 a 120 caracteres', 'solicitud'],
            ['teléfono', 'Número de celular', 'celular', 'Obligatorio · 10 dígitos, empieza por 3', 'solicitud'],
            ['número', '# Pedidos al día', 'pedidos_diarios', 'Obligatorio · entero de 1 a 10.000', 'solicitud'],
            ['área de texto', 'Mensaje (opcional)', 'mensaje', 'Opcional · máx. 1.000 caracteres', 'solicitud'],
            ['botón (enviar)', 'Quiero ser aliado', '—', 'Valida y envía', 'solicitud'],
          ],
          llamadas: [
            {
              id: 'solicitud', nombre: 'Enviar solicitud de comercio', metodo: 'POST', ruta: '/api/publico/solicitudes', auth: pub,
              cuando: 'Al tocar "Quiero ser aliado" con el formulario válido.',
              envia: [
                ['comercio', 'texto', true, 'Panadería El Buen Pan', ''],
                ['ubicacion', 'texto', true, 'Cra 15 # 80-20, Bogotá', ''],
                ['celular', 'texto', true, '3100000000', 'Solo dígitos (el frontend quita espacios)'],
                ['pedidos_diarios', 'entero', true, 20, ''],
                ['mensaje', 'texto', false, 'Vendemos pan y tortas a domicilio', ''],
                ['origen', 'texto', false, 'web/unete?utm_source=instagram', 'Página y UTM'],
              ],
              recibe: [
                ['id', 'uuid', true, '5b2e…', ''],
                ['mensaje', 'texto', true, '¡Listo! Te escribimos por WhatsApp en menos de un día hábil.', 'Para mostrar'],
              ],
              tablas: 'solicitudes_comercio', errores: [['422', 'Campo inválido (llega "campos")'], ['429', 'Demasiados envíos desde la misma IP']],
            },
          ],
        },
        {
          id: 'web-contacto', nombre: 'Contacto', archivo: 'Pages/indexcontacto.html',
          controles: [
            ['enlace', 'Escríbenos por WhatsApp', '—', 'wa.me', 'externo'],
            ['botón', 'Copiar correo de ventas / soporte / tecnología / general', '—', 'Copia al portapapeles', 'local'],
            ['enlace', 'ventas@ · soporte@ · dev@ · contacto@', '—', 'mailto:', 'externo'],
            ['botón', 'Alejar / Acercar mapa de ubicación', '—', 'Zoom', 'local'],
          ],
          llamadas: [],
          nota: 'Contacto no tiene formulario: todo va por WhatsApp o correo. La tabla mensajes_contacto queda lista por si se agrega uno.',
        },
      ],
    },
    // =================================================================
    {
      id: 'app', nombre: 'AppWeb (PWA)', repo: 'frontend_appweb', color: '#B5DB2E',
      txt: 'Inicio de sesión, panel del comercio y panel del repartidor.',
      pantallas: [
        {
          id: 'app-login', nombre: 'Inicio de sesión', archivo: 'index.html',
          controles: [
            ['texto', 'Usuario', 'usuario', 'Obligatorio · sin espacios, minúsculas', 'login'],
            ['contraseña', 'Contraseña', 'password', 'Obligatorio', 'login'],
            ['botón', 'Mostrar contraseña (ojo)', '—', 'Muestra u oculta', 'local'],
            ['botón (enviar)', 'Ingresar', '—', 'Envía; si falla, sacude el formulario', 'login'],
          ],
          llamadas: [
            {
              id: 'login', nombre: 'Iniciar sesión', metodo: 'POST', ruta: '/api/login', auth: pub,
              cuando: 'Al tocar "Ingresar". Ya está conectado en Scripts-index.js (API_LOGIN).',
              envia: [
                ['usuario', 'texto', true, 'demo', ''],
                ['password', 'texto', true, '••••••', 'Así lo envía hoy la AppWeb'],
              ],
              recibe: 'Sesion',
              tablas: 'usuarios, sesiones, intentos_ingreso',
              errores: [['401', '"Usuario o contraseña incorrectos"'], ['423', 'Usuario bloqueado por intentos'], ['429', 'Límite de Nginx: 10 por minuto']],
            },
          ],
        },
        {
          id: 'app-comercio', nombre: 'Comercio · Mis pedidos', archivo: 'Pages/Pages-stores.html',
          controles: [
            ['botón', 'Todos · Por recoger · En camino · Entregados · No entregados', 'estado', 'Filtra la lista (con contador)', 'mis-pedidos'],
            ['botón (fila)', 'Cada pedido de la lista', 'id', 'Abre el detalle', 'pedido-detalle'],
            ['botón', 'Nuevo pedido', '—', 'Abre el formulario', 'local'],
            ['botón', 'Abrir mi cuenta (iniciales)', '—', 'Abre la hoja de cuenta', 'yo'],
          ],
          llamadas: [
            {
              id: 'mis-pedidos', nombre: 'Lista de pedidos del comercio', metodo: 'GET', ruta: '/api/pedidos?desde=&estado=', auth,
              cuando: 'Al abrir la página y al volver a ella. El filtro se hace en el navegador.',
              envia: null,
              recibe: [
                ['pedidos[]', 'PedidoResumen', true, null, 'Más recientes primero'],
                ['contadores.todos', 'entero', true, 6, ''],
                ['contadores.por_recoger', 'entero', true, 2, ''],
                ['contadores.en_camino', 'entero', true, 2, 'recogido + en_camino'],
                ['contadores.entregado', 'entero', true, 1, ''],
                ['contadores.no_entregado', 'entero', true, 1, ''],
              ],
              tablas: 'pedidos', errores: [['401', 'Token vencido: se renueva con /api/refrescar']],
            },
            {
              id: 'pedido-detalle', nombre: 'Detalle del pedido', metodo: 'GET', ruta: '/api/pedidos/:id', auth,
              cuando: 'Al tocar un pedido.', envia: null, recibe: 'PedidoDetalle',
              tablas: 'pedidos, pedido_eventos, comercios, usuarios', errores: [['404', 'No existe o no es de este comercio']],
            },
          ],
        },
        {
          id: 'app-nuevo', nombre: 'Comercio · Nuevo pedido', archivo: 'Pages/Pages-stores.html (hoja "Nuevo pedido")',
          controles: [
            ['opción (radio)', 'Zona de entrega: Bogotá / Funza / Soacha (con tarifa)', 'zona', 'Obligatorio · una opción', 'crear-pedido'],
            ['texto', 'Dirección de entrega', 'direccion', 'Obligatorio · 5 a 120 caracteres', 'crear-pedido'],
            ['texto', 'Nombre de quien recibe', 'nombre', 'Obligatorio · 2 a 60 caracteres', 'crear-pedido'],
            ['teléfono', 'Celular de quien recibe', 'telefono', 'Obligatorio · 10 dígitos (se formatea 300 123 4567)', 'crear-pedido'],
            ['texto (moneda)', 'Valor a cobrar al cliente', 'cobro', 'Opcional · pesos, vacío = ya pagado', 'crear-pedido'],
            ['área de texto', 'Notas para el repartidor (opcional)', 'notas', 'Opcional · máx. 300 caracteres', 'crear-pedido'],
            ['resumen', 'Zona · Envío · Cobro (se calcula al escribir)', '—', 'Muestra la tarifa', 'local'],
            ['botón (enviar)', 'Crear pedido', '—', 'Valida y envía', 'crear-pedido'],
            ['botón', 'Cerrar (×) / tocar el fondo', '—', 'Cierra la hoja', 'local'],
          ],
          llamadas: [
            {
              id: 'crear-pedido', nombre: 'Crear pedido', metodo: 'POST', ruta: '/api/pedidos', auth,
              cuando: 'Al tocar "Crear pedido". La API geocodifica la dirección; la base pone tarifa, localidad, zona y repartidor.',
              envia: [
                ['zona', 'texto', true, 'bogota', 'bogota · funza · soacha (municipio)'],
                ['direccion', 'texto', true, 'Calle 72 #10-34', ''],
                ['nombre', 'texto', true, 'Andrea Gómez', ''],
                ['telefono', 'texto', true, '3001234567', 'Solo dígitos'],
                ['cobro', 'entero', true, 45000, '0 si ya está pagado'],
                ['notas', 'texto', false, 'Entregar en portería', ''],
              ],
              recibe: 'PedidoDetalle',
              tablas: 'pedidos (+ pedido_eventos y asignaciones por triggers)',
              errores: [['422', 'Campo inválido o dirección que no se pudo ubicar'], ['409', 'Fuera del horario de operación']],
            },
          ],
        },
        {
          id: 'app-detalle', nombre: 'Comercio · Detalle del pedido', archivo: 'Pages/Pages-stores.html (hoja del pedido)',
          controles: [
            ['botón (lápiz)', 'Editar dirección / celular / notas', 'direccion · telefono · notas', 'Solo mientras está "Por recoger"', 'editar-pedido'],
            ['botón', 'Descargar (guía PDF)', '—', 'Guía para pegar al paquete', 'guia'],
            ['botón', 'Eliminar pedido', '—', 'Pide confirmar ("Toca de nuevo para confirmar")', 'cancelar-pedido'],
            ['botón', 'Cerrar', '—', 'Cierra la hoja', 'local'],
          ],
          llamadas: [
            {
              id: 'editar-pedido', nombre: 'Editar pedido', metodo: 'PATCH', ruta: '/api/pedidos/:id', auth,
              cuando: 'Al guardar un campo editado.',
              envia: [
                ['direccion', 'texto', false, 'Calle 72 #10-34, apto 501', 'Solo los campos que cambian'],
                ['telefono', 'texto', false, '3001234567', ''],
                ['notas', 'texto', false, 'Llamar antes', ''],
              ],
              recibe: 'PedidoDetalle', tablas: 'pedidos, auditoria', errores: [['409', 'Ya lo recogieron: no se puede editar']],
            },
            {
              id: 'guia', nombre: 'Guía del pedido (PDF)', metodo: 'GET', ruta: '/api/pedidos/:id/guia.pdf', auth,
              cuando: 'Al tocar "Descargar".', envia: null,
              recibe: [['(archivo)', 'PDF', true, 'application/pdf', 'Código LOE-…, destinatario, dirección, cobro y código de barras Code 128']],
              tablas: 'pedidos', errores: [],
            },
            {
              id: 'cancelar-pedido', nombre: 'Eliminar (cancelar) pedido', metodo: 'POST', ruta: '/api/pedidos/:id/cancelar', auth,
              cuando: 'Al confirmar "Eliminar pedido". No se borra: queda en estado cancelado.', envia: null,
              recibe: [['id', 'uuid', true, 'a41f…', ''], ['estado', 'texto', true, 'cancelado', '']],
              tablas: 'pedidos, pedido_eventos', errores: [['409', 'Ya lo recogieron']],
            },
          ],
        },
        {
          id: 'app-cuenta', nombre: 'Cuenta (comercio y repartidor)', archivo: 'Pages/Pages-stores.html · Pages-repartidor.html (hoja "Mi cuenta")',
          controles: [
            ['botón (lápiz)', 'Editar dirección (comercio)', 'direccion', 'Dirección de recogida', 'editar-cuenta'],
            ['botón (lápiz)', 'Editar celular (comercio)', 'celular', '10 dígitos', 'editar-cuenta'],
            ['botón (lápiz)', 'Editar correo (comercio)', 'correo', 'Correo válido', 'editar-cuenta'],
            ['botón (radio)', 'Tema: Claro · Oscuro · Auto', 'tema', 'Se aplica al instante y se guarda', 'tema'],
            ['botón', 'Cerrar sesión', '—', 'Borra auth_token y vuelve al inicio', 'salir'],
          ],
          llamadas: [
            {
              id: 'yo', nombre: 'Mis datos', metodo: 'GET', ruta: '/api/yo', auth,
              cuando: 'Al abrir la página.', envia: null,
              recibe: [
                ['usuario', 'Usuario', true, null, ''],
                ['comercio.nombre', 'texto', false, 'Tienda Central', 'Solo si es comercio'],
                ['comercio.localidad', 'texto', false, 'Chapinero', ''],
                ['comercio.direccion', 'texto', false, 'Calle 80 #15-20', ''],
                ['comercio.celular', 'texto', false, '3001112233', ''],
                ['comercio.correo', 'texto', false, 'hola@tiendacentral.co', ''],
                ['repartidor.zona', 'texto', false, 'Bogotá y alrededores', 'Solo si es repartidor'],
              ],
              tablas: 'usuarios, comercios, puntos_recogida, repartidores', errores: [],
            },
            {
              id: 'editar-cuenta', nombre: 'Editar datos del comercio', metodo: 'PATCH', ruta: '/api/yo/comercio', auth,
              cuando: 'Al guardar un campo de la cuenta.',
              envia: [
                ['direccion', 'texto', false, 'Calle 80 #15-20', 'Solo los que cambian'],
                ['celular', 'texto', false, '3001112233', ''],
                ['correo', 'texto', false, 'hola@tiendacentral.co', ''],
              ],
              recibe: [['ok', 'booleano', true, true, '']], tablas: 'comercios, puntos_recogida, auditoria', errores: [['422', 'Dato inválido']],
            },
            {
              id: 'tema', nombre: 'Guardar tema', metodo: 'PATCH', ruta: '/api/yo', auth,
              cuando: 'Al elegir Claro, Oscuro o Auto. También se guarda en el navegador.',
              envia: [['tema', 'texto', true, 'oscuro', 'claro · oscuro · auto']],
              recibe: [['ok', 'booleano', true, true, '']], tablas: 'usuarios', errores: [],
            },
            {
              id: 'salir', nombre: 'Cerrar sesión', metodo: 'POST', ruta: '/api/salir', auth,
              cuando: 'Al tocar "Cerrar sesión".', envia: null,
              recibe: [['ok', 'booleano', true, true, '']], tablas: 'sesiones', errores: [],
            },
          ],
        },
        {
          id: 'app-repartidor', nombre: 'Repartidor · Mi ruta', archivo: 'Pages/Pages-repartidor.html',
          controles: [
            ['botón', 'Pendientes · Por recoger · En camino · Completados · Todos', 'estado', 'Filtra la lista (con contador)', 'ruta'],
            ['botón (fila)', 'Cada trabajo: "Recoger en…" o "Entregar al cliente"', 'id', 'Abre el detalle', 'pedido-detalle-rep'],
            ['resumen', 'Cobrado hoy · Por cobrar', '—', 'Se calcula con la ruta', 'ruta'],
            ['botón', 'Abrir mi cuenta', '—', 'Tema y cerrar sesión (ver "Cuenta")', 'yo'],
          ],
          llamadas: [
            {
              id: 'ruta', nombre: 'Mi ruta del día', metodo: 'GET', ruta: '/api/ruta?fecha=', auth,
              cuando: 'Al abrir la página y cada 60 s mientras está visible.', envia: null,
              recibe: [
                ['pedidos[]', 'PedidoResumen', true, null, 'En orden de recorrido'],
                ['pedidos[].recoger_en', 'texto', true, 'Tienda Central', 'Comercio donde se recoge'],
                ['caja.cobrado', 'entero', true, 32000, 'Cobrado en entregados'],
                ['caja.pendiente', 'entero', true, 135400, 'Por cobrar en pendientes'],
              ],
              tablas: 'pedidos, comercios', errores: [],
            },
            {
              id: 'pedido-detalle-rep', nombre: 'Detalle del trabajo', metodo: 'GET', ruta: '/api/pedidos/:id', auth,
              cuando: 'Al tocar un trabajo.', envia: null, recibe: 'PedidoDetalle', tablas: 'pedidos, pedido_eventos', errores: [['403', 'No es su pedido']],
            },
          ],
        },
        {
          id: 'app-trabajo', nombre: 'Repartidor · Trabajo y novedad', archivo: 'Pages/Pages-repartidor.html (hojas del trabajo y "No se pudo entregar")',
          controles: [
            ['enlace', 'Llamar', '—', 'tel:', 'externo'],
            ['enlace', 'WhatsApp', '—', 'wa.me', 'externo'],
            ['enlace', 'Cómo llegar (Maps)', '—', 'Google Maps con la dirección', 'externo'],
            ['deslizador', 'Desliza: Ya lo recogí / Voy en camino / Lo entregué', 'estado', 'Avanza un paso; Enter o Espacio también confirman', 'estado'],
            ['botón', 'No se pudo entregar', '—', 'Abre la hoja de novedad', 'local'],
            ['opción (radio)', 'No contesta · Dirección errada · Rechazó el pedido · No había nadie · Otro motivo', 'motivo', 'Obligatorio para reportar', 'novedad'],
            ['botón (enviar)', 'Reportar novedad', '—', 'Se activa al elegir motivo', 'novedad'],
            ['botón', 'Subir foto de entrega', 'archivo', 'Opcional · JPG/PNG máx. 8 MB', 'evidencia'],
          ],
          llamadas: [
            {
              id: 'estado', nombre: 'Avanzar estado', metodo: 'POST', ruta: '/api/pedidos/:id/estado', auth,
              cuando: 'Al terminar de deslizar.',
              envia: [['estado', 'texto', true, 'en_camino', 'El siguiente: recogido → en_camino → entregado']],
              recibe: [['pedido', 'PedidoResumen', true, null, ''], ['mensaje', 'texto', false, '¡Entregado! +$45.000', 'Para el aviso']],
              tablas: 'pedidos, pedido_eventos, notificaciones', errores: [['409', 'Paso no válido (la base lo rechaza)']],
            },
            {
              id: 'novedad', nombre: 'Reportar no entregado', metodo: 'POST', ruta: '/api/pedidos/:id/estado', auth,
              cuando: 'Al tocar "Reportar novedad".',
              envia: [
                ['estado', 'texto', true, 'no_entregado', ''],
                ['motivo', 'texto', true, 'no_contesta', 'no_contesta · direccion · rechazado · ausente · otro'],
                ['detalle', 'texto', false, 'Timbré 3 veces', 'Opcional'],
              ],
              recibe: [['pedido', 'PedidoResumen', true, null, '']],
              tablas: 'pedidos, pedido_eventos, notificaciones', errores: [['422', 'Falta el motivo']],
            },
            {
              id: 'evidencia', nombre: 'Subir evidencia', metodo: 'POST', ruta: '/api/pedidos/:id/evidencias', auth,
              cuando: 'Al tomar la foto. Va como multipart/form-data, no JSON.',
              envia: [['archivo', 'archivo', true, 'foto.jpg', 'multipart'], ['tipo', 'texto', true, 'foto_entrega', 'foto_entrega · firma · foto_fachada']],
              recibe: [['id', 'uuid', true, '91ab…', ''], ['url', 'texto', true, 'https://…/evidencias/91ab.jpg', 'Enlace firmado, 1 hora']],
              tablas: 'archivos, evidencias', errores: [['413', 'Archivo de más de 8 MB']],
            },
          ],
        },
      ],
    },
    // =================================================================
    {
      id: 'admin', nombre: 'Panel admin', repo: 'frontend_admin', color: '#5A48D6',
      txt: 'Inicio de sesión, Resumen, Pedidos, Comercios, Repartidores, Mapa, Enlaces e Intercambio.',
      pantallas: [
        {
          id: 'adm-login', nombre: 'Inicio de sesión', archivo: 'index.html',
          controles: [
            ['texto', 'Usuario', 'usuario', 'Obligatorio', 'login'],
            ['contraseña', 'Contraseña', 'password', 'Obligatorio', 'login'],
            ['botón', 'Mostrar contraseña', '—', 'Muestra u oculta', 'local'],
            ['botón (enviar)', 'Entrar al panel', '—', 'Solo entra si rol = admin', 'login'],
            ['enlace', 'contacto@loentrego.com', '—', 'mailto:', 'externo'],
          ],
          llamadas: [],
          nota: 'Usa la misma llamada "Iniciar sesión" de la AppWeb (POST /api/login). Si el rol no es admin, la API responde 403.',
        },
        {
          id: 'adm-barra', nombre: 'Barra superior (todas las secciones)', archivo: 'Pages/paneladmin.html',
          controles: [
            ['búsqueda', 'Buscar pedido, comercio o repartidor', 'q', 'Desde 2 caracteres · espera 250 ms al escribir', 'buscar'],
            ['opción (lista)', 'Cada resultado', 'tipo + id', 'Abre la ficha lateral', 'ficha'],
            ['botón', 'Cuenta (iniciales)', '—', 'Abre el menú', 'local'],
            ['botón (radio)', 'Tema: Claro · Oscuro · Auto', 'tema', 'Se guarda', 'tema'],
            ['botón', 'Cerrar sesión', '—', '', 'salir'],
            ['botón', 'Cerrar ficha (× o fondo)', '—', '', 'local'],
          ],
          llamadas: [
            {
              id: 'buscar', nombre: 'Búsqueda global', metodo: 'GET', ruta: '/api/admin/buscar?q=', auth,
              cuando: 'Al escribir en el buscador.', envia: null,
              recibe: [
                ['resultados[]', 'lista', true, null, 'Máx. 12, los más relevantes primero'],
                ['resultados[].tipo', 'texto', true, 'pedido', 'pedido · comercio · repartidor'],
                ['resultados[].id', 'texto', true, 'a41f…', ''],
                ['resultados[].titulo', 'texto', true, 'LOE-0001042 · Andrea Gómez', ''],
                ['resultados[].detalle', 'texto', true, 'En camino · Tienda Central', ''],
              ],
              tablas: 'pedidos, comercios, usuarios', errores: [],
            },
            {
              id: 'ficha', nombre: 'Ficha lateral', metodo: 'GET', ruta: '/api/admin/:tipo/:id', auth,
              cuando: 'Al abrir un resultado o una fila. :tipo = pedidos · comercios · repartidores.', envia: null,
              recibe: [['ficha', 'PedidoDetalle | FichaComercio | FichaRepartidor', true, null, 'Según el tipo']],
              tablas: 'según el tipo', errores: [['404', 'No existe']],
            },
          ],
        },
        {
          id: 'adm-resumen', nombre: 'Resumen', archivo: 'Pages/paneladmin.html',
          controles: [
            ['botón (radio)', 'Hoy · 1 mes · 6 meses · 1 año · Histórico', 'periodo', 'hoy · 1m · 6m · 1a · todo', 'resumen'],
            ['tarjetas', 'Pedidos, entregados, efectividad, recaudo, ingresos', '—', 'Solo lectura', 'resumen'],
            ['tarjetas', 'Google Business · Instagram · Facebook', '—', 'Solo lectura', 'resumen'],
            ['listas en movimiento', 'Reseñas y actividad reciente', '—', 'Solo lectura', 'resumen'],
          ],
          llamadas: [
            {
              id: 'resumen', nombre: 'Cifras del Resumen', metodo: 'GET', ruta: '/api/admin/resumen?periodo=', auth,
              cuando: 'Al entrar y al cambiar de periodo.', envia: null,
              recibe: [
                ['periodo', 'texto', true, '1m', ''],
                ['pedidos', 'entero', true, 1284, ''],
                ['entregados', 'entero', true, 1201, ''],
                ['no_entregados', 'entero', true, 37, ''],
                ['efectividad', 'decimal', true, 97.0, 'Porcentaje'],
                ['recaudo', 'entero', true, 48250000, 'Pesos'],
                ['ingresos_envio', 'entero', true, 12010000, ''],
                ['serie[]', 'lista', true, null, 'Un punto por día (o por mes en 6 m, 1 año e histórico)'],
                ['serie[].fecha', 'fecha', true, '2026-11-01', ''],
                ['serie[].pedidos', 'entero', true, 41, ''],
                ['redes[]', 'lista', true, null, ''],
                ['redes[].red', 'texto', true, 'google', 'google · instagram · facebook'],
                ['redes[].seguidores', 'entero', false, 1830, ''],
                ['redes[].calificacion', 'decimal', false, 4.8, 'Google'],
                ['redes[].resenas', 'entero', false, 212, ''],
                ['resenas[]', 'lista', true, null, 'Últimas 10'],
                ['resenas[].autor', 'texto', true, 'María P.', ''],
                ['resenas[].estrellas', 'entero', true, 5, ''],
                ['resenas[].texto', 'texto', true, 'Llegó rapidísimo', ''],
              ],
              tablas: 'v_resumen_diario, metricas_redes, resenas', errores: [],
            },
          ],
        },
        {
          id: 'adm-pedidos', nombre: 'Pedidos', archivo: 'Pages/paneladmin.html',
          controles: [
            ['botón', 'Todos · Por recoger · En camino · Entregados · Novedades', 'estado', 'Filtra (con contador)', 'pedidos-admin'],
            ['botón (radio)', 'Por repartidor · Lista', 'agrupar', 'Solo cambia cómo se ve', 'local'],
            ['botón (fila)', 'Cada pedido', 'id', 'Abre la ficha', 'ficha'],
            ['botón (radio)', 'Cambiar estado (en la ficha)', 'estado', 'Mismas reglas del flujo', 'estado-admin'],
            ['lista (select)', 'Reasignar repartidor (en la ficha)', 'repartidor_id', 'Repartidores de la zona primero', 'reasignar'],
          ],
          llamadas: [
            {
              id: 'pedidos-admin', nombre: 'Pedidos del día', metodo: 'GET', ruta: '/api/admin/pedidos?fecha=&estado=', auth,
              cuando: 'Al entrar a Pedidos.', envia: null,
              recibe: [
                ['pedidos[]', 'PedidoResumen', true, null, ''],
                ['pedidos[].repartidor', 'texto', false, 'Camilo Restrepo', 'Para agrupar'],
                ['pedidos[].comercio', 'texto', true, 'Tienda Central', ''],
                ['contadores', 'objeto', true, { todos: 48, por_recoger: 9, curso: 12, entregado: 25, no_entregado: 2 }, ''],
              ],
              tablas: 'pedidos, comercios, usuarios', errores: [],
            },
            {
              id: 'estado-admin', nombre: 'Cambiar estado (admin)', metodo: 'POST', ruta: '/api/admin/pedidos/:id/estado', auth,
              cuando: 'Al elegir un estado en la ficha.',
              envia: [['estado', 'texto', true, 'entregado', ''], ['motivo', 'texto', false, null, 'Si es no_entregado']],
              recibe: 'PedidoDetalle', tablas: 'pedidos, pedido_eventos, auditoria', errores: [['409', 'Paso no válido']],
            },
            {
              id: 'reasignar', nombre: 'Reasignar repartidor', metodo: 'POST', ruta: '/api/admin/pedidos/:id/repartidor', auth,
              cuando: 'Al cambiar el repartidor en la ficha.',
              envia: [['repartidor_id', 'uuid', true, 'r2', '']],
              recibe: 'PedidoDetalle', tablas: 'pedidos, asignaciones (modo manual)', errores: [['409', 'El pedido ya está cerrado']],
            },
          ],
        },
        {
          id: 'adm-comrep', nombre: 'Comercios y Repartidores', archivo: 'Pages/paneladmin.html',
          controles: [
            ['botón (fila)', 'Cada comercio', 'id', 'Abre la ficha', 'ficha'],
            ['botón (fila)', 'Cada repartidor', 'id', 'Abre la ficha', 'ficha'],
            ['tarjetas', 'Estadísticas de cada uno', '—', 'Solo lectura', 'comercios'],
          ],
          llamadas: [
            {
              id: 'comercios', nombre: 'Lista de comercios', metodo: 'GET', ruta: '/api/admin/comercios?periodo=', auth,
              cuando: 'Al entrar a Comercios.', envia: null,
              recibe: [['comercios[]', 'FichaComercio', true, null, '']], tablas: 'v_comercios', errores: [],
            },
            {
              id: 'repartidores', nombre: 'Lista de repartidores', metodo: 'GET', ruta: '/api/admin/repartidores?periodo=', auth,
              cuando: 'Al entrar a Repartidores, a Intercambio y al crear una zona.', envia: null,
              recibe: [['repartidores[]', 'FichaRepartidor', true, null, '']], tablas: 'v_repartidores', errores: [],
            },
          ],
        },
        {
          id: 'adm-mapa', nombre: 'Mapa · Localidades, Calor y Zonas de reparto', archivo: 'Pages/paneladmin.html · Scripts/mapa-zonas.js',
          controles: [
            ['botón (capa)', 'Localidades', '—', 'Muestra u oculta', 'localidades'],
            ['botón (capa)', 'Calor', 'periodo', 'Pedidos por localidad', 'demanda'],
            ['botón (radio)', 'Ver · Editar', 'modo', 'Modo del mapa', 'local'],
            ['botón', 'Acercar · Alejar · Ver todo', '—', 'Zoom animado', 'local'],
            ['botón (lista)', 'Cada localidad / cada zona', 'id', 'Abre su detalle', 'local'],
            ['botón', '+ Nueva zona', '—', 'Primero el repartidor, luego el contorno', 'repartidores'],
            ['opción (radio)', 'Repartidor de la zona', 'repartidores[0]', 'Obligatorio · uno', 'guardar-zona'],
            ['texto', 'Nombre de la zona', 'nombre', 'Obligatorio · máx. 40', 'guardar-zona'],
            ['número', 'Capacidad (pedidos al día por repartidor)', 'capacidad_diaria', 'Entero ≥ 1', 'guardar-zona'],
            ['clics en el mapa', 'Contorno (puntos)', 'geometry', 'Mínimo 3 puntos', 'guardar-zona'],
            ['botón', 'Quitar último · Cancelar (×) · Crear zona', '—', 'Durante el dibujo', 'guardar-zona'],
            ['arrastre', 'Mover / agregar / quitar puntos (doble clic)', 'geometry', 'Las vecinas se recortan solas', 'guardar-zona'],
            ['botón', 'Editar zona', '—', '', 'local'],
            ['botón', 'Eliminar zona', '—', 'Pide confirmar', 'borrar-zona'],
            ['archivo (oculto)', 'Importar GeoJSON', 'archivo', '.geojson / .json', 'importar-zonas'],
          ],
          llamadas: [
            {
              id: 'zonas', nombre: 'Zonas de reparto', metodo: 'GET', ruta: '/api/admin/zonas', auth,
              cuando: 'Al abrir el mapa (hoy se guardan en localStorage "loentrego-admin-zonas-v2").', envia: null,
              recibe: [['type', 'texto', true, 'FeatureCollection', ''], ['features[]', 'ZonaFeature', true, null, '']],
              tablas: 'zonas_reparto, zona_repartidores, v_cobertura_zonas', errores: [],
            },
            {
              id: 'localidades', nombre: 'Localidades', metodo: 'GET', ruta: '/api/admin/mapa/localidades', auth,
              cuando: 'Al abrir el mapa (hoy sale de Scripts/territorio.json). Se puede cachear un día.', envia: null,
              recibe: [
                ['type', 'texto', true, 'FeatureCollection', ''],
                ['features[].id', 'texto', true, 'chapinero', ''],
                ['features[].properties.nombre', 'texto', true, 'Chapinero', ''],
                ['features[].properties.municipio', 'texto', true, 'bogota', ''],
                ['features[].properties.aproximado', 'booleano', true, false, 'Comunas de Soacha: true'],
                ['features[].geometry', 'objeto', true, null, 'MultiPolygon'],
              ],
              tablas: 'localidades', errores: [],
            },
            {
              id: 'demanda', nombre: 'Demanda por localidad (Calor)', metodo: 'GET', ruta: '/api/admin/mapa/demanda?periodo=', auth,
              cuando: 'Al activar Calor o cambiar de periodo.', envia: null,
              recibe: [
                ['localidades[]', 'lista', true, null, ''],
                ['localidades[].id', 'texto', true, 'chapinero', ''],
                ['localidades[].pedidos', 'entero', true, 312, ''],
                ['localidades[].repartidores', 'decimal', true, 1.5, 'Fracción de repartidores en la localidad'],
              ],
              tablas: 'v_demanda_localidad, zona_repartidores', errores: [],
            },
            {
              id: 'guardar-zona', nombre: 'Crear o editar zona', metodo: 'PUT', ruta: '/api/admin/zonas/:id', auth,
              cuando: 'Al tocar "Crear zona" o al soltar un punto editado. Incluye las vecinas recortadas.',
              envia: [
                ['zona', 'ZonaFeature', true, null, 'La zona creada o editada'],
                ['vecinas[]', 'ZonaFeature', false, null, 'Vecinas que cambiaron por el recorte'],
                ['eliminadas[]', 'lista', false, ['bosa-2'], 'Zonas que quedaron cubiertas por completo'],
              ],
              recibe: [['type', 'texto', true, 'FeatureCollection', 'Todas las zonas, ya guardadas'], ['features[]', 'ZonaFeature', true, null, '']],
              tablas: 'zonas_reparto, zona_repartidores, auditoria', errores: [['422', 'Polígono inválido o zona sin repartidor']],
            },
            {
              id: 'borrar-zona', nombre: 'Eliminar zona', metodo: 'DELETE', ruta: '/api/admin/zonas/:id', auth,
              cuando: 'Al confirmar "Eliminar zona". Se archiva (archivado_en).', envia: null,
              recibe: [['ok', 'booleano', true, true, '']], tablas: 'zonas_reparto, auditoria', errores: [],
            },
            {
              id: 'importar-zonas', nombre: 'Importar zonas (GeoJSON)', metodo: 'PUT', ruta: '/api/admin/zonas', auth,
              cuando: 'Al elegir un archivo. El panel corrige [lat, lon] y avisa qué cambió antes de enviar.',
              envia: [['type', 'texto', true, 'FeatureCollection', ''], ['features[]', 'ZonaFeature', true, null, 'Reemplaza todas']],
              recibe: [['features[]', 'ZonaFeature', true, null, '']], tablas: 'zonas_reparto, zona_repartidores, auditoria', errores: [['422', 'GeoJSON inválido']],
            },
          ],
        },
        {
          id: 'adm-enlaces', nombre: 'Enlaces de registro', archivo: 'Pages/paneladmin.html',
          controles: [
            ['url', 'URL del formulario (repartidor)', 'url_base', 'URL https válida', 'crear-enlace'],
            ['botón', 'Generar enlace (repartidor)', 'rol = "repartidor"', '', 'crear-enlace'],
            ['url', 'URL del formulario (comercio)', 'url_base', 'URL https válida', 'crear-enlace'],
            ['botón', 'Generar enlace (comercio)', 'rol = "comercio"', '', 'crear-enlace'],
            ['botón', 'Copiar (cada enlace)', '—', 'Copia al portapapeles', 'local'],
            ['botón', 'Eliminar (cada enlace)', 'id', 'Lo revoca', 'borrar-enlace'],
          ],
          llamadas: [
            {
              id: 'enlaces', nombre: 'Enlaces generados', metodo: 'GET', ruta: '/api/admin/enlaces', auth,
              cuando: 'Al entrar a Enlaces.', envia: null,
              recibe: [
                ['enlaces[]', 'lista', true, null, 'Solo los vigentes'],
                ['enlaces[].id', 'uuid', true, '3c9d…', ''],
                ['enlaces[].rol', 'texto', true, 'repartidor', ''],
                ['enlaces[].url', 'texto', true, 'https://loentrego.com/registro-repartidor?t=Xk2…', ''],
                ['enlaces[].usos', 'entero', true, 0, ''],
                ['enlaces[].usos_max', 'entero', true, 1, ''],
                ['enlaces[].vence', 'fecha-hora', true, '2026-11-30T23:59:00-05:00', ''],
              ],
              tablas: 'enlaces_registro', errores: [],
            },
            {
              id: 'crear-enlace', nombre: 'Generar enlace', metodo: 'POST', ruta: '/api/admin/enlaces', auth,
              cuando: 'Al tocar "Generar enlace".',
              envia: [
                ['rol', 'texto', true, 'repartidor', 'repartidor · comercio'],
                ['url_base', 'texto', true, 'https://loentrego.com/registro-repartidor', ''],
                ['usos_max', 'entero', false, 1, 'Por defecto 1'],
                ['dias', 'entero', false, 7, 'Vigencia, por defecto 7'],
              ],
              recibe: [['id', 'uuid', true, '3c9d…', ''], ['url', 'texto', true, 'https://loentrego.com/registro-repartidor?t=Xk2…', 'url_base + token'], ['vence', 'fecha-hora', true, '2026-11-30T23:59:00-05:00', '']],
              tablas: 'enlaces_registro', errores: [['422', 'URL inválida']],
            },
            {
              id: 'borrar-enlace', nombre: 'Eliminar enlace', metodo: 'DELETE', ruta: '/api/admin/enlaces/:id', auth,
              cuando: 'Al tocar "Eliminar".', envia: null, recibe: [['ok', 'booleano', true, true, '']], tablas: 'enlaces_registro (revocado_en)', errores: [],
            },
          ],
        },
        {
          id: 'adm-intercambio', nombre: 'Intercambio de repartidor', archivo: 'Pages/paneladmin.html',
          controles: [
            ['lista (select)', 'Repartidor actual', 'repartidor_origen', 'Obligatorio', 'intercambio'],
            ['lista (select)', 'Nuevo repartidor', 'repartidor_destino', 'Obligatorio · distinto al actual', 'intercambio'],
            ['lista (select)', 'Paquete', 'pedido_id', 'Pedidos activos del repartidor actual', 'pedidos-de'],
            ['botón', 'Intercambiar repartidor', '—', 'Pide confirmar', 'intercambio'],
          ],
          llamadas: [
            {
              id: 'pedidos-de', nombre: 'Paquetes del repartidor', metodo: 'GET', ruta: '/api/admin/pedidos?repartidor=&activos=1', auth,
              cuando: 'Al elegir el repartidor actual.', envia: null,
              recibe: [['pedidos[]', 'PedidoResumen', true, null, 'Solo por_recoger, recogido y en_camino']], tablas: 'pedidos', errores: [],
            },
            {
              id: 'intercambio', nombre: 'Intercambiar repartidor', metodo: 'POST', ruta: '/api/admin/intercambios', auth,
              cuando: 'Al confirmar.',
              envia: [
                ['repartidor_origen', 'uuid', true, 'r1', ''],
                ['repartidor_destino', 'uuid', true, 'r2', ''],
                ['pedido_id', 'uuid', true, 'a41f…', 'Un paquete (o zona_id para la zona completa)'],
                ['motivo', 'texto', false, 'Moto varada', ''],
              ],
              recibe: [['id', 'uuid', true, '77ee…', ''], ['estado', 'texto', true, 'aprobado', ''], ['pedido', 'PedidoResumen', true, null, '']],
              tablas: 'intercambios, pedidos, asignaciones (modo intercambio)', errores: [['409', 'El paquete ya se entregó']],
            },
          ],
        },
      ],
    },
    // =================================================================
    {
      id: 'links', nombre: 'Links', repo: 'Frontend_Links', color: '#4F8DFF',
      txt: 'Formularios de registro con enlace de un solo uso y la página de enlaces tipo Linktree.',
      pantallas: [
        {
          id: 'lk-comercio', nombre: 'Registro de comercio', archivo: 'form comercio/index.html?t=TOKEN',
          controles: [
            ['texto', 'Nombre del comercio', 'nombre', 'Obligatorio · 2 a 80 caracteres', 'registro-comercio'],
            ['opción (chips)', 'Tienda o local · Tienda en línea · Entidad pública', 'tipo', 'comercio · ecommerce · sector_publico', 'registro-comercio'],
            ['texto', 'Dirección de recogida', 'direccion', 'Obligatorio · 5 a 120 caracteres', 'registro-comercio'],
            ['opción (segmentos)', 'Municipio donde estás: Bogotá · Funza · Soacha', 'municipio', 'Una opción', 'registro-comercio'],
            ['número', 'Pedidos al día (aproximado)', 'pedidos_diarios', 'Obligatorio · entero de 1 a 10.000', 'registro-comercio'],
            ['teléfono', 'Celular', 'celular', '10 dígitos, empieza por 3 (se formatea 300 123 4567)', 'registro-comercio'],
            ['correo', 'Correo', 'correo', 'Correo válido', 'registro-comercio'],
            ['texto', 'Usuario', 'usuario', '4 a 40: minúsculas, números, punto, guion', 'registro-comercio'],
            ['contraseña', 'Contraseña (con ojo y barrita de fuerza)', 'password', 'Mínimo 8 caracteres', 'registro-comercio'],
            ['casilla', 'Acepto el tratamiento de mis datos', 'acepta_datos', 'Obligatoria', 'registro-comercio'],
            ['botón (enviar)', 'Crear cuenta de comercio', '—', 'Valida y envía', 'registro-comercio'],
            ['enlace', 'Ir a la app (al terminar)', '—', 'app.loentrego.com', 'externo'],
          ],
          llamadas: [
            {
              id: 'registro-verificar', nombre: 'Revisar el enlace', metodo: 'GET', ruta: '/api/registro/:token', auth: 'Pública',
              cuando: 'Al abrir cualquiera de los dos formularios. Si no es válido, el formulario se bloquea.', envia: null,
              recibe: [['valido', 'booleano', true, true, ''], ['rol', 'texto', true, 'comercio', 'comercio · repartidor'], ['vence', 'fecha-hora', true, '2026-11-30T23:59:00-05:00', ''], ['mensaje', 'texto', false, null, 'Si no es válido']],
              tablas: 'enlaces_registro', errores: [['404', 'El enlace no existe'], ['410', 'Ya se usó o venció']],
            },
            {
              id: 'registro-comercio', nombre: 'Crear cuenta de comercio', metodo: 'POST', ruta: '/api/registro/:token', auth: 'Pública',
              cuando: 'Al tocar "Crear cuenta de comercio". Crea usuario, comercio y punto de recogida, y gasta el enlace.',
              envia: [
                ['rol', 'texto', true, 'comercio', ''],
                ['nombre', 'texto', true, 'Panadería La Espiga', ''],
                ['tipo', 'texto', true, 'ecommerce', ''],
                ['direccion', 'texto', true, 'Cra 15 #93-45', ''],
                ['municipio', 'texto', true, 'funza', ''],
                ['pedidos_diarios', 'entero', true, 20, ''],
                ['celular', 'texto', true, '3001234567', 'Solo dígitos'],
                ['correo', 'texto', true, 'hola@laespiga.co', ''],
                ['usuario', 'texto', true, 'laespiga', ''],
                ['password', 'texto', true, '••••••••', ''],
                ['acepta_datos', 'booleano', true, true, ''],
              ],
              recibe: [['usuario', 'texto', true, 'laespiga', ''], ['rol', 'texto', true, 'comercio', ''], ['mensaje', 'texto', true, 'Tu comercio quedó activo', '']],
              tablas: 'enlaces_registro, registros_por_enlace, usuarios, comercios, comercio_usuarios, puntos_recogida',
              errores: [['409', 'El usuario ya existe (llega en "campos")'], ['410', 'El enlace ya se usó o venció'], ['422', 'Campo inválido']],
            },
          ],
        },
        {
          id: 'lk-repartidor', nombre: 'Registro de repartidor', archivo: 'form repartidor/index.html?t=TOKEN',
          controles: [
            ['texto', 'Nombre completo', 'nombre', 'Nombre y apellido', 'registro-repartidor'],
            ['lista (select)', 'Documento: C.C. · C.E. · PPT · Pasaporte', 'tipo_documento', 'cc · ce · ppt · pasaporte', 'registro-repartidor'],
            ['texto', 'Número de documento', 'documento', '5 a 15 letras o números', 'registro-repartidor'],
            ['teléfono', 'Celular (con WhatsApp)', 'celular', '10 dígitos, empieza por 3', 'registro-repartidor'],
            ['correo', 'Correo', 'correo', 'Correo válido', 'registro-repartidor'],
            ['texto (placa)', 'Placa de la moto', 'placa', 'Obligatorio · formato ABC12D (por ahora solo moto)', 'registro-repartidor'],
            ['texto', 'Usuario', 'usuario', '4 a 40: minúsculas, números, punto, guion', 'registro-repartidor'],
            ['contraseña', 'Contraseña (con ojo y barrita de fuerza)', 'password', 'Mínimo 8 caracteres', 'registro-repartidor'],
            ['casilla', 'Acepto el tratamiento de mis datos', 'acepta_datos', 'Obligatoria', 'registro-repartidor'],
            ['botón (enviar)', 'Crear mi cuenta', '—', 'Valida todo y envía', 'registro-repartidor'],
            ['enlace', 'Escríbenos por WhatsApp · Abrir la app', '—', '', 'externo'],
          ],
          llamadas: [
            {
              id: 'registro-repartidor', nombre: 'Crear cuenta de repartidor', metodo: 'POST', ruta: '/api/registro/:token', auth: 'Pública',
              cuando: 'Al tocar "Crear mi cuenta". La cuenta queda "en proceso" hasta que el administrador la active y le asigne zona. Antes, el enlace se revisa con la misma llamada GET.',
              envia: [
                ['rol', 'texto', true, 'repartidor', ''],
                ['nombre', 'texto', true, 'Camilo Restrepo', ''],
                ['tipo_documento', 'texto', true, 'cc', ''],
                ['documento', 'texto', true, '1012345678', ''],
                ['celular', 'texto', true, '3104445566', ''],
                ['correo', 'texto', true, 'camilo@correo.com', ''],
                ['vehiculo', 'texto', true, 'moto', 'Siempre "moto" por ahora'],
                ['placa', 'texto', true, 'ABC12D', ''],
                ['usuario', 'texto', true, 'camilo.r', ''],
                ['password', 'texto', true, '••••••••', ''],
                ['acepta_datos', 'booleano', true, true, ''],
              ],
              recibe: [['usuario', 'texto', true, 'camilo.r', ''], ['rol', 'texto', true, 'repartidor', ''], ['mensaje', 'texto', true, 'Tu cuenta quedó creada', '']],
              tablas: 'enlaces_registro, registros_por_enlace, usuarios, repartidores (estado en_proceso)',
              errores: [['409', 'Usuario o documento ya registrado'], ['410', 'El enlace ya se usó o venció'], ['422', 'Campo inválido']],
            },
          ],
        },
        {
          id: 'lk-links', nombre: 'Página de enlaces (tipo Linktree)', archivo: 'links/index.html',
          controles: [
            ['botón', 'Compartir', '—', 'Menú de compartir del celular o copia el enlace', 'local'],
            ['enlace (destacado)', 'Escríbenos por WhatsApp', '—', 'wa.me con mensaje', 'externo'],
            ['enlace', 'Quiero enviar con LoEntrego', '—', 'loentrego.com · Únete', 'externo'],
            ['enlace', 'Conoce cómo funciona', '—', 'loentrego.com', 'externo'],
            ['enlace', 'Quiero ser repartidor', '—', 'wa.me con mensaje', 'externo'],
            ['enlace', 'Entrar a la app', '—', 'app.loentrego.com', 'externo'],
            ['enlace', 'Califícanos en Google', '—', 'Reseña de Google Business', 'externo'],
            ['enlace (ícono)', 'WhatsApp · Instagram · Facebook · Correo', '—', '', 'externo'],
          ],
          llamadas: [],
          nota: 'No llama a la API: los enlaces se editan en la lista ENLACES de links/script.js.',
        },
      ],
    },
    // =================================================================
    {
      id: 'mant', nombre: 'Página de mantenimiento', repo: 'frontend-maintenance', color: '#FF8A1F',
      txt: 'Se muestra mientras un recurso está en mantenimiento.',
      pantallas: [
        {
          id: 'mant-pagina', nombre: 'Volvemos pronto', archivo: 'index.html',
          controles: [
            ['botón', 'Reintentar ahora', '—', 'Recarga la página (sin recargas automáticas)', 'canales'],
            ['enlace', 'Escríbenos por WhatsApp', '—', 'wa.me', 'externo'],
            ['enlace', 'contacto@loentrego.com', '—', 'mailto:', 'externo'],
            ['indicador', 'Regreso estimado + cuenta regresiva', 'regreso', 'Hora de Colombia', 'canales'],
            ['lista', 'Estado de cada canal (4)', 'canales', 'ok · warn · fail', 'canales'],
          ],
          llamadas: [
            {
              id: 'canales', nombre: 'Estado de los canales', metodo: 'GET', ruta: '/api/publico/canales', auth: pub,
              cuando: 'Al cargar y al reintentar. Hoy se edita a mano en Script.js (ESTADO) y data-regreso.', envia: null,
              recibe: [
                ['canales[]', 'lista', true, null, 'En orden'],
                ['canales[].canal', 'texto', true, 'App LoEntrego', ''],
                ['canales[].estado', 'texto', true, 'warn', 'ok · warn · fail'],
                ['canales[].texto', 'texto', true, 'En mantenimiento', ''],
                ['regreso', 'fecha-hora', false, '2026-11-23T16:30:00-05:00', 'Vacío = "En unos minutos"'],
                ['mensaje', 'texto', false, null, ''],
              ],
              tablas: 'estado_canales, mantenimientos', errores: [],
            },
          ],
        },
      ],
    },
  ];

  // Rutas que no salen de una pantalla (sistema, servidor, integraciones)
  const EXTRA = [
    ['GET', '/api/salud', 'Monitoreo', 'Responde si la API y la base están arriba.', '—'],
    ['POST', '/api/refrescar', 'AppWeb · Panel', 'Cambia el token de refresco por uno nuevo cuando el de acceso vence.', 'sesiones'],
    ['POST', '/api/push', 'AppWeb', 'Guarda la suscripción de notificaciones del dispositivo.', 'suscripciones_push'],
    ['POST', '/api/publico/calificar/:token', 'Cliente final', 'Califica la entrega desde el enlace de WhatsApp.', 'calificaciones'],
    ['POST', '/api/admin/cierres', 'Admin', 'Registra lo que entregó el repartidor al cerrar caja.', 'cierres_caja'],
    ['POST', '/api/admin/liquidaciones', 'Admin', 'Arma, aprueba y marca como pagada una liquidación.', 'liquidaciones, liquidacion_pedidos'],
    ['PUT', '/api/admin/canales', 'Admin', 'Cambia lo que muestra la página de mantenimiento.', 'estado_canales, mantenimientos'],
    ['POST', '/webhooks/whatsapp', 'Meta', 'Estado de los mensajes enviados (entregado, leído, fallido).', 'notificaciones'],
  ];

  return { TIPOS, FRONTS, EXTRA };
})();
