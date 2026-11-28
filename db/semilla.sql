-- =====================================================================
--  LoEntrego · Datos iniciales (catálogos y usuarios de prueba)
--  Correr después de esquema.sql:  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/semilla.sql
--  Las zonas (polígonos) se cargan con el SQL que genera el panel
--  (window.LEMapa.sql()) o con ogr2ogr: ver frontend_admin/docs/zonas-geojson-postgis.md
-- =====================================================================
BEGIN;

-- Áreas de cobertura con su tarifa de envío (hoy $10.000 en las tres)
INSERT INTO areas (id, nombre, departamento, tarifa) VALUES
  ('bogota', 'Bogotá', 'Bogotá D.C.',  10000),
  ('funza',  'Funza',  'Cundinamarca', 10000),
  ('soacha', 'Soacha', 'Cundinamarca', 10000);

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

-- Usuarios de prueba (los mismos de la demo). ¡Cambiar las claves en producción!
INSERT INTO usuarios (rol, usuario, clave_hash, nombre, celular) VALUES
  ('admin',      'admin',      crypt('admin123',  gen_salt('bf')), 'Administrador general', NULL),
  ('comercio',   'demo',       crypt('demo123',   gen_salt('bf')), 'Tienda Demo',           '3001112233'),
  ('repartidor', 'repartidor', crypt('reparto123', gen_salt('bf')), 'Carlos Repartidor',    '3104445566');

INSERT INTO comercios (id, tipo, direccion, detalle, area_id)
SELECT id, 'ecommerce', 'Calle 80 #15-20', 'Bodega', 'bogota' FROM usuarios WHERE usuario = 'demo';

INSERT INTO repartidores (usuario_id, documento, prefijo)
SELECT id, '1012345678', 'CRE' FROM usuarios WHERE usuario = 'repartidor';

COMMIT;
