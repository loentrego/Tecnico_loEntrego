-- =====================================================================
--  LoEntrego · Esquema de base de datos (PostgreSQL 16 + PostGIS 3)
--
--  Un solo esquema para todo el ecosistema:
--    web (formularios) · AppWeb (comercios y repartidores) · panel admin
--    · página de mantenimiento · métricas de redes.
--
--  Cómo correrlo (base vacía):
--    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/esquema.sql
--
--  Convenciones
--    · Nombres en español, en minúscula y con guion bajo.
--    · Llaves: uuid (gen_random_uuid) salvo catálogos pequeños con texto estable
--      (municipios, zonas) que ya usan los frontends.
--    · Dinero en pesos colombianos, entero (bigint): no hay centavos.
--    · Fechas con zona horaria (timestamptz). La operación es en America/Bogota.
--    · Coordenadas WGS84 (SRID 4326). Puntos como geography; polígonos como geometry.
--    · Todo lo que se borra en la app se "archiva" (archivado_en); no se borra la fila.
-- =====================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid(), hash de claves
CREATE EXTENSION IF NOT EXISTS citext;     -- usuario y correo sin distinguir mayúsculas
CREATE EXTENSION IF NOT EXISTS postgis;    -- zonas, localidades y puntos de entrega

SET TIME ZONE 'America/Bogota';

-- =====================================================================
--  0. Tipos (valores cerrados que comparten los frontends)
-- =====================================================================

-- Roles de quien entra a la AppWeb o al panel
CREATE TYPE rol_usuario AS ENUM ('admin', 'comercio', 'repartidor');

-- Ciclo de vida del pedido (igual que ESTADOS en AppWeb/Scripts-app.js)
CREATE TYPE estado_pedido AS ENUM ('por_recoger', 'recogido', 'en_camino', 'entregado', 'no_entregado', 'cancelado');

-- Motivos de "No entregado" (igual que MOTIVOS en AppWeb)
CREATE TYPE motivo_no_entrega AS ENUM ('no_contesta', 'direccion', 'rechazado', 'ausente', 'otro');

CREATE TYPE tipo_comercio AS ENUM ('comercio', 'ecommerce', 'sector_publico');
CREATE TYPE estado_comercio AS ENUM ('activo', 'pausado', 'retirado');
CREATE TYPE estado_repartidor AS ENUM ('en_proceso', 'activo', 'suspendido', 'retirado');
CREATE TYPE tipo_documento AS ENUM ('cc', 'ce', 'ppt', 'pasaporte');

-- Tipos de territorio (localidades de Bogotá, comunas de Soacha, cuadrantes de Funza…)
CREATE TYPE tipo_territorio AS ENUM ('localidad', 'comuna', 'cuadrante', 'rural', 'corregimiento');

CREATE TYPE estado_solicitud AS ENUM ('nueva', 'contactada', 'convertida', 'descartada');
CREATE TYPE estado_liquidacion AS ENUM ('borrador', 'aprobada', 'pagada', 'anulada');
CREATE TYPE estado_cierre AS ENUM ('abierto', 'cuadrado', 'con_diferencia');
CREATE TYPE canal_notificacion AS ENUM ('push', 'correo');
CREATE TYPE estado_envio AS ENUM ('pendiente', 'enviado', 'fallido');
CREATE TYPE red_social AS ENUM ('google', 'instagram', 'facebook');
CREATE TYPE estado_canal AS ENUM ('ok', 'warn', 'fail');   -- igual que la página de mantenimiento

-- =====================================================================
--  Utilidad: "actualizado" se pone solo en cada UPDATE
-- =====================================================================
CREATE FUNCTION tocar_actualizado() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.actualizado := now(); RETURN NEW; END $$;

-- =====================================================================
--  1. ARCHIVOS (fotos de evidencia, documentos, soportes de pago)
--     El binario vive en el almacenamiento de objetos; aquí solo la ficha.
-- =====================================================================
CREATE TABLE archivos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  llave         text NOT NULL UNIQUE,               -- ruta en el almacenamiento (p. ej. evidencias/2026/11/…jpg)
  tipo_mime     text NOT NULL,
  bytes         bigint NOT NULL CHECK (bytes >= 0),
  sha256        text,
  subido_por    uuid,                               -- FK a usuarios (se agrega abajo)
  creado        timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================
--  2. USUARIOS Y ACCESO
-- =====================================================================
CREATE TABLE usuarios (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rol             rol_usuario NOT NULL,
  usuario         citext NOT NULL UNIQUE,            -- con lo que entra (demo, repartidor, admin…)
  clave_hash      text NOT NULL,                     -- crypt(clave, gen_salt('bf')) o argon2 desde el backend
  nombre          text NOT NULL,                     -- nombre del comercio, del repartidor o del admin
  celular         text CHECK (celular ~ '^3[0-9]{9}$'),   -- celular colombiano, solo dígitos
  correo          citext UNIQUE,
  foto_id         uuid REFERENCES archivos(id),
  tema            text NOT NULL DEFAULT 'auto' CHECK (tema IN ('claro', 'oscuro', 'auto')),
  activo          boolean NOT NULL DEFAULT true,
  ultimo_ingreso  timestamptz,
  creado          timestamptz NOT NULL DEFAULT now(),
  actualizado     timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER t_usuarios_act BEFORE UPDATE ON usuarios FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();
ALTER TABLE archivos ADD CONSTRAINT archivos_subido_por_fk FOREIGN KEY (subido_por) REFERENCES usuarios(id);

-- Sesiones: un registro por dispositivo con su token de refresco (se guarda el hash, nunca el token)
CREATE TABLE sesiones (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  token_hash    text NOT NULL UNIQUE,
  dispositivo   text,
  ip            inet,
  creado        timestamptz NOT NULL DEFAULT now(),
  expira        timestamptz NOT NULL,
  revocado_en   timestamptz
);
CREATE INDEX sesiones_usuario_idx ON sesiones (usuario_id) WHERE revocado_en IS NULL;

-- Intentos de ingreso (para bloquear fuerza bruta y para auditoría)
CREATE TABLE intentos_ingreso (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario     citext NOT NULL,
  ip          inet,
  exitoso     boolean NOT NULL,
  ocurrido    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX intentos_ingreso_idx ON intentos_ingreso (usuario, ocurrido DESC);

-- Suscripciones Web Push de la AppWeb (PWA)
CREATE TABLE suscripciones_push (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  endpoint    text NOT NULL UNIQUE,
  p256dh      text NOT NULL,
  auth        text NOT NULL,
  creado      timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================
--  3. TERRITORIO (PostGIS)
-- =====================================================================
CREATE TABLE municipios (
  id            text PRIMARY KEY,                    -- 'bogota', 'funza', 'soacha'
  nombre        text NOT NULL,
  departamento  text NOT NULL,
  activo        boolean NOT NULL DEFAULT true,       -- si hay cobertura
  geom          geometry(MultiPolygon, 4326)
);
CREATE INDEX municipios_geom_idx ON municipios USING gist (geom);

-- Localidades, comunas, cuadrantes: referencia para reportes (no se editan en el panel)
CREATE TABLE localidades (
  id            text PRIMARY KEY,                    -- 'chapinero', 'soacha-comuna-1', …
  municipio_id  text NOT NULL REFERENCES municipios(id),
  nombre        text NOT NULL,
  tipo          tipo_territorio NOT NULL,
  aproximado    boolean NOT NULL DEFAULT false,      -- comunas de Soacha: límite aproximado
  fuente        text,
  geom          geometry(MultiPolygon, 4326) NOT NULL
);
CREATE INDEX localidades_geom_idx ON localidades USING gist (geom);
CREATE INDEX localidades_municipio_idx ON localidades (municipio_id);

-- Tarifas de envío con vigencia (hoy: $10.000 en los tres municipios)
CREATE TABLE tarifas (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  municipio_id    text NOT NULL REFERENCES municipios(id),
  valor           bigint NOT NULL CHECK (valor >= 0),
  vigente_desde   date NOT NULL DEFAULT current_date,
  vigente_hasta   date,
  CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde),
  UNIQUE (municipio_id, vigente_desde)
);

-- =====================================================================
--  4. REPARTIDORES
-- =====================================================================
CREATE TABLE repartidores (
  usuario_id        uuid PRIMARY KEY REFERENCES usuarios(id),   -- 1 a 1 con su usuario
  tipo_documento    tipo_documento NOT NULL DEFAULT 'cc',
  documento         text NOT NULL,
  estado            estado_repartidor NOT NULL DEFAULT 'en_proceso',
  fecha_ingreso     date,
  contacto_emergencia_nombre   text,
  contacto_emergencia_celular  text,
  creado            timestamptz NOT NULL DEFAULT now(),
  actualizado       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tipo_documento, documento)
);
CREATE TRIGGER t_repartidores_act BEFORE UPDATE ON repartidores FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();

-- Documentos del repartidor (cédula, antecedentes) con vencimiento
CREATE TABLE documentos_repartidor (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  repartidor_id   uuid NOT NULL REFERENCES repartidores(usuario_id) ON DELETE CASCADE,
  tipo            text NOT NULL CHECK (tipo IN ('cedula', 'antecedentes', 'otro')),
  archivo_id      uuid NOT NULL REFERENCES archivos(id),
  vence           date,
  verificado_por  uuid REFERENCES usuarios(id),
  verificado_en   timestamptz,
  creado          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX documentos_vence_idx ON documentos_repartidor (vence) WHERE vence IS NOT NULL;

-- Jornadas: cuándo estuvo disponible (no se rastrea su ubicación)
CREATE TABLE jornadas (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  repartidor_id   uuid NOT NULL REFERENCES repartidores(usuario_id),
  inicio          timestamptz NOT NULL DEFAULT now(),
  fin             timestamptz,
  CHECK (fin IS NULL OR fin > inicio)
);
CREATE UNIQUE INDEX jornadas_una_abierta ON jornadas (repartidor_id) WHERE fin IS NULL;

-- =====================================================================
--  5. ZONAS DE REPARTO (editables en el panel: Mapa → Zonas de reparto)
-- =====================================================================
CREATE TABLE zonas_reparto (
  id                text PRIMARY KEY,                -- id estable que usa el panel
  nombre            text NOT NULL,
  municipio_id      text NOT NULL REFERENCES municipios(id),
  capacidad_diaria  int NOT NULL DEFAULT 12 CHECK (capacidad_diaria > 0),  -- pedidos/día por repartidor
  prioridad         int NOT NULL DEFAULT 0,          -- si se solapan, gana la mayor
  geom              geometry(MultiPolygon, 4326) NOT NULL,
  archivado_en      timestamptz,
  creado            timestamptz NOT NULL DEFAULT now(),
  actualizado       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX zonas_reparto_geom_idx ON zonas_reparto USING gist (geom);
CREATE TRIGGER t_zonas_act BEFORE UPDATE ON zonas_reparto FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();

-- Qué repartidores atienden cada zona (toda zona tiene al menos uno: lo valida el backend/panel)
CREATE TABLE zona_repartidores (
  zona_id         text NOT NULL REFERENCES zonas_reparto(id) ON DELETE CASCADE,
  repartidor_id   uuid NOT NULL REFERENCES repartidores(usuario_id),
  desde           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (zona_id, repartidor_id)
);
CREATE INDEX zona_repartidores_rep_idx ON zona_repartidores (repartidor_id);

-- =====================================================================
--  6. COMERCIOS
-- =====================================================================
CREATE TABLE comercios (
  id                uuid PRIMARY KEY REFERENCES usuarios(id),   -- el mismo id de su cuenta de acceso; no se guarda dueño ni responsable
  nombre            text NOT NULL,                   -- nombre comercial
  tipo              tipo_comercio NOT NULL DEFAULT 'comercio',
  estado            estado_comercio NOT NULL DEFAULT 'activo',
  celular           text,                            -- debe tener WhatsApp
  correo            citext,
  -- Punto de recogida: cada comercio tiene uno y el repartidor recoge aquí
  direccion         text NOT NULL,
  detalle           text,                            -- local, bodega, piso, a quién preguntar
  municipio_id      text NOT NULL REFERENCES municipios(id),
  punto             geography(Point, 4326),          -- dirección geocodificada (la pone el backend)
  localidad_id      text REFERENCES localidades(id),
  creado            timestamptz NOT NULL DEFAULT now(),
  actualizado       timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER t_comercios_act BEFORE UPDATE ON comercios FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();
CREATE INDEX comercios_nombre_idx ON comercios (lower(nombre));
CREATE INDEX comercios_punto_idx ON comercios USING gist (punto);

-- =====================================================================
--  7. PEDIDOS (el corazón)
-- =====================================================================
CREATE SEQUENCE pedidos_codigo_seq START 1001;

CREATE TABLE pedidos (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo                text NOT NULL UNIQUE DEFAULT 'LOE-' || lpad(nextval('pedidos_codigo_seq')::text, 7, '0') CHECK (codigo ~ '^[A-Z]{3}-[0-9]{7}$'),   -- LOE-0001041: 3 letras + 7 números (Code 128)
  comercio_id           uuid NOT NULL REFERENCES comercios(id),
  creado_por            uuid REFERENCES usuarios(id),
  -- Destinatario (formulario "Nuevo pedido" de la AppWeb)
  destinatario_nombre   text NOT NULL,
  destinatario_telefono text NOT NULL CHECK (destinatario_telefono ~ '^[0-9]{7,10}$'),
  direccion             text NOT NULL,
  notas                 text,
  -- Ubicación: el municipio lo elige el comercio; punto, localidad y zona los pone el backend
  municipio_id          text NOT NULL REFERENCES municipios(id),
  punto                 geography(Point, 4326),        -- dirección geocodificada
  localidad_id          text REFERENCES localidades(id),
  zona_id               text REFERENCES zonas_reparto(id),
  fuera_de_zona         boolean NOT NULL DEFAULT false, -- quedó en un hueco: revisar
  -- Dinero
  cobro                 bigint NOT NULL DEFAULT 0 CHECK (cobro >= 0),   -- contraentrega; 0 = ya pagado
  tarifa                bigint NOT NULL CHECK (tarifa >= 0),            -- envío congelado al crear
  -- Operación
  repartidor_id         uuid REFERENCES repartidores(usuario_id),
  estado                estado_pedido NOT NULL DEFAULT 'por_recoger',
  motivo                motivo_no_entrega,
  motivo_detalle        text,
  intentos              smallint NOT NULL DEFAULT 1 CHECK (intentos >= 1),
  pedido_origen_id      uuid REFERENCES pedidos(id),   -- reintento de un "no entregado"
  programado_para       date NOT NULL DEFAULT current_date,
  creado                timestamptz NOT NULL DEFAULT now(),
  actualizado           timestamptz NOT NULL DEFAULT now(),
  cerrado_en            timestamptz,                   -- cuando llega a entregado/no_entregado/cancelado
  CHECK ((estado = 'no_entregado') = (motivo IS NOT NULL)),
  CHECK (estado = 'por_recoger' OR estado = 'cancelado' OR repartidor_id IS NOT NULL)
);
CREATE INDEX pedidos_comercio_idx   ON pedidos (comercio_id, creado DESC);
CREATE INDEX pedidos_repartidor_idx ON pedidos (repartidor_id, programado_para) WHERE repartidor_id IS NOT NULL;
CREATE INDEX pedidos_activos_idx    ON pedidos (estado) WHERE estado IN ('por_recoger', 'recogido', 'en_camino');
CREATE INDEX pedidos_zona_dia_idx   ON pedidos (zona_id, programado_para);
CREATE INDEX pedidos_localidad_idx  ON pedidos (localidad_id, creado);
CREATE INDEX pedidos_punto_idx      ON pedidos USING gist (punto);
CREATE TRIGGER t_pedidos_act BEFORE UPDATE ON pedidos FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();

-- Historial: cada cambio de estado con su hora (la "mini-ruta" de la AppWeb)
CREATE TABLE pedido_eventos (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pedido_id   uuid NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  estado      estado_pedido NOT NULL,
  usuario_id  uuid REFERENCES usuarios(id),          -- quién lo cambió (null = sistema)
  nota        text,
  ocurrido    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX pedido_eventos_idx ON pedido_eventos (pedido_id, ocurrido);

-- Asignaciones (dato auxiliar): cada vez que cambia pedidos.repartidor_id queda a quién pasó,
-- a qué hora y quién lo hizo. Sin motivo. El repartidor vigente es el de pedidos.repartidor_id.
CREATE TABLE asignaciones (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pedido_id       uuid NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  repartidor_id   uuid NOT NULL REFERENCES repartidores(usuario_id),
  hecho_por       uuid REFERENCES usuarios(id),      -- quién lo cambió (null = sistema)
  ocurrido        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX asignaciones_idx ON asignaciones (pedido_id, ocurrido);

-- Evidencias de entrega (foto, firma) o de no entrega
CREATE TABLE evidencias (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id   uuid NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  tipo        text NOT NULL CHECK (tipo IN ('foto_entrega', 'firma', 'foto_fachada', 'comprobante_pago')),
  archivo_id  uuid NOT NULL REFERENCES archivos(id),
  creado      timestamptz NOT NULL DEFAULT now()
);

-- Calificaciones del servicio (del cliente final o del comercio)
CREATE TABLE calificaciones (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id       uuid NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  autor           text NOT NULL CHECK (autor IN ('cliente', 'comercio')),
  repartidor_id   uuid REFERENCES repartidores(usuario_id),
  estrellas       smallint NOT NULL CHECK (estrellas BETWEEN 1 AND 5),
  comentario      text,
  creado          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pedido_id, autor)
);
CREATE INDEX calificaciones_rep_idx ON calificaciones (repartidor_id, creado);

-- =====================================================================
--  8. DINERO: recaudo contraentrega, cierres de caja y liquidaciones
-- =====================================================================

-- Cierre de caja diario del repartidor: lo que cobró vs. lo que entregó a LoEntrego
CREATE TABLE cierres_caja (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  repartidor_id     uuid NOT NULL REFERENCES repartidores(usuario_id),
  fecha             date NOT NULL,
  esperado          bigint NOT NULL DEFAULT 0,      -- suma de cobros de pedidos entregados
  recibido          bigint,                         -- lo que efectivamente entregó
  diferencia        bigint GENERATED ALWAYS AS (coalesce(recibido, 0) - esperado) STORED,
  estado            estado_cierre NOT NULL DEFAULT 'abierto',
  recibido_por      uuid REFERENCES usuarios(id),
  soporte_id        uuid REFERENCES archivos(id),
  creado            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (repartidor_id, fecha)
);

-- Liquidación al comercio: recaudos de sus pedidos menos tarifas de envío
CREATE TABLE liquidaciones (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  comercio_id     uuid NOT NULL REFERENCES comercios(id),
  periodo_inicio  date NOT NULL,
  periodo_fin     date NOT NULL,
  total_recaudo   bigint NOT NULL DEFAULT 0,
  total_tarifas   bigint NOT NULL DEFAULT 0,
  neto            bigint GENERATED ALWAYS AS (total_recaudo - total_tarifas) STORED,  -- negativo = el comercio debe
  estado          estado_liquidacion NOT NULL DEFAULT 'borrador',
  aprobada_por    uuid REFERENCES usuarios(id),
  pagada_en       timestamptz,
  soporte_id      uuid REFERENCES archivos(id),
  creado          timestamptz NOT NULL DEFAULT now(),
  CHECK (periodo_fin >= periodo_inicio)
);

-- Qué pedidos entran en cada liquidación (un pedido se liquida una sola vez)
CREATE TABLE liquidacion_pedidos (
  liquidacion_id  uuid NOT NULL REFERENCES liquidaciones(id) ON DELETE CASCADE,
  pedido_id       uuid NOT NULL UNIQUE REFERENCES pedidos(id),
  recaudo         bigint NOT NULL,
  tarifa          bigint NOT NULL,
  PRIMARY KEY (liquidacion_id, pedido_id)
);

-- Pago al repartidor por periodo
CREATE TABLE pagos_repartidor (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  repartidor_id   uuid NOT NULL REFERENCES repartidores(usuario_id),
  periodo_inicio  date NOT NULL,
  periodo_fin     date NOT NULL,
  entregas        int NOT NULL DEFAULT 0,
  valor_por_entrega bigint NOT NULL,
  ajustes         bigint NOT NULL DEFAULT 0,       -- bonos (+) o descuentos por diferencias de caja (−)
  total           bigint GENERATED ALWAYS AS (entregas * valor_por_entrega + ajustes) STORED,
  estado          estado_liquidacion NOT NULL DEFAULT 'borrador',
  pagado_en       timestamptz,
  soporte_id      uuid REFERENCES archivos(id),
  creado          timestamptz NOT NULL DEFAULT now(),
  CHECK (periodo_fin >= periodo_inicio)
);

-- =====================================================================
--  9. CAPTACIÓN (web y enlaces del panel)
-- =====================================================================

-- Formulario "Únete" de la web (comercio, ubicación, celular, pedidos diarios, mensaje)
CREATE TABLE solicitudes_comercio (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  comercio          text NOT NULL,
  ubicacion         text NOT NULL,
  celular           text NOT NULL,
  pedidos_diarios   int CHECK (pedidos_diarios >= 0),
  mensaje           text,
  origen            text,                            -- utm / página / referido
  estado            estado_solicitud NOT NULL DEFAULT 'nueva',
  atendida_por      uuid REFERENCES usuarios(id),
  comercio_id       uuid REFERENCES comercios(id),   -- en qué comercio terminó (si se convirtió)
  ip                inet,
  creado            timestamptz NOT NULL DEFAULT now(),
  actualizado       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX solicitudes_comercio_estado_idx ON solicitudes_comercio (estado, creado DESC);
CREATE TRIGGER t_solicitudes_act BEFORE UPDATE ON solicitudes_comercio FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();

-- Postulaciones de repartidores (si llegan por la web o por enlace)
CREATE TABLE postulaciones_repartidor (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre        text NOT NULL,
  celular       text NOT NULL,
  municipio_id  text REFERENCES municipios(id),
  mensaje       text,
  estado        estado_solicitud NOT NULL DEFAULT 'nueva',
  repartidor_id uuid REFERENCES repartidores(usuario_id),
  creado        timestamptz NOT NULL DEFAULT now()
);

-- Formulario de contacto de la web
CREATE TABLE mensajes_contacto (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      text NOT NULL,
  celular     text,
  correo      citext,
  mensaje     text NOT NULL,
  leido_por   uuid REFERENCES usuarios(id),
  leido_en    timestamptz,
  ip          inet,
  creado      timestamptz NOT NULL DEFAULT now(),
  CHECK (celular IS NOT NULL OR correo IS NOT NULL)
);

-- Enlaces de registro que genera el panel (invitar comercios o repartidores)
CREATE TABLE enlaces_registro (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token         text NOT NULL UNIQUE DEFAULT translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_'),
  rol           rol_usuario NOT NULL CHECK (rol IN ('comercio', 'repartidor')),
  nota          text,
  usos_max      int NOT NULL DEFAULT 1 CHECK (usos_max > 0),
  usos          int NOT NULL DEFAULT 0 CHECK (usos >= 0),
  vence         timestamptz NOT NULL DEFAULT now() + interval '7 days',
  revocado_en   timestamptz,
  creado_por    uuid NOT NULL REFERENCES usuarios(id),
  creado        timestamptz NOT NULL DEFAULT now(),
  CHECK (usos <= usos_max)
);

-- Quién se registró con cada enlace
CREATE TABLE registros_por_enlace (
  enlace_id   uuid NOT NULL REFERENCES enlaces_registro(id),
  usuario_id  uuid NOT NULL UNIQUE REFERENCES usuarios(id),
  creado      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (enlace_id, usuario_id)
);

-- =====================================================================
--  10. REDES Y REPUTACIÓN (Resumen del panel: Google Business, Instagram, Facebook)
-- =====================================================================

-- Foto diaria de cada red (la llena un trabajo programado con las APIs)
CREATE TABLE metricas_redes (
  red             red_social NOT NULL,
  fecha           date NOT NULL,
  seguidores      int,
  alcance         int,
  interacciones   int,
  visitas_perfil  int,
  calificacion    numeric(2,1) CHECK (calificacion BETWEEN 1 AND 5),   -- Google
  total_resenas   int,
  datos           jsonb NOT NULL DEFAULT '{}',        -- lo demás que entregue la API
  PRIMARY KEY (red, fecha)
);

-- Reseñas públicas (Google Business, Facebook)
CREATE TABLE resenas (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  red           red_social NOT NULL,
  id_externo    text NOT NULL,
  autor         text,
  estrellas     smallint CHECK (estrellas BETWEEN 1 AND 5),
  texto         text,
  publicada     timestamptz NOT NULL,
  respuesta     text,
  respondida_en timestamptz,
  UNIQUE (red, id_externo)
);

-- =====================================================================
--  11. NOTIFICACIONES (push y correo)
-- =====================================================================
CREATE TABLE plantillas (
  id          text PRIMARY KEY,                     -- 'pedido_en_camino', 'pedido_entregado', …
  canal       canal_notificacion NOT NULL,
  cuerpo      text NOT NULL,                        -- con variables {{nombre}}, {{codigo}}…
  activa      boolean NOT NULL DEFAULT true
);

CREATE TABLE notificaciones (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  canal         canal_notificacion NOT NULL,
  plantilla_id  text REFERENCES plantillas(id),
  usuario_id    uuid REFERENCES usuarios(id),      -- si es para alguien con cuenta…
  destino       text NOT NULL,                     -- …o un celular/correo (cliente final)
  pedido_id     uuid REFERENCES pedidos(id),
  variables     jsonb NOT NULL DEFAULT '{}',
  estado        estado_envio NOT NULL DEFAULT 'pendiente',
  intentos      smallint NOT NULL DEFAULT 0,
  error         text,
  id_externo    text,                              -- id del proveedor (para el webhook de estado)
  creado        timestamptz NOT NULL DEFAULT now(),
  enviado_en    timestamptz
);
CREATE INDEX notificaciones_pendientes_idx ON notificaciones (creado) WHERE estado = 'pendiente';

-- =====================================================================
--  12. SISTEMA: estado de canales (página de mantenimiento), ajustes y auditoría
-- =====================================================================

-- Lo que muestra la página de mantenimiento (ESTADO en frontend-maintenance/Script.js)
CREATE TABLE estado_canales (
  canal         text PRIMARY KEY,                  -- 'App LoEntrego', 'Página web', 'Operación', 'Atención'
  estado        estado_canal NOT NULL DEFAULT 'ok',
  texto         text NOT NULL,
  orden         smallint NOT NULL DEFAULT 0,
  actualizado   timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER t_canales_act BEFORE UPDATE ON estado_canales FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();

CREATE TABLE mantenimientos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inicio        timestamptz NOT NULL,
  regreso       timestamptz,                       -- "Regreso estimado" (data-regreso)
  mensaje       text,
  creado_por    uuid REFERENCES usuarios(id),
  CHECK (regreso IS NULL OR regreso > inicio)
);

-- Ajustes generales (valor por entrega al repartidor, horario, correo de contacto…)
CREATE TABLE ajustes (
  clave         text PRIMARY KEY,
  valor         jsonb NOT NULL,
  descripcion   text,
  actualizado   timestamptz NOT NULL DEFAULT now()
);

-- Auditoría: quién cambió qué (la llena el backend o triggers)
CREATE TABLE auditoria (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id  uuid REFERENCES usuarios(id),
  tabla       text NOT NULL,
  registro_id text NOT NULL,
  accion      text NOT NULL CHECK (accion IN ('crear', 'editar', 'archivar', 'borrar', 'ingresar')),
  antes       jsonb,
  despues     jsonb,
  ip          inet,
  ocurrido    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auditoria_registro_idx ON auditoria (tabla, registro_id, ocurrido DESC);

-- =====================================================================
--  13. FUNCIONES DE TERRITORIO Y AUTOASIGNACIÓN
-- =====================================================================

-- Zona para un punto: la que lo contiene (mayor prioridad) o, si cae en un hueco, la más cercana
CREATE FUNCTION zona_para_punto(lat double precision, lon double precision)
RETURNS TABLE (id text, nombre text, dentro boolean) LANGUAGE sql STABLE AS $$
  WITH p AS (SELECT ST_SetSRID(ST_MakePoint(lon, lat), 4326) AS g)
  (SELECT z.id, z.nombre, true FROM zonas_reparto z, p
    WHERE z.archivado_en IS NULL AND ST_Covers(z.geom, p.g)
    ORDER BY z.prioridad DESC LIMIT 1)
  UNION ALL
  (SELECT z.id, z.nombre, false FROM zonas_reparto z, p
    WHERE z.archivado_en IS NULL AND NOT EXISTS (
      SELECT 1 FROM zonas_reparto z2 WHERE z2.archivado_en IS NULL AND ST_Covers(z2.geom, p.g))
    ORDER BY z.geom <-> p.g LIMIT 1)
  LIMIT 1
$$;

CREATE FUNCTION localidad_para_punto(lat double precision, lon double precision)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT l.id FROM localidades l
  WHERE ST_Covers(l.geom, ST_SetSRID(ST_MakePoint(lon, lat), 4326))
  LIMIT 1
$$;

-- Repartidor sugerido: de los que atienden la zona, activo y con jornada abierta, el de menos pedidos activos
CREATE FUNCTION repartidor_sugerido(p_zona text) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT zr.repartidor_id
  FROM zona_repartidores zr
  JOIN repartidores r ON r.usuario_id = zr.repartidor_id AND r.estado = 'activo'
  LEFT JOIN pedidos p ON p.repartidor_id = zr.repartidor_id AND p.estado IN ('por_recoger', 'recogido', 'en_camino')
  WHERE zr.zona_id = p_zona
  GROUP BY zr.repartidor_id
  ORDER BY EXISTS (SELECT 1 FROM jornadas j WHERE j.repartidor_id = zr.repartidor_id AND j.fin IS NULL) DESC,
           count(p.id), min(zr.desde)
  LIMIT 1
$$;

-- Al crear un pedido: tarifa vigente, localidad, zona y repartidor (si hay punto geocodificado)
CREATE FUNCTION pedido_al_crear() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE z record; lat double precision; lon double precision;
BEGIN
  IF NEW.estado <> 'por_recoger' THEN RAISE EXCEPTION 'Un pedido nuevo empieza en por_recoger'; END IF;
  IF NEW.tarifa IS NULL THEN
    SELECT t.valor INTO NEW.tarifa FROM tarifas t
    WHERE t.municipio_id = NEW.municipio_id AND t.vigente_desde <= current_date
      AND (t.vigente_hasta IS NULL OR t.vigente_hasta > current_date)
    ORDER BY t.vigente_desde DESC LIMIT 1;
    IF NEW.tarifa IS NULL THEN RAISE EXCEPTION 'No hay tarifa vigente para %', NEW.municipio_id; END IF;
  END IF;
  IF NEW.punto IS NOT NULL THEN
    lat := ST_Y(NEW.punto::geometry); lon := ST_X(NEW.punto::geometry);
    NEW.localidad_id := coalesce(NEW.localidad_id, localidad_para_punto(lat, lon));
    IF NEW.zona_id IS NULL THEN
      SELECT * INTO z FROM zona_para_punto(lat, lon);
      NEW.zona_id := z.id; NEW.fuera_de_zona := NOT coalesce(z.dentro, false);
    END IF;
    IF NEW.repartidor_id IS NULL AND NEW.zona_id IS NOT NULL THEN
      NEW.repartidor_id := repartidor_sugerido(NEW.zona_id);
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER t_pedidos_crear BEFORE INSERT ON pedidos FOR EACH ROW EXECUTE FUNCTION pedido_al_crear();

-- Historial y asignaciones automáticos
CREATE FUNCTION pedido_registrar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.estado IS DISTINCT FROM OLD.estado THEN
    INSERT INTO pedido_eventos (pedido_id, estado, usuario_id, nota)
    VALUES (NEW.id, NEW.estado, nullif(current_setting('loentrego.usuario', true), '')::uuid, NEW.motivo_detalle);
  END IF;
  IF NEW.repartidor_id IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.repartidor_id IS DISTINCT FROM OLD.repartidor_id) THEN
    INSERT INTO asignaciones (pedido_id, repartidor_id, hecho_por)
    VALUES (NEW.id, NEW.repartidor_id, nullif(current_setting('loentrego.usuario', true), '')::uuid);
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER t_pedidos_registrar AFTER INSERT OR UPDATE ON pedidos FOR EACH ROW EXECUTE FUNCTION pedido_registrar();

-- Reglas del flujo: solo se avanza en orden y los estados finales no se reabren
CREATE FUNCTION pedido_validar_estado() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE orden constant estado_pedido[] := ARRAY['por_recoger', 'recogido', 'en_camino', 'entregado']::estado_pedido[];
BEGIN
  IF NEW.estado = OLD.estado THEN RETURN NEW; END IF;
  IF OLD.estado IN ('entregado', 'no_entregado', 'cancelado') THEN
    RAISE EXCEPTION 'El pedido % ya está cerrado (%)', OLD.codigo, OLD.estado;
  END IF;
  IF NEW.estado = 'cancelado' AND OLD.estado <> 'por_recoger' THEN
    RAISE EXCEPTION 'Solo se cancela un pedido que no se ha recogido';
  END IF;
  IF NEW.estado = ANY (orden) AND array_position(orden, NEW.estado) <> array_position(orden, OLD.estado) + 1 THEN
    RAISE EXCEPTION 'Paso no válido: % → %', OLD.estado, NEW.estado;
  END IF;
  IF NEW.estado IN ('entregado', 'no_entregado', 'cancelado') THEN NEW.cerrado_en := now(); END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER t_pedidos_estado BEFORE UPDATE OF estado ON pedidos FOR EACH ROW EXECUTE FUNCTION pedido_validar_estado();

-- =====================================================================
--  14. VISTAS PARA EL PANEL (Resumen, Comercios, Repartidores, Mapa)
-- =====================================================================

-- Resumen por día
CREATE VIEW v_resumen_diario AS
SELECT programado_para AS dia,
       count(*)                                         AS pedidos,
       count(*) FILTER (WHERE estado = 'entregado')     AS entregados,
       count(*) FILTER (WHERE estado = 'no_entregado')  AS no_entregados,
       count(*) FILTER (WHERE estado IN ('por_recoger', 'recogido', 'en_camino')) AS activos,
       round(100.0 * count(*) FILTER (WHERE estado = 'entregado') / nullif(count(*) FILTER (WHERE estado IN ('entregado', 'no_entregado')), 0), 1) AS efectividad,
       sum(cobro) FILTER (WHERE estado = 'entregado')   AS recaudo,
       sum(tarifa) FILTER (WHERE estado = 'entregado')  AS ingresos_envio
FROM pedidos
GROUP BY programado_para;

-- Por repartidor
CREATE VIEW v_repartidores AS
SELECT r.usuario_id AS repartidor_id, u.nombre, r.estado,
       count(p.id) FILTER (WHERE p.estado = 'entregado')                         AS entregas,
       count(p.id) FILTER (WHERE p.estado = 'no_entregado')                      AS no_entregas,
       count(p.id) FILTER (WHERE p.estado IN ('por_recoger', 'recogido', 'en_camino')) AS activos,
       (SELECT round(avg(c.estrellas), 2) FROM calificaciones c WHERE c.repartidor_id = r.usuario_id) AS calificacion,
       (SELECT string_agg(zr.zona_id, ', ' ORDER BY zr.zona_id) FROM zona_repartidores zr WHERE zr.repartidor_id = r.usuario_id) AS zonas
FROM repartidores r
JOIN usuarios u ON u.id = r.usuario_id
LEFT JOIN pedidos p ON p.repartidor_id = r.usuario_id
GROUP BY r.usuario_id, u.nombre, r.estado;

-- Por comercio
CREATE VIEW v_comercios AS
SELECT c.id AS comercio_id, c.nombre, c.tipo, c.estado,
       count(p.id)                                       AS pedidos,
       count(p.id) FILTER (WHERE p.estado = 'entregado') AS entregados,
       max(p.creado)                                     AS ultimo_pedido,
       coalesce(sum(p.cobro) FILTER (WHERE p.estado = 'entregado'), 0) AS recaudo
FROM comercios c
LEFT JOIN pedidos p ON p.comercio_id = c.id
GROUP BY c.id;

-- Demanda por localidad (capa "Calor" del mapa)
CREATE VIEW v_demanda_localidad AS
SELECT l.id AS localidad_id, l.nombre, l.municipio_id, p.programado_para AS dia, count(p.id) AS pedidos
FROM localidades l
JOIN pedidos p ON p.localidad_id = l.id
GROUP BY l.id, l.nombre, l.municipio_id, p.programado_para;

-- Cobertura de zonas: "faltan N repartidores"
CREATE VIEW v_cobertura_zonas AS
SELECT z.id AS zona_id, z.nombre, z.capacidad_diaria,
       count(DISTINCT zr.repartidor_id) AS repartidores,
       round(coalesce(d.promedio, 0), 1) AS pedidos_dia_promedio,
       greatest(0, ceil(coalesce(d.promedio, 0) / z.capacidad_diaria) - count(DISTINCT zr.repartidor_id))::int AS faltan
FROM zonas_reparto z
LEFT JOIN zona_repartidores zr ON zr.zona_id = z.id
LEFT JOIN LATERAL (
  SELECT avg(n) AS promedio FROM (
    SELECT count(*) AS n FROM pedidos p
    WHERE p.zona_id = z.id AND p.programado_para > current_date - 30
    GROUP BY p.programado_para) s
) d ON true
WHERE z.archivado_en IS NULL
GROUP BY z.id, z.nombre, z.capacidad_diaria, d.promedio;

-- =====================================================================
--  15. MÉTRICAS POR DÍA (comercios y repartidores)
--  Una fila por comercio o repartidor y día. Los periodos (hoy, semana,
--  mes, 6 meses, año, histórico) se sacan sumando filas. El backend llama
--  refrescar_metricas() cada pocos minutos para hoy y al cierre del día.
-- =====================================================================
CREATE TABLE metricas_comercio_dia (
  comercio_id       uuid NOT NULL REFERENCES comercios(id) ON DELETE CASCADE,
  dia               date NOT NULL,
  pedidos           int NOT NULL DEFAULT 0,
  entregados        int NOT NULL DEFAULT 0,
  no_entregados     int NOT NULL DEFAULT 0,
  cancelados        int NOT NULL DEFAULT 0,
  recaudo           bigint NOT NULL DEFAULT 0,       -- cobrado contraentrega en pedidos entregados
  tarifas           bigint NOT NULL DEFAULT 0,       -- envíos de los pedidos entregados
  minutos_entrega   bigint NOT NULL DEFAULT 0,       -- suma de minutos de recogido a entregado
  calculado         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (comercio_id, dia)
);
CREATE INDEX metricas_comercio_dia_idx ON metricas_comercio_dia (dia);

CREATE TABLE metricas_repartidor_dia (
  repartidor_id     uuid NOT NULL REFERENCES repartidores(usuario_id) ON DELETE CASCADE,
  dia               date NOT NULL,
  asignados         int NOT NULL DEFAULT 0,
  entregados        int NOT NULL DEFAULT 0,
  no_entregados     int NOT NULL DEFAULT 0,
  cobrado           bigint NOT NULL DEFAULT 0,       -- efectivo recibido en entregas
  minutos_entrega   bigint NOT NULL DEFAULT 0,
  minutos_jornada   int NOT NULL DEFAULT 0,          -- tiempo conectado ese día
  calificaciones    int NOT NULL DEFAULT 0,          -- cuántas recibió
  estrellas         int NOT NULL DEFAULT 0,          -- suma de estrellas (promedio = estrellas / calificaciones)
  calculado         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (repartidor_id, dia)
);
CREATE INDEX metricas_repartidor_dia_idx ON metricas_repartidor_dia (dia);

-- Recalcula un día completo (por defecto hoy). Se puede repetir sin duplicar.
CREATE FUNCTION refrescar_metricas(p_dia date DEFAULT current_date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM metricas_comercio_dia WHERE dia = p_dia;
  INSERT INTO metricas_comercio_dia (comercio_id, dia, pedidos, entregados, no_entregados, cancelados, recaudo, tarifas, minutos_entrega)
  SELECT p.comercio_id, p_dia,
         count(*),
         count(*) FILTER (WHERE p.estado = 'entregado'),
         count(*) FILTER (WHERE p.estado = 'no_entregado'),
         count(*) FILTER (WHERE p.estado = 'cancelado'),
         coalesce(sum(p.cobro)  FILTER (WHERE p.estado = 'entregado'), 0),
         coalesce(sum(p.tarifa) FILTER (WHERE p.estado = 'entregado'), 0),
         coalesce(sum(t.minutos) FILTER (WHERE p.estado = 'entregado'), 0)
  FROM pedidos p
  LEFT JOIN LATERAL (
    SELECT extract(epoch FROM p.cerrado_en - coalesce(min(e.ocurrido), p.creado))::bigint / 60 AS minutos
    FROM pedido_eventos e WHERE e.pedido_id = p.id AND e.estado = 'recogido'
  ) t ON true
  WHERE p.programado_para = p_dia
  GROUP BY p.comercio_id;

  DELETE FROM metricas_repartidor_dia WHERE dia = p_dia;
  INSERT INTO metricas_repartidor_dia (repartidor_id, dia, asignados, entregados, no_entregados, cobrado, minutos_entrega, minutos_jornada, calificaciones, estrellas)
  SELECT r.usuario_id, p_dia,
         coalesce(pd.asignados, 0), coalesce(pd.entregados, 0), coalesce(pd.no_entregados, 0),
         coalesce(pd.cobrado, 0), coalesce(pd.minutos, 0),
         coalesce(j.minutos, 0), coalesce(c.n, 0), coalesce(c.estrellas, 0)
  FROM repartidores r
  LEFT JOIN LATERAL (
    SELECT count(*) AS asignados,
           count(*) FILTER (WHERE p.estado = 'entregado')    AS entregados,
           count(*) FILTER (WHERE p.estado = 'no_entregado') AS no_entregados,
           sum(p.cobro) FILTER (WHERE p.estado = 'entregado') AS cobrado,
           sum(extract(epoch FROM p.cerrado_en - coalesce(
                 (SELECT min(e.ocurrido) FROM pedido_eventos e WHERE e.pedido_id = p.id AND e.estado = 'recogido'),
                 p.creado))::bigint / 60) FILTER (WHERE p.estado = 'entregado') AS minutos
    FROM pedidos p WHERE p.repartidor_id = r.usuario_id AND p.programado_para = p_dia
  ) pd ON true
  LEFT JOIN LATERAL (
    SELECT sum(extract(epoch FROM coalesce(jo.fin, now()) - jo.inicio))::int / 60 AS minutos
    FROM jornadas jo WHERE jo.repartidor_id = r.usuario_id AND jo.inicio::date = p_dia
  ) j ON true
  LEFT JOIN LATERAL (
    SELECT count(*) AS n, sum(ca.estrellas) AS estrellas
    FROM calificaciones ca WHERE ca.repartidor_id = r.usuario_id AND ca.creado::date = p_dia
  ) c ON true
  WHERE pd.asignados > 0 OR j.minutos > 0 OR c.n > 0;
END $$;

-- Periodos que usan el panel y la AppWeb
CREATE VIEW periodos AS
SELECT * FROM (VALUES
  ('hoy',       1, current_date),
  ('semana',    2, current_date - 6),
  ('mes',       3, current_date - 29),
  ('6m',        4, (current_date - interval '6 months')::date),
  ('anio',      5, (current_date - interval '1 year')::date),
  ('historico', 6, '-infinity'::date)
) AS t (periodo, orden, desde);

-- Métricas de cada comercio por periodo
CREATE VIEW v_metricas_comercio AS
SELECT m.comercio_id, pe.periodo, pe.orden,
       sum(m.pedidos)::int AS pedidos, sum(m.entregados)::int AS entregados,
       sum(m.no_entregados)::int AS no_entregados, sum(m.cancelados)::int AS cancelados,
       round(100.0 * sum(m.entregados) / nullif(sum(m.entregados) + sum(m.no_entregados), 0), 1) AS efectividad,
       sum(m.recaudo)::bigint AS recaudo, sum(m.tarifas)::bigint AS tarifas,
       round(sum(m.minutos_entrega)::numeric / nullif(sum(m.entregados), 0), 0) AS minutos_promedio
FROM periodos pe
JOIN metricas_comercio_dia m ON m.dia >= pe.desde
GROUP BY m.comercio_id, pe.periodo, pe.orden;

-- Métricas de cada repartidor por periodo
CREATE VIEW v_metricas_repartidor AS
SELECT m.repartidor_id, pe.periodo, pe.orden,
       sum(m.asignados)::int AS asignados, sum(m.entregados)::int AS entregados,
       sum(m.no_entregados)::int AS no_entregados,
       round(100.0 * sum(m.entregados) / nullif(sum(m.entregados) + sum(m.no_entregados), 0), 1) AS efectividad,
       sum(m.cobrado)::bigint AS cobrado,
       round(sum(m.minutos_entrega)::numeric / nullif(sum(m.entregados), 0), 0) AS minutos_promedio,
       round(sum(m.minutos_jornada) / 60.0, 1) AS horas_jornada,
       round(sum(m.estrellas)::numeric / nullif(sum(m.calificaciones), 0), 2) AS calificacion
FROM periodos pe
JOIN metricas_repartidor_dia m ON m.dia >= pe.desde
GROUP BY m.repartidor_id, pe.periodo, pe.orden;

COMMIT;
