#!/usr/bin/env bash
# =====================================================================
#  LoEntrego · Instalación del VPS (Bluehost · Ubuntu 22.04 o 24.04 LTS, sin cPanel)
#  Antes, en Namecheap (Advanced DNS), 4 registros A → IP del VPS: @, www, app, admin.
#  Uso (como root, en un servidor recién creado, con la carpeta vps/ completa):
#     DOMINIO=loentrego.com CORREO=contacto@loentrego.com bash instalar.sh
#  Es idempotente: se puede correr de nuevo sin romper nada.
# =====================================================================
set -euo pipefail
DOMINIO="${DOMINIO:-loentrego.com}"   # dominio raíz: se usan @, www, app y admin
CORREO="${CORREO:-contacto@loentrego.com}"
APP_USER=loentrego
DB_NAME=loentrego
NODE_MAJOR=22

paso() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

# Solo Ubuntu 22.04 o 24.04 (Bluehost puede entregar AlmaLinux/cPanel: reinstalar con Ubuntu)
. /etc/os-release
if [ "$ID" != "ubuntu" ] || { [ "$VERSION_ID" != "22.04" ] && [ "$VERSION_ID" != "24.04" ]; }; then
  echo "Este script es para Ubuntu 22.04 o 24.04 (encontré: $PRETTY_NAME)."
  echo "En Bluehost: reinstala el VPS con Ubuntu, sin panel, y vuelve a correrlo."
  exit 1
fi

paso "Sistema al día, zona horaria de Bogotá y actualizaciones de seguridad automáticas"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q && apt-get upgrade -y -q
apt-get install -y -q ca-certificates curl gnupg git rsync unzip jq htop unattended-upgrades
timedatectl set-timezone America/Bogota
dpkg-reconfigure -f noninteractive unattended-upgrades

paso "Memoria de intercambio (2 GB) para que las compilaciones no tumben el servidor"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

paso "Firewall (solo SSH, HTTP y HTTPS) y fail2ban"
apt-get install -y -q ufw fail2ban
ufw default deny incoming && ufw default allow outgoing
ufw allow OpenSSH && ufw allow 'Nginx Full' 2>/dev/null || ufw allow 80,443/tcp
ufw --force enable
systemctl enable --now fail2ban

paso "Usuario de la aplicación (sin acceso root)"
id "$APP_USER" >/dev/null 2>&1 || adduser --system --group --home /srv/loentrego --shell /bin/bash "$APP_USER"
mkdir -p /srv/loentrego/{api,respaldos,logs} && chown -R "$APP_USER":"$APP_USER" /srv/loentrego

paso "Carpetas de los frontends y usuario de despliegue (lo usa GitHub Actions por SSH)"
# Cada repo de frontend se copia a su carpeta; el usuario "despliegue" solo puede escribir ahí
id despliegue >/dev/null 2>&1 || adduser --disabled-password --gecos "" despliegue
mkdir -p /srv/loentrego/www/{web,app,admin,mantenimiento} /srv/loentrego/mantenimiento /home/despliegue/.ssh
chown -R despliegue:despliegue /srv/loentrego/www
chmod 755 /srv/loentrego /srv/loentrego/www
touch /home/despliegue/.ssh/authorized_keys
chown -R despliegue:despliegue /home/despliegue/.ssh && chmod 700 /home/despliegue/.ssh && chmod 600 /home/despliegue/.ssh/authorized_keys
# Puede reiniciar la API después de un despliegue, y nada más
echo 'despliegue ALL=(root) NOPASSWD: /usr/bin/systemctl restart loentrego-api' > /etc/sudoers.d/loentrego-despliegue
chmod 440 /etc/sudoers.d/loentrego-despliegue
# Mantenimiento por sitio: touch /srv/loentrego/mantenimiento/app.on (web.on, admin.on)
chown root:despliegue /srv/loentrego/mantenimiento && chmod 775 /srv/loentrego/mantenimiento

paso "PostgreSQL 16 + PostGIS 3 (repositorio oficial de PostgreSQL) y GDAL (ogr2ogr)"
# El repositorio oficial da la versión 16 tanto en Ubuntu 22.04 como en 24.04
install -d /usr/share/postgresql-common/pgdg
curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
apt-get update -q
apt-get install -y -q postgresql-16 postgresql-16-postgis-3 gdal-bin
systemctl enable --now postgresql
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$APP_USER'" | grep -q 1; then
  DB_PASS="$(openssl rand -base64 30 | tr -d '/+=')"
  sudo -u postgres psql -c "CREATE ROLE $APP_USER LOGIN PASSWORD '$DB_PASS'"
  sudo -u postgres createdb -O "$APP_USER" "$DB_NAME"
  echo "DATABASE_URL=postgres://$APP_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME" > /srv/loentrego/.env
  chown "$APP_USER":"$APP_USER" /srv/loentrego/.env && chmod 600 /srv/loentrego/.env
fi
# Las extensiones las crea el superusuario (el esquema las pide con IF NOT EXISTS)
sudo -u postgres psql -d "$DB_NAME" -c 'CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS citext; CREATE EXTENSION IF NOT EXISTS pgcrypto;'
# Postgres escucha solo en localhost (valor por defecto en Ubuntu); no se abre el 5432

paso "Redis (límites de intentos de inicio de sesión), solo en localhost"
apt-get install -y -q redis-server
sed -i 's/^supervised .*/supervised systemd/' /etc/redis/redis.conf
systemctl enable --now redis-server

paso "Node.js $NODE_MAJOR LTS (la API)"
if ! node -v 2>/dev/null | grep -q "^v$NODE_MAJOR"; then
  curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash -
  apt-get install -y -q nodejs
fi

paso "Servicio systemd de la API (arranca solo y se reinicia si se cae)"
cat > /etc/systemd/system/loentrego-api.service <<UNIT
[Unit]
Description=LoEntrego API
After=network.target postgresql.service redis-server.service

[Service]
User=$APP_USER
WorkingDirectory=/srv/loentrego/api
EnvironmentFile=/srv/loentrego/.env
Environment=NODE_ENV=production PORT=3000
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable loentrego-api   # se inicia cuando el código esté en /srv/loentrego/api

paso "Nginx + Certbot (HTTPS de Let's Encrypt con renovación automática)"
apt-get install -y -q nginx certbot python3-certbot-nginx
DIR="$(cd "$(dirname "$0")" && pwd)"
sed "s/loentrego\.com/$DOMINIO/g" "$DIR/nginx-app.conf" > /etc/nginx/sites-available/loentrego
install -m 644 "$DIR/nginx-comun.conf" /etc/nginx/snippets/loentrego-comun.conf
install -m 644 "$DIR/nginx-api.conf" /etc/nginx/snippets/loentrego-api.conf
ln -sf /etc/nginx/sites-available/loentrego /etc/nginx/sites-enabled/loentrego
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
certbot --nginx -d "$DOMINIO" -d "www.$DOMINIO" -d "app.$DOMINIO" -d "admin.$DOMINIO" \
  -m "$CORREO" --agree-tos --redirect --non-interactive || \
  echo "Certbot falló: revisa en Namecheap (Advanced DNS) que @, www, app y admin apunten a este VPS y vuelve a correr el script."

paso "Respaldos: rclone + copia diaria de la base a las 3:15 a. m."
apt-get install -y -q rclone
install -m 750 -o "$APP_USER" -g "$APP_USER" "$DIR/respaldo.sh" /srv/loentrego/respaldo.sh
echo "15 3 * * * $APP_USER /srv/loentrego/respaldo.sh >> /srv/loentrego/logs/respaldo.log 2>&1" > /etc/cron.d/loentrego-respaldo

paso "Rotación de logs de la app"
cat > /etc/logrotate.d/loentrego <<'ROT'
/srv/loentrego/logs/*.log {
  weekly
  rotate 8
  compress
  missingok
  notifempty
}
ROT

paso "Listo"
echo "Siguiente:"
echo " 1. Pegar la llave pública de GitHub Actions en /home/despliegue/.ssh/authorized_keys"
echo " 2. Hacer push a main en cada frontend (o correr su Action) para llenar /srv/loentrego/www/*"
echo " 3. Subir la API a /srv/loentrego/api y correr db/esquema.sql y db/semilla.sql"
echo " 4. Configurar rclone (rclone config) para los respaldos"
echo " 5. Probar: https://$DOMINIO  https://app.$DOMINIO  https://admin.$DOMINIO  https://app.$DOMINIO/api/salud"
