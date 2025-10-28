#!/bin/bash
# ====================================================================
# Websites maintenance tool : backups and clones
# Auteur : (c) Loiseau2nuit 2025
# Version : 0.2
# Status : UNTESTED YET ! NOT FOR PRODUCTION PURPOSE !
# ====================================================================
# - Manual backups (e.g. : before upgrades or heavy maintenance)
# - Working clones creation for test purposes (files + base + nginx conf)
# ====================================================================

# --- CONFIG ---------------------------------------------------------
WWW_ROOT="/var/www"
BACKUP_ROOT="/var/backups/manual"
NGINX_SITES="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
# DB_USER="root"
# DB_PASS="motdepasse"      # ou utiliser ~/.my.cnf
PHP_SOCK="/run/php/php8.2-fpm.sock"  # à adapter selon ta version PHP
TMP_DIR="/tmp/site_tool"
mkdir -p "$BACKUP_ROOT" "$TMP_DIR"

# --- MySQL CONFIG -----------------------------------------

# Valeurs par défaut (au cas où ~/.my.cnf n'existe pas)
DB_USER_DEFAULT="root"
DB_PASS_DEFAULT=""

# Si un fichier ~/.my.cnf existe, on essaie d’en extraire les infos
if [ -f ~/.my.cnf ]; then
  echo "🔍 Fichier ~/.my.cnf détecté — utilisation des identifiants qu’il contient."
  DB_USER=$(awk -F= '/user *=/ {gsub(/[[:space:]]/, "", $2); print $2}' ~/.my.cnf | tail -n1)
  DB_PASS=$(awk -F= '/password *=/ {gsub(/[[:space:]]/, "", $2); print $2}' ~/.my.cnf | tail -n1)
else
  echo "⚠️  Aucun ~/.my.cnf trouvé — utilisation des valeurs par défaut."
  DB_USER="$DB_USER_DEFAULT"
  DB_PASS="$DB_PASS_DEFAULT"
fi

# On prépare les options pour les appels à mysql / mysqldump
# (ne met pas --password si la variable est vide)
MYSQL_OPTS=("-u${DB_USER}")
[ -n "$DB_PASS" ] && MYSQL_OPTS+=("-p${DB_PASS}")


# --- FUNCTIONS ------------------------------------------------------

list_sites() {
  echo "Sites disponibles :"
  ls -1 "$WWW_ROOT"
}

select_site() {
  list_sites
  echo
  read -rp "Nom du site à traiter (ou 'all') : " SITE
  if [ "$SITE" = "all" ]; then
    SITES=$(ls -1 "$WWW_ROOT")
  else
    SITES="$SITE"
  fi
}

backup_site() {
  for SITE in $SITES; do
    SITE_PATH="$WWW_ROOT/$SITE"
    [ ! -d "$SITE_PATH" ] && echo "⚠️  Dossier $SITE_PATH introuvable" && continue

    DB_NAME=$(grep -RohP "(?<=DB_NAME[='\"])[^'\"]+" "$SITE_PATH" | head -n1) 
    [ -z "$DB_NAME" ] && echo "⚠️  Base introuvable dans la config du site $SITE" && continue

    DATE=$(date +"%F_%H-%M-%S")
    DEST="$BACKUP_ROOT/${SITE}_${DATE}"
    mkdir -p "$DEST"

    echo "🔹 Sauvegarde du site $SITE..."
    tar -cJf "$DEST/${SITE}.tar.xz" -C "$WWW_ROOT" "$SITE"

    echo "🔹 Sauvegarde de la base $DB_NAME..."
    mysqldump "${MYSQL_OPTS[@]}" --add-drop-table "$DB_NAME" | gzip > "$DEST/${DB_NAME}.sql.gz"

    echo "✅ Sauvegarde de $SITE terminée → $DEST"
    echo
  done
}

clone_site() {
  list_sites
  echo
  read -rp "Site à dupliquer : " SRC
  SRC_PATH="$WWW_ROOT/$SRC"
  [ ! -d "$SRC_PATH" ] && echo "❌ Site source introuvable" && exit 1

  read -rp "Nom du site de test (ex: ${SRC}-test) : " DEST
  DEST_PATH="$WWW_ROOT/$DEST"
  if [ -d "$DEST_PATH" ]; then
    echo "❌ Le dossier $DEST_PATH existe déjà."
    exit 1
  fi

  # --- Copie fichiers
  echo "📁 Copie du répertoire..."
  cp -a "$SRC_PATH" "$DEST_PATH"

  # --- Base de données
  SRC_DB=$(grep -RohP "(?<=DB_NAME[='\"])[^'\"]+" "$SITE_PATH" | head -n1)
  [ -z "$SRC_DB" ] && echo "⚠️  Impossible de déterminer la BDD source." && exit 1
  DEST_DB="${SRC_DB}_test"

  echo "🗃️  Clonage de la base de données ($SRC_DB → $DEST_DB)..."
  mysql "${MYSQL_OPTS[@]}" -e "DROP DATABASE IF EXISTS \`$DEST_DB\`; CREATE DATABASE \`$DEST_DB\`;"
  mysqldump "${MYSQL_OPTS[@]}" "$SRC_DB" | mysql "${MYSQL_OPTS[@]}" "$DEST_DB"

  # --- Configuration PHP
  echo "--------------------------------------------------"
  echo "🔍 Recherche des versions PHP installées..."
  PHP_VERSIONS_AVAILABLE=$(ls /run/php/php*-fpm.sock 2>/dev/null | sed -E 's|/run/php/php([0-9.]+)-fpm.sock|\1|' | sort -u)

  if [ -z "$PHP_VERSIONS_AVAILABLE" ]; then
    echo "⚠️  Aucune version PHP-FPM détectée sur le système."
  else
    echo "Versions PHP disponibles :"
    echo "$PHP_VERSIONS_AVAILABLE" | sed 's/^/  - /'
  fi

  echo
  read -rp "Version PHP souhaitée pour le clone (ex: 8.2) : " PHP_VER
  PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"

  if [ ! -S "$PHP_SOCK" ]; then
    echo "⚠️  PHP ${PHP_VER} non installé. Souhaitez-vous l’installer ? (o/n)"
    read -r install_choice
    if [[ "$install_choice" =~ ^[oOyY]$ ]]; then
      echo "📦 Installation de PHP ${PHP_VER}..."
      SUDO=$(command -v sudo >/dev/null 2>&1 && echo "sudo" || echo "")
      ${SUDO} apt-get update -qq
      ${SUDO} apt-get install -y php${PHP_VER}-cli php${PHP_VER}-common \
        php${PHP_VER}-{apcu,bz2,curl,gd,imagick,imap,intl,ldap,mbstring,mysql,opcache,readline,snmp,soap,xml,xmlrpc,zip} \
        php${PHP_VER}-fpm
    else
      echo "❌ Annulation : PHP ${PHP_VER} requis non présent."
      exit 1
    fi
  fi

  echo "✅ Utilisation du socket PHP : $PHP_SOCK"

  # --- Modification config site
  echo "⚙️  Ajustement du fichier de configuration..."
  find "$DEST_PATH" \( -name "*.php" -o -name "*.conf" -o -name "*.env" \) \ -type f -exec sed -i "s/$SRC_DB/$DEST_DB/g" {} +

  # --- Configuration Nginx
  echo "🌐 Génération de la configuration Nginx..."
  NGINX_CONF="$NGINX_SITES/$DEST.conf"
  SERVER_NAME="${DEST}.local"

  cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $SERVER_NAME;
    root $DEST_PATH;

    index index.php index.html;
    access_log /var/log/nginx/${DEST}_access.log;
    error_log /var/log/nginx/${DEST}_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCK;
    }
}
EOF

  ln -s "$NGINX_CONF" "$NGINX_ENABLED/$DEST.conf" 2>/dev/null || true

  echo "🔎 Vérification de la configuration Nginx…"
  if ! nginx -t; then
      echo "❌ Erreur dans la configuration Nginx"
      echo "---- Dernières lignes du journal Nginx ----"
      journalctl -u nginx -n 20 --no-pager
      exit 1
  fi

  if ! systemctl reload nginx; then
      echo "❌ Impossible de recharger Nginx"
      echo "---- Dernières lignes du journal Nginx ----"
      journalctl -u nginx -n 20 --no-pager
      exit 1
  fi

  echo
  echo "✅ Copie de test déployée avec succès !"
  echo "URL : http://$SERVER_NAME/"
  echo "BDD : $DEST_DB"
  echo "PHP : $PHP_VER"
}

main_menu() {
  echo "=================================================="
  echo "     Outil de gestion de sites web (manuel)"
  echo "=================================================="
  echo "1) Sauvegarde d’un site"
  echo "2) Création d’une copie de test"
  echo "3) Quitter"
  echo "--------------------------------------------------"
  read -rp "Choix : " choice

  case $choice in
    1)
      select_site
      backup_site
      ;;
    2)
      clone_site
      ;;
    3)
      echo "Au revoir 👋"
      exit 0
      ;;
    *)
      echo "Choix invalide"
      ;;
  esac
}

# --- EXECUTION ------------------------------------------------------
main_menu
