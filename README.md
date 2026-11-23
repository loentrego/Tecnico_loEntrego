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
| `datos/entradas.js` | **Entradas y salidas**: cada campo y botón de los 4 frontends, la llamada a la API a la que va y el JSON que envía y recibe. La tabla de la API sale de aquí. |
| `datos/esquema.json`, `datos/esquema.js` | Estructura de la base, generada desde la base real. No editar a mano. |
| `vps/instalar.sh` | Instala el VPS de Bluehost (Ubuntu 22.04 o 24.04, sin cPanel): firewall, Nginx, Certbot, PostgreSQL + PostGIS, Redis, Node.js, servicio de la API y respaldos. |
| `vps/nginx-app.conf` | Los 3 sitios de Nginx: web, app y admin, cada uno con su `/api`. |
| `vps/nginx-comun.conf`, `vps/nginx-api.conf` | Lo común a los sitios (encabezados, caché, página de mantenimiento) y el paso de `/api` a la API. |
| `github/desplegar-frontend.yml` | Plantilla de GitHub Actions: con cada push a `main` copia el frontend a su carpeta en el VPS. |
| `vps/respaldo.sh` | Respaldo diario de la base (14 días locales + copia cifrada con rclone). |

## Infraestructura

- **Servidor:** VPS de Bluehost · 2 vCPU · 4 GB RAM · 100 GB.
- **Dominio y DNS:** Namecheap (Advanced DNS: registros A `@`, `www`, `app` y `admin` → IP del VPS).
- **Lo que usa la gente:** todo en el VPS, bajo el dominio. `loentrego.com` (web), `app.loentrego.com` (AppWeb), `admin.loentrego.com` (panel) y `/api` en cada uno.
- **GitHub:** organiza el código y despliega al VPS con GitHub Actions (`github/desplegar-frontend.yml`). GitHub Pages solo publica el mockup con datos ficticios.
- **Mantenimiento:** `touch /srv/loentrego/mantenimiento/app.on` (o `web.on`, `admin.on`); se quita borrando el archivo.

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
