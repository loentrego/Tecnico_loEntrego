# LoEntrego · Documentación técnica

Cómo funciona LoEntrego por dentro: el servidor, los programas, los servicios externos,
la API y la base de datos de todo el ecosistema (web, AppWeb, panel admin y página de
mantenimiento). Abre `index.html` para verla.

## Contenido

| Carpeta / archivo | Qué es |
|---|---|
| `index.html`, `styles.css`, `script.js` | La página de documentación (mismo estilo del manual de marca). |
| `db/esquema.sql` | **Base de datos completa**: 39 tablas, tipos, relaciones, reglas del pedido, autoasignación por zona (PostGIS) y vistas del panel. |
| `db/semilla.sql` | Datos iniciales: municipios, tarifas, canales de mantenimiento, plantillas, ajustes y usuarios de prueba. |
| `db/exportar-esquema.sql` | Saca tablas y relaciones de la base a `datos/esquema.json` (lo que dibuja la página). |
| `datos/esquema.json`, `datos/esquema.js` | Estructura de la base, generada desde la base real. No editar a mano. |
| `vps/instalar.sh` | Instala el VPS (Ubuntu 24.04): firewall, Nginx, Certbot, PostgreSQL + PostGIS, Redis, Node.js, servicio de la API y respaldos. |
| `vps/nginx-app.conf` | Sitio de Nginx para `app.loentrego.com` con límites en el inicio de sesión. |
| `vps/respaldo.sh` | Respaldo diario de la base (14 días locales + copia cifrada con rclone). |

## Crear la base

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/esquema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/semilla.sql
```

Las localidades y zonas de reparto (polígonos) se cargan con el SQL que genera el panel
admin (`window.LEMapa.sql()`). Ver `frontend_admin/docs/zonas-geojson-postgis.md`.

## Si cambia el esquema

1. Edita `db/esquema.sql` y pruébalo en una base vacía.
2. Regenera los datos de la página:

```bash
psql "$DATABASE_URL" -q -f db/exportar-esquema.sql | grep '^{' > datos/esquema.json
python3 -c "import json;d=json.load(open('datos/esquema.json'));open('datos/esquema.js','w').write('window.ESQUEMA = '+json.dumps(d,ensure_ascii=False)+';\n')"
```

3. Si agregaste una tabla, ponla en su área (`AREAS`) y descríbela (`DESC`) en `script.js`.

Uso interno. Calles y límites: © colaboradores de OpenStreetMap (ODbL).
