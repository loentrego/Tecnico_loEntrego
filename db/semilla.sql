-- =====================================================================
--  LoEntrego · Datos iniciales (catálogos y usuarios de prueba)
--  Correr después de esquema.sql:  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/semilla.sql
--  Las localidades y zonas (polígonos) se cargan con el SQL que genera el panel
--  (window.LEMapa.sql()) o con ogr2ogr: ver frontend_admin/docs/zonas-geojson-postgis.md
-- =====================================================================
BEGIN;

INSERT INTO municipios (id, nombre, departamento) VALUES
  ('bogota', 'Bogotá', 'Bogotá D.C.'),
  ('funza',  'Funza',  'Cundinamarca'),
  ('soacha', 'Soacha', 'Cundinamarca');

-- Tarifa de envío actual: $10.000 en los tres municipios
INSERT INTO tarifas (municipio_id, valor, vigente_desde) VALUES
  ('bogota', 10000, '2026-01-01'), ('funza', 10000, '2026-01-01'), ('soacha', 10000, '2026-01-01');

-- Lo que muestra la página de mantenimiento
INSERT INTO estado_canales (canal, estado, texto, orden) VALUES
  ('App LoEntrego', 'ok', 'Activa', 1),
  ('Página web',    'ok', 'Activa', 2),
  ('Operación',     'ok', 'Funcionando', 3),
  ('Atención',      'ok', 'Correo activo', 4);

INSERT INTO ajustes (clave, valor, descripcion) VALUES
  ('valor_por_entrega',  '4500',                     'Pago al repartidor por entrega (COP)'),
  ('horario_operacion',  '{"desde":"07:00","hasta":"19:00","dias":[1,2,3,4,5,6]}', 'Horario de recogidas y entregas'),
  ('correo_contacto',    '"contacto@loentrego.com"', 'Correo de contacto');

INSERT INTO plantillas (id, canal, cuerpo) VALUES
  ('solicitud_recibida', 'correo', 'Recibimos tu solicitud, {{comercio}}. Te escribimos en menos de un día hábil.');

-- Usuarios de prueba (los mismos de la demo). ¡Cambiar las claves en producción!
INSERT INTO usuarios (rol, usuario, clave_hash, nombre, celular) VALUES
  ('admin',      'admin',      crypt('admin123',  gen_salt('bf')), 'Administrador general', NULL),
  ('comercio',   'demo',       crypt('demo123',   gen_salt('bf')), 'Tienda Demo',           '3001112233'),
  ('repartidor', 'repartidor', crypt('reparto123', gen_salt('bf')), 'Carlos Repartidor',    '3104445566');

INSERT INTO comercios (id, nombre, tipo, celular, direccion, detalle, municipio_id)
SELECT id, 'Tienda Demo', 'ecommerce', '3001112233', 'Calle 80 #15-20', 'Bodega', 'bogota' FROM usuarios WHERE usuario = 'demo';

INSERT INTO repartidores (usuario_id, documento, estado, fecha_ingreso)
SELECT id, '1012345678', 'activo', '2026-01-15' FROM usuarios WHERE usuario = 'repartidor';

COMMIT;
