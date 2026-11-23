-- Exporta tablas, columnas, llaves y relaciones a JSON (para la página).
-- Uso: psql "$DATABASE_URL" -q -f db/exportar-esquema.sql | grep "^{" > datos/esquema.json
\pset tuples_only on
\pset format unaligned
WITH t AS (
  SELECT c.oid, c.relname AS tabla, obj_description(c.oid) AS descr
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r' AND c.relname<>'spatial_ref_sys'
), cols AS (
  SELECT t.tabla, a.attnum, a.attname AS col, format_type(a.atttypid,a.atttypmod) AS tipo, a.attnotnull AS nn,
    EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid=t.oid AND k.contype='p' AND a.attnum = ANY(k.conkey)) AS pk,
    (SELECT json_build_object('tabla', cf.relname, 'col', af.attname) FROM pg_constraint k
       JOIN pg_class cf ON cf.oid=k.confrelid JOIN pg_attribute af ON af.attrelid=k.confrelid AND af.attnum=k.confkey[1]
       WHERE k.conrelid=t.oid AND k.contype='f' AND k.conkey[1]=a.attnum AND array_length(k.conkey,1)=1 LIMIT 1) AS fk,
    EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid=t.oid AND k.contype='u' AND k.conkey=ARRAY[a.attnum]) AS uq
  FROM t JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum>0 AND NOT a.attisdropped
)
SELECT json_build_object(
 'tablas', (SELECT json_agg(json_build_object('nombre', t.tabla, 'columnas',
     (SELECT json_agg(json_build_object('nombre',col,'tipo',tipo,'nn',nn,'pk',pk,'fk',fk,'uq',uq) ORDER BY attnum) FROM cols WHERE cols.tabla=t.tabla)) ORDER BY t.tabla) FROM t),
 'enums', (SELECT json_object_agg(ty.typname, (SELECT json_agg(e.enumlabel ORDER BY e.enumsortorder) FROM pg_enum e WHERE e.enumtypid=ty.oid))
     FROM pg_type ty JOIN pg_namespace n ON n.oid=ty.typnamespace WHERE n.nspname='public' AND ty.typtype='e'),
 'vistas', (SELECT json_agg(viewname ORDER BY viewname) FROM pg_views WHERE schemaname='public' AND viewname NOT IN ('geography_columns','geometry_columns')),
 'funciones', (SELECT json_agg(p.proname ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname IN ('zona_para_punto','localidad_para_punto','repartidor_sugerido','pedido_al_crear','pedido_registrar','pedido_validar_estado','tocar_actualizado'))
);
