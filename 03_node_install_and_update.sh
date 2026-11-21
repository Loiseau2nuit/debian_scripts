#!/bin/bash

set -euo pipefail

# === CONFIGURATION ===
SYMLINK="/opt/node"
OLD_DIR="/opt/node-OLD"
LOG_FILE="/var/log/node_update_check.log"
TMP_DIR="/tmp/nodejs-update"
NODEJS_DIST_URL="https://nodejs.org/dist/latest"
ARCH="linux-x64"
MAIL_TO="admin@example.com"
GLOBAL_NODE_LINK="/usr/local/bin/node"

# === Fonctions utilitaires ===
log() {
    echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"
}

send_mail() {
    SUBJECT="$1"
    BODY="$2"
    echo "$BODY" | mail -s "$SUBJECT" "$MAIL_TO"
}

handle_error() {
    log "[ERROR] Une erreur s'est produite. Tentative de rollback."
    rollback || log "[ERROR] Rollback échoué."
    TAIL_LOG=$(tail -n 50 "$LOG_FILE")
    send_mail "[WARN] Échec mise à jour Node.js + tentative rollback" "$TAIL_LOG"
    exit 1
}

rollback() {
    if [ -d "$OLD_DIR" ]; then
        log "[INFO] Restauration de la version précédente depuis $OLD_DIR"
        rm -rf "$(readlink -f "$SYMLINK")"
        mv "$OLD_DIR" "$(readlink -f "$SYMLINK")"
        log "[OK] Rollback effectué."
        return 0
    else
        log "[WARN] Aucun répertoire $OLD_DIR trouvé pour rollback."
        return 1
    fi
}

install_script() {
    log "[INFO] Installation initiale..."

    # Création du log
    touch "$LOG_FILE"
    chmod 664 "$LOG_FILE"
    log "Fichier de log créé à $LOG_FILE"

    # Vérification présence de Node.js
    if [ ! -L "$SYMLINK" ]; then
        read -rp "Node.js ne semble pas installé. Souhaitez-vous l'installer maintenant ? [y/N] " reply
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            bash "$0"
            exit 0
        else
            log "[INFO] Installation annulée par l'utilisateur."
            exit 1
        fi
    fi

    # Lien global vers node
    if [ ! -L "$GLOBAL_NODE_LINK" ]; then
        ln -s "$SYMLINK/bin/node" "$GLOBAL_NODE_LINK"
        log "Lien global $GLOBAL_NODE_LINK → $SYMLINK/bin/node créé"
    fi

    log "[OK] Installation initiale terminée."
    exit 0
}

# === Installation si demandé ===
if [[ "${1:-}" == "--install" ]]; then
    install_script
fi

# === Rollback si demandé ===
if [[ "${1:-}" == "--rollback" ]]; then
    rollback && exit 0 || exit 1
fi

# === Piège les erreurs ===
trap 'handle_error' ERR

log "=== Démarrage de la vérification de mise à jour Node.js ==="

# === Étape 0 : Vérifie que Node.js est installé ===
if [ ! -L "$SYMLINK" ]; then
    log "[ERROR] Node.js ne semble pas installé (lien $SYMLINK manquant)."
    read -rp "Souhaitez-vous procéder à son installation ? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        bash "$0" --install
        exit 0
    else
        log "[INFO] Vérification annulée."
        exit 1
    fi
fi

# === Étape 1 : Vérifie le lien symbolique
REAL_PATH=$(readlink -f "$SYMLINK")
LOCAL_VERSION=$(basename "$REAL_PATH" | sed -E 's/^node-v//')

# === Étape 2 : Récupération de la version distante
LATEST_VERSION=$(curl -s "$NODEJS_DIST_URL/" | grep -oP 'node-v\K[0-9]+\.[0-9]+\.[0-9]+' | head -n1)

if [ -z "$LATEST_VERSION" ]; then
    log "[ERROR] Impossible de récupérer la version distante."
    exit 1
fi

if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]; then
    log "[OK] Node.js est à jour (v$LOCAL_VERSION)."
    exit 0
fi

log "[INFO] Mise à jour nécessaire : installée = $LOCAL_VERSION / disponible = $LATEST_VERSION"

# === Étape 3 : Téléchargement
FILENAME="node-v$LATEST_VERSION-$ARCH"
ARCHIVE_NAME="$FILENAME.tar.xz"
DOWNLOAD_URL="$NODEJS_DIST_URL/$ARCHIVE_NAME"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
log "[INFO] Téléchargement de $ARCHIVE_NAME depuis $DOWNLOAD_URL"
curl -sL "$DOWNLOAD_URL" -o "$TMP_DIR/$ARCHIVE_NAME"

# === Étape 4 : Vérification SHA256
SHA_URL="$NODEJS_DIST_URL/SHASUMS256.txt"
EXPECTED_SHA=$(curl -s "$SHA_URL" | grep "$ARCHIVE_NAME" | awk '{print $1}')
DOWNLOADED_SHA=$(sha256sum "$TMP_DIR/$ARCHIVE_NAME" | awk '{print $1}')

if [ "$EXPECTED_SHA" != "$DOWNLOADED_SHA" ]; then
    log "[ERROR] Échec de vérification SHA256."
    exit 1
fi
log "[OK] Vérification SHA256 réussie"

# === Étape 5 : Extraction
tar -xf "$TMP_DIR/$ARCHIVE_NAME" -C "$TMP_DIR"
INSTALL_DIR="/opt/node-v$LATEST_VERSION"
mv "$TMP_DIR/$FILENAME" "$INSTALL_DIR"
log "[INFO] Extraction déployée dans $INSTALL_DIR"

# === Étape 6 : Sauvegarde + bascule
rm -rf "$OLD_DIR"
log "[INFO] Sauvegarde de la version actuelle vers $OLD_DIR"
mv "$REAL_PATH" "$OLD_DIR"

ln -sfn "$INSTALL_DIR" "$SYMLINK"
log "[OK] Lien symbolique mis à jour : $SYMLINK → $INSTALL_DIR"

# === Étape 7 : Lien global vers node
ln -sf "$SYMLINK/bin/node" "$GLOBAL_NODE_LINK"
log "[OK] Lien global mis à jour : $GLOBAL_NODE_LINK"

# === Étape 8 : Nettoyage
rm -rf "$TMP_DIR"
log "[OK] Nettoyage terminé"

# === Étape 9 : Notification succès
BODY="Node.js mis à jour avec succès :

- Ancienne version : $LOCAL_VERSION
- Nouvelle version : $LATEST_VERSION
- Installée dans : $INSTALL_DIR
- Sauvegarde précédente : $OLD_DIR
- Date : $(date)
- Lien symbolique : $SYMLINK → $INSTALL_DIR"

send_mail "[OK] Node.js mis à jour vers $LATEST_VERSION" "$BODY"
log "[INFO] Notification de succès envoyée à $MAIL_TO"
