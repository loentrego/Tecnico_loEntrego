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
--      (áreas, zonas) que ya usan los frontends.
--    · Dinero en pesos colombianos, entero (bigint): no hay centavos.
--    · Fechas con zona horaria (timestamptz). La operación es en America/Bogota.
--    · Coordenadas WGS84 (SRID 4326). Puntos como geography; polígonos como geometry.
--    · Todo lo que se borra en la app se "archiva" (archivado_en); no se borra la fila.
-- =====================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid(), hash de claves
CREATE EXTENSION IF NOT EXISTS citext;     -- usuario y correo sin distinguir mayúsculas
CREATE EXTENSION IF NOT EXISTS postgis;    -- contornos de áreas y zonas

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
-- Estado de cualquier cuenta (comercio, repartidor o admin):
--   activo   → usa todo
--   pausado  → puede entrar, pero no crea ni recibe pedidos
--   retirado → no puede entrar (la cuenta no se borra: el historial se conserva)
CREATE TYPE estado_usuario AS ENUM ('activo', 'pausado', 'retirado');


CREATE TYPE estado_solicitud AS ENUM ('nueva', 'contactada', 'convertida', 'descartada');
CREATE TYPE estado_liquidacion AS ENUM ('borrador', 'aprobada', 'pagada', 'anulada');
CREATE TYPE estado_cierre AS ENUM ('abierto', 'cuadrado', 'con_diferencia');
CREATE TYPE estado_canal AS ENUM ('ok', 'warn', 'fail');   -- igual que la página de mantenimiento

-- =====================================================================
--  Utilidad: "actualizado" se pone solo en cada UPDATE
-- =====================================================================
-- Día en Bogotá de una fecha y hora (no depende de la zona horaria del servidor)
CREATE FUNCTION dia_de(t timestamptz) RETURNS date LANGUAGE sql IMMUTABLE AS $$ SELECT (t AT TIME ZONE 'America/Bogota')::date $$;

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
  estado          estado_usuario NOT NULL DEFAULT 'activo',   -- el único estado: comercios y repartidores no tienen otro
  ultimo_ingreso  timestamptz,
  creado          timestamptz NOT NULL DEFAULT now(),
  actualizado     timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER t_usuarios_act BEFORE UPDATE ON usuarios FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();
CREATE INDEX usuarios_nombre_idx ON usuarios (lower(nombre));

-- Comercios y repartidores no repiten nombre, celular, correo ni fechas: todo eso está en usuarios.
-- Si cambia algo de su tabla, se marca la fecha "actualizado" de su usuario.
CREATE FUNCTION tocar_usuario() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE usuarios SET actualizado = now() WHERE id = (to_jsonb(NEW) ->> TG_ARGV[0])::uuid;
  RETURN NULL;
END $$;
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

-- =====================================================================
--  3. TERRITORIO (PostGIS)
-- =====================================================================
-- Áreas de cobertura: cada lugar donde opera LoEntrego (hoy Bogotá, Funza y Soacha).
-- Para crecer a otra ciudad o municipio se agrega una fila. La tarifa es la de hoy:
-- cada pedido guarda la suya al crearse, así que cambiarla no altera el historial.
CREATE TABLE areas (
  id            text PRIMARY KEY,                    -- 'bogota', 'funza', 'soacha'
  nombre        text NOT NULL,
  departamento  text NOT NULL,
  tarifa        bigint NOT NULL CHECK (tarifa >= 0), -- envío en pesos
  activa        boolean NOT NULL DEFAULT true,       -- si hay cobertura
  contorno      geometry(MultiPolygon, 4326)         -- límite del área (PostGIS)
);
CREATE INDEX areas_contorno_idx ON areas USING gist (contorno);

-- =====================================================================
--  4. REPARTIDORES
-- =====================================================================
CREATE TABLE repartidores (
  usuario_id        uuid PRIMARY KEY REFERENCES usuarios(id),   -- 1 a 1 con su usuario
  documento         text NOT NULL UNIQUE CHECK (documento ~ '^[0-9]{6,10}$'),   -- cédula de ciudadanía (la única que se acepta); no se valida contra ningún sistema
  prefijo           char(3) UNIQUE CHECK (prefijo ~ '^[A-Z]{3}$' AND prefijo <> 'LOE'),   -- código de sus guías: CRE-0000001 (lo asigna el backend al activarlo)
  contador_pedidos  int NOT NULL DEFAULT 0 CHECK (contador_pedidos BETWEEN 0 AND 9999999),  -- último número usado en sus guías
  contacto_emergencia_nombre   text,
  contacto_emergencia_celular  text
);   -- nombre, celular, correo y fechas: en usuarios
CREATE TRIGGER t_repartidores_act AFTER UPDATE ON repartidores FOR EACH ROW EXECUTE FUNCTION tocar_usuario('usuario_id');

-- =====================================================================
--  5. ZONAS (editables en el panel: Mapa → Zonas de reparto)
-- =====================================================================
-- Cada zona tiene un solo repartidor (un repartidor puede tener varias zonas).
-- El contorno es un polígono PostGIS: todos sus puntos van en una sola columna;
-- el panel lo envía y lo recibe como GeoJSON (ST_GeomFromGeoJSON / ST_AsGeoJSON).
CREATE TABLE zonas (
  id                text PRIMARY KEY,                -- id estable que usa el panel
  nombre            text NOT NULL,
  area_id           text NOT NULL REFERENCES areas(id),
  repartidor_id     uuid NOT NULL REFERENCES repartidores(usuario_id),
  capacidad_diaria  int NOT NULL DEFAULT 12 CHECK (capacidad_diaria > 0),  -- pedidos al día que aguanta
  contorno          geometry(MultiPolygon, 4326) NOT NULL,
  archivado_en      timestamptz,                     -- se archiva en vez de borrar (los pedidos la siguen nombrando)
  creado            timestamptz NOT NULL DEFAULT now(),
  actualizado       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX zonas_contorno_idx ON zonas USING gist (contorno);
CREATE INDEX zonas_repartidor_idx ON zonas (repartidor_id) WHERE archivado_en IS NULL;
CREATE TRIGGER t_zonas_act BEFORE UPDATE ON zonas FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();

-- =====================================================================
--  6. COMERCIOS
-- =====================================================================
CREATE TABLE comercios (
  id                uuid PRIMARY KEY REFERENCES usuarios(id),   -- el mismo id de su cuenta de acceso (une las dos tablas); no se guarda dueño ni responsable
  tipo              tipo_comercio NOT NULL DEFAULT 'comercio',
  -- Punto de recogida: cada comercio tiene uno y el repartidor recoge aquí
  direccion         text NOT NULL,
  detalle           text,                            -- local, bodega, piso, a quién preguntar
  area_id           text NOT NULL REFERENCES areas(id)
);   -- nombre comercial, celular, correo y fechas: en usuarios
CREATE TRIGGER t_comercios_act AFTER UPDATE ON comercios FOR EACH ROW EXECUTE FUNCTION tocar_usuario('id');

-- =====================================================================
--  7. PEDIDOS (el corazón)
-- =====================================================================
CREATE SEQUENCE pedidos_codigo_seq START 1001;

CREATE TABLE pedidos (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo                text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z]{3}-[0-9]{7}$'),   -- número de guía: lo arma la base al registrar el pedido (CRE-0000042)
  comercio_id           uuid NOT NULL REFERENCES comercios(id),   -- quien lo creó (el comercio es su propia cuenta)
  -- Destinatario (formulario "Nuevo pedido" de la AppWeb)
  destinatario_nombre   text NOT NULL,
  destinatario_telefono text NOT NULL CHECK (destinatario_telefono ~ '^[0-9]{7,10}$'),
  direccion             text NOT NULL,
  notas                 text,
  -- Zona: el backend ubica la dirección (sin guardar coordenadas) y busca su zona con zona_para_punto().
  -- De la zona salen el área (y su tarifa) y el repartidor.
  zona_id               text NOT NULL REFERENCES zonas(id),
  fuera_de_zona         boolean NOT NULL DEFAULT false, -- la dirección cayó en un hueco: se usó la zona más cercana
  -- Dinero
  cobro                 bigint NOT NULL DEFAULT 0 CHECK (cobro >= 0),   -- contraentrega; 0 = ya pagado
  tarifa                bigint NOT NULL CHECK (tarifa >= 0),            -- envío congelado al crear
  -- Operación
  repartidor_id         uuid REFERENCES repartidores(usuario_id),
  estado                estado_pedido NOT NULL DEFAULT 'por_recoger',   -- el último evento; cambia solo registrando un evento
  intentos              smallint NOT NULL DEFAULT 1 CHECK (intentos >= 1),
  pedido_origen_id      uuid REFERENCES pedidos(id),   -- reintento de un "no entregado"
  creado                timestamptz NOT NULL DEFAULT now(),   -- se entrega al día siguiente
  actualizado           timestamptz NOT NULL DEFAULT now(),
  cerrado_en            timestamptz,                   -- cuando llega a entregado/no_entregado/cancelado
  CHECK (estado = 'por_recoger' OR estado = 'cancelado' OR repartidor_id IS NOT NULL)
);
CREATE INDEX pedidos_comercio_idx   ON pedidos (comercio_id, creado DESC);
CREATE INDEX pedidos_comercio_dia_idx ON pedidos (comercio_id, dia_de(creado));
CREATE INDEX pedidos_repartidor_idx ON pedidos (repartidor_id, dia_de(creado)) WHERE repartidor_id IS NOT NULL;
CREATE INDEX pedidos_activos_idx    ON pedidos (estado) WHERE estado IN ('por_recoger', 'recogido', 'en_camino');
CREATE INDEX pedidos_zona_dia_idx   ON pedidos (zona_id, dia_de(creado));
CREATE INDEX pedidos_dia_idx        ON pedidos (dia_de(creado));
CREATE TRIGGER t_pedidos_act BEFORE UPDATE ON pedidos FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();

-- Historial: cada cambio de estado con su hora (la "mini-ruta" de la AppWeb)
-- Para cambiar el estado de un pedido se registra un evento aquí: la base valida el paso
-- y actualiza pedidos.estado sola. Si es "no entregado", el evento lleva el motivo.
CREATE TABLE pedido_eventos (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pedido_id   uuid NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  estado      estado_pedido NOT NULL,
  usuario_id  uuid REFERENCES usuarios(id),          -- quién lo cambió (null = sistema)
  motivo      motivo_no_entrega,                     -- por qué no se entregó (solo en no_entregado)
  nota        text,                                  -- lo que escribió quien hizo el cambio
  ocurrido    timestamptz NOT NULL DEFAULT now(),
  CHECK ((estado = 'no_entregado') = (motivo IS NOT NULL))
);
CREATE INDEX pedido_eventos_idx ON pedido_eventos (pedido_id, ocurrido);

-- Asignaciones (dato auxiliar): cada vez que cambia pedidos.repartidor_id queda quién lo tenía,
-- a quién pasó, a qué hora y quién lo hizo. Sin motivo. El repartidor vigente es el de pedidos.repartidor_id.
CREATE TABLE asignaciones (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pedido_id       uuid NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  repartidor_anterior  uuid REFERENCES repartidores(usuario_id),           -- quién lo tenía (null = primera asignación)
  repartidor_nuevo     uuid NOT NULL REFERENCES repartidores(usuario_id),  -- a quién pasó
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
--  10. SISTEMA: estado de canales (página de mantenimiento), ajustes y auditoría
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
--  11. FUNCIONES DE TERRITORIO Y AUTOASIGNACIÓN
-- =====================================================================

-- Zona para un punto: la que lo contiene o, si cae en un hueco, la más cercana
CREATE FUNCTION zona_para_punto(lat double precision, lon double precision)
RETURNS TABLE (id text, nombre text, dentro boolean) LANGUAGE sql STABLE AS $$
  WITH p AS (SELECT ST_SetSRID(ST_MakePoint(lon, lat), 4326) AS g)
  (SELECT z.id, z.nombre, true FROM zonas z, p
    WHERE z.archivado_en IS NULL AND ST_Covers(z.contorno, p.g)
    LIMIT 1)
  UNION ALL
  (SELECT z.id, z.nombre, false FROM zonas z, p
    WHERE z.archivado_en IS NULL AND NOT EXISTS (
      SELECT 1 FROM zonas z2 WHERE z2.archivado_en IS NULL AND ST_Covers(z2.contorno, p.g))
    ORDER BY z.contorno <-> p.g LIMIT 1)
  LIMIT 1
$$;

-- Al registrar un pedido, en este orden: tarifa del área → zona por la dirección → repartidor de esa zona
-- → número de guía (prefijo del repartidor + su contador, ej. CRE-0000042).
-- La zona la manda el backend (la sacó de la dirección). Si el repartidor de la zona está pausado,
-- el pedido queda sin repartidor y la guía sale con LOE + secuencia general.
CREATE FUNCTION pedido_al_crear() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE pre text; num int;
BEGIN
  IF NEW.estado <> 'por_recoger' THEN RAISE EXCEPTION 'Un pedido nuevo empieza en por_recoger'; END IF;
  -- Tarifa: la del área de la zona
  IF NEW.tarifa IS NULL THEN
    SELECT a.tarifa INTO NEW.tarifa FROM zonas zo JOIN areas a ON a.id = zo.area_id AND a.activa
    WHERE zo.id = NEW.zona_id AND zo.archivado_en IS NULL;
    IF NEW.tarifa IS NULL THEN RAISE EXCEPTION 'La zona % no existe o no tiene cobertura', NEW.zona_id; END IF;
  END IF;
  -- Repartidor: el de la zona, si está activo
  IF NEW.repartidor_id IS NULL THEN
    SELECT zo.repartidor_id INTO NEW.repartidor_id FROM zonas zo
      JOIN usuarios u ON u.id = zo.repartidor_id AND u.estado = 'activo'
    WHERE zo.id = NEW.zona_id;
  END IF;
  IF NEW.codigo IS NULL THEN
    IF NEW.repartidor_id IS NOT NULL THEN
      UPDATE repartidores SET contador_pedidos = contador_pedidos + 1
       WHERE usuario_id = NEW.repartidor_id AND prefijo IS NOT NULL
       RETURNING prefijo, contador_pedidos INTO pre, num;   -- dos pedidos a la vez nunca reciben el mismo número
    END IF;
    IF pre IS NULL THEN pre := 'LOE'; num := nextval('pedidos_codigo_seq'); END IF;
    NEW.codigo := pre || '-' || lpad(num::text, 7, '0');
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER t_pedidos_crear BEFORE INSERT ON pedidos FOR EACH ROW EXECUTE FUNCTION pedido_al_crear();

-- Historial y asignaciones automáticos
CREATE FUNCTION pedido_registrar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN   -- primer evento: lo crea el comercio
    INSERT INTO pedido_eventos (pedido_id, estado, usuario_id) VALUES (NEW.id, 'por_recoger', NEW.comercio_id);
  END IF;
  IF NEW.repartidor_id IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.repartidor_id IS DISTINCT FROM OLD.repartidor_id) THEN
    INSERT INTO asignaciones (pedido_id, repartidor_anterior, repartidor_nuevo, hecho_por)
    VALUES (NEW.id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.repartidor_id END, NEW.repartidor_id,
            nullif(current_setting('loentrego.usuario', true), '')::uuid);
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER t_pedidos_registrar AFTER INSERT OR UPDATE ON pedidos FOR EACH ROW EXECUTE FUNCTION pedido_registrar();

-- Reglas del flujo, al registrar un evento: solo se avanza en orden y los estados finales no se reabren
CREATE FUNCTION evento_validar() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE actual estado_pedido; cod text;
        orden constant estado_pedido[] := ARRAY['por_recoger', 'recogido', 'en_camino', 'entregado']::estado_pedido[];
BEGIN
  SELECT estado, codigo INTO actual, cod FROM pedidos WHERE id = NEW.pedido_id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM pedido_eventos WHERE pedido_id = NEW.pedido_id) THEN   -- el de la creación
    IF NEW.estado <> 'por_recoger' THEN RAISE EXCEPTION 'Un pedido empieza en por_recoger'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.estado = actual THEN RAISE EXCEPTION 'El pedido % ya está en %', cod, actual; END IF;
  IF actual IN ('entregado', 'no_entregado', 'cancelado') THEN
    RAISE EXCEPTION 'El pedido % ya está cerrado (%)', cod, actual;
  END IF;
  IF NEW.estado = 'cancelado' AND actual <> 'por_recoger' THEN
    RAISE EXCEPTION 'Solo se cancela un pedido que no se ha recogido';
  END IF;
  IF NEW.estado = ANY (orden) AND array_position(orden, NEW.estado) <> array_position(orden, actual) + 1 THEN
    RAISE EXCEPTION 'Paso no válido: % → %', actual, NEW.estado;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER t_eventos_validar BEFORE INSERT ON pedido_eventos FOR EACH ROW EXECUTE FUNCTION evento_validar();

-- El evento actualiza el pedido (estado y, si se cerró, cerrado_en)
CREATE FUNCTION evento_aplicar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE pedidos SET estado = NEW.estado,
         cerrado_en = CASE WHEN NEW.estado IN ('entregado', 'no_entregado', 'cancelado') THEN NEW.ocurrido ELSE cerrado_en END
   WHERE id = NEW.pedido_id AND estado IS DISTINCT FROM NEW.estado;
  RETURN NULL;
END $$;
CREATE TRIGGER t_eventos_aplicar AFTER INSERT ON pedido_eventos FOR EACH ROW EXECUTE FUNCTION evento_aplicar();

-- Nadie cambia pedidos.estado a mano: tiene que coincidir con el último evento
CREATE FUNCTION pedido_solo_por_evento() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado IS DISTINCT FROM
     (SELECT e.estado FROM pedido_eventos e WHERE e.pedido_id = NEW.id ORDER BY e.id DESC LIMIT 1) THEN
    RAISE EXCEPTION 'El estado se cambia registrando un evento en pedido_eventos';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER t_pedidos_estado BEFORE UPDATE OF estado ON pedidos FOR EACH ROW EXECUTE FUNCTION pedido_solo_por_evento();

-- =====================================================================
--  12. VISTAS PARA EL PANEL (Resumen, Comercios, Repartidores, Mapa)
-- =====================================================================

-- Resumen por día
CREATE VIEW v_resumen_diario AS
SELECT dia_de(creado) AS dia,
       count(*)                                         AS pedidos,
       count(*) FILTER (WHERE estado = 'entregado')     AS entregados,
       count(*) FILTER (WHERE estado = 'no_entregado')  AS no_entregados,
       count(*) FILTER (WHERE estado IN ('por_recoger', 'recogido', 'en_camino')) AS activos,
       round(100.0 * count(*) FILTER (WHERE estado = 'entregado') / nullif(count(*) FILTER (WHERE estado IN ('entregado', 'no_entregado')), 0), 1) AS efectividad,
       sum(cobro) FILTER (WHERE estado = 'entregado')   AS recaudo,
       sum(tarifa) FILTER (WHERE estado = 'entregado')  AS ingresos_envio
FROM pedidos
GROUP BY dia_de(creado);

-- Por repartidor
CREATE VIEW v_repartidores AS
SELECT r.usuario_id AS repartidor_id, u.nombre, u.estado,
       count(p.id) FILTER (WHERE p.estado = 'entregado')                         AS entregas,
       count(p.id) FILTER (WHERE p.estado = 'no_entregado')                      AS no_entregas,
       count(p.id) FILTER (WHERE p.estado IN ('por_recoger', 'recogido', 'en_camino')) AS activos,
       (SELECT string_agg(z.nombre, ', ' ORDER BY z.nombre) FROM zonas z WHERE z.repartidor_id = r.usuario_id AND z.archivado_en IS NULL) AS zonas
FROM repartidores r
JOIN usuarios u ON u.id = r.usuario_id
LEFT JOIN pedidos p ON p.repartidor_id = r.usuario_id
GROUP BY r.usuario_id, u.nombre, u.estado;

-- Por comercio
CREATE VIEW v_comercios AS
SELECT c.id AS comercio_id, u.nombre, c.tipo, u.estado,
       count(p.id)                                       AS pedidos,
       count(p.id) FILTER (WHERE p.estado = 'entregado') AS entregados,
       max(p.creado)                                     AS ultimo_pedido,
       coalesce(sum(p.cobro) FILTER (WHERE p.estado = 'entregado'), 0) AS recaudo
FROM comercios c
JOIN usuarios u ON u.id = c.id
LEFT JOIN pedidos p ON p.comercio_id = c.id
GROUP BY c.id, u.nombre, u.estado;

-- Demanda en el mapa (capa "Calor"): pedidos por zona y día
CREATE VIEW v_demanda_zonas AS
SELECT p.zona_id, dia_de(p.creado) AS dia, count(*) AS pedidos
FROM pedidos p
WHERE p.estado <> 'cancelado'
GROUP BY p.zona_id, dia_de(p.creado);

-- Carga de cada zona: pedidos al día (promedio de 30 días) frente a su capacidad
CREATE VIEW v_cobertura_zonas AS
SELECT z.id AS zona_id, z.nombre, z.area_id, z.repartidor_id, u.nombre AS repartidor, z.capacidad_diaria,
       round(coalesce(d.promedio, 0), 1) AS pedidos_dia_promedio,
       round(100 * coalesce(d.promedio, 0) / z.capacidad_diaria) AS carga_pct   -- más de 100 = se queda corta
FROM zonas z
JOIN usuarios u ON u.id = z.repartidor_id
LEFT JOIN LATERAL (
  SELECT avg(n) AS promedio FROM (
    SELECT count(*) AS n FROM pedidos p
    WHERE p.zona_id = z.id AND dia_de(p.creado) > dia_de(now()) - 30
    GROUP BY dia_de(p.creado)) s
) d ON true
WHERE z.archivado_en IS NULL;

-- =====================================================================
--  13. MÉTRICAS (se calculan en vivo desde los pedidos: no hay tablas de métricas)
--  Los pedidos ya son el historial. Cada periodo es una fecha "desde" en hora de Bogotá.
--  Si algún día hiciera falta más velocidad: una vista materializada por día que arma Postgres.
-- =====================================================================
CREATE VIEW periodos AS
SELECT * FROM (VALUES
  ('dia',       1, dia_de(now())),
  ('semana',    2, date_trunc('week',  dia_de(now()))::date),          -- desde el lunes
  ('mes',       3, date_trunc('month', dia_de(now()))::date),          -- desde el día 1
  ('6m',        4, (dia_de(now()) - interval '6 months')::date),       -- últimos 6 meses
  ('anio',      5, date_trunc('year',  dia_de(now()))::date),          -- desde el 1 de enero
  ('historico', 6, '-infinity'::date)
) AS t (periodo, orden, desde);

-- Hora en que se recogió cada pedido (para el tiempo de entrega)
CREATE VIEW v_pedidos_tiempos AS
SELECT p.id AS pedido_id,
       (SELECT min(e.ocurrido) FROM pedido_eventos e WHERE e.pedido_id = p.id AND e.estado = 'recogido') AS recogido_en
FROM pedidos p;

-- Métricas de cada comercio por periodo
CREATE VIEW v_metricas_comercio AS
SELECT p.comercio_id, pe.periodo, pe.orden,
       count(*)::int                                         AS pedidos,
       count(*) FILTER (WHERE p.estado = 'entregado')::int    AS entregados,
       count(*) FILTER (WHERE p.estado = 'no_entregado')::int AS no_entregados,
       count(*) FILTER (WHERE p.estado = 'cancelado')::int    AS cancelados,
       round(100.0 * count(*) FILTER (WHERE p.estado = 'entregado')
             / nullif(count(*) FILTER (WHERE p.estado IN ('entregado', 'no_entregado')), 0), 1) AS efectividad,
       coalesce(sum(p.cobro)  FILTER (WHERE p.estado = 'entregado'), 0)::bigint AS recaudo,
       coalesce(sum(p.tarifa) FILTER (WHERE p.estado = 'entregado'), 0)::bigint AS tarifas,
       round(avg(extract(epoch FROM p.cerrado_en - t.recogido_en) / 60) FILTER (WHERE p.estado = 'entregado')) AS minutos_promedio
FROM periodos pe
JOIN pedidos p ON dia_de(p.creado) >= pe.desde
JOIN v_pedidos_tiempos t ON t.pedido_id = p.id
GROUP BY p.comercio_id, pe.periodo, pe.orden;

-- Métricas de cada repartidor por periodo (se le evalúa solo por estos números)
CREATE VIEW v_metricas_repartidor AS
SELECT p.repartidor_id, pe.periodo, pe.orden,
       count(*)::int                                         AS asignados,
       count(*) FILTER (WHERE p.estado = 'entregado')::int    AS entregados,
       count(*) FILTER (WHERE p.estado = 'no_entregado')::int AS no_entregados,
       round(100.0 * count(*) FILTER (WHERE p.estado = 'entregado')
             / nullif(count(*) FILTER (WHERE p.estado IN ('entregado', 'no_entregado')), 0), 1) AS efectividad,
       coalesce(sum(p.cobro) FILTER (WHERE p.estado = 'entregado'), 0)::bigint AS cobrado,
       round(avg(extract(epoch FROM p.cerrado_en - t.recogido_en) / 60) FILTER (WHERE p.estado = 'entregado')) AS minutos_promedio
FROM periodos pe
JOIN pedidos p ON dia_de(p.creado) >= pe.desde AND p.repartidor_id IS NOT NULL
JOIN v_pedidos_tiempos t ON t.pedido_id = p.id
GROUP BY p.repartidor_id, pe.periodo, pe.orden;

COMMIT;
