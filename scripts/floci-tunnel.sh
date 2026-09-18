#!/usr/bin/env bash
set -euo pipefail

# Floci ne publie vers l'hôte que le port SSH de l'EC2 simulée : les ports
# HTTP ouverts par les security groups Terraform ne sont pas accessibles
# directement depuis Windows/WSL2. Ce script ouvre un tunnel SSH local
# (via le port SSH que Floci publie réellement) vers le port 80 (Nginx) de
# l'instance, pour rendre l'application joignable en localhost.
#
# Usage : depuis la racine du dépôt
#   ./scripts/floci-tunnel.sh [port_local]
#
# port_local doit correspondre à application_public_port (terraform/variables.tf,
# 8080 par défaut) : c'est ce port qui est stocké comme domaine PrestaShop.

port_local="${1:-8080}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cle_privee="${repo_root}/.keys/taylor-shift"

# Sur un dépôt situé sous /mnt/c (WSL2 + Windows), le montage drvfs ne
# supporte pas les permissions Unix : la clé apparaît "-rwxrwxrwx" et SSH la
# refuse ("bad permissions"). Repli automatique : copier la clé dans un
# fichier temporaire (sur le filesystem Linux natif, où chmod fonctionne
# réellement) si ses permissions ne sont pas déjà restrictives.
perms="$(stat -c '%a' "${cle_privee}" 2>/dev/null || echo '')"
if [ -n "${perms}" ] && [ "${perms}" != "600" ] && [ "${perms}" != "400" ]; then
  cle_tmp="$(mktemp)"
  cp "${cle_privee}" "${cle_tmp}"
  chmod 600 "${cle_tmp}"
  trap 'rm -f "${cle_tmp}"' EXIT
  cle_privee="${cle_tmp}"
fi

conteneur="$(docker ps --filter "name=floci-ec2-" --format '{{.Names}}' | head -n1)"
if [ -z "${conteneur}" ]; then
  echo "Aucune instance floci-ec2-* en cours d'exécution. Lancer d'abord terraform apply." >&2
  exit 1
fi

port_ssh="$(docker port "${conteneur}" 22/tcp | head -n1 | sed -E 's#.*:##')"
if [ -z "${port_ssh}" ]; then
  echo "Impossible de déterminer le port SSH publié par Floci pour ${conteneur}." >&2
  exit 1
fi

echo "Instance : ${conteneur} (SSH publié sur le port ${port_ssh})"
echo "Application accessible sur http://localhost:${port_local} tant que ce tunnel reste ouvert (Ctrl+C pour arrêter)."

exec ssh -i "${cle_privee}" -p "${port_ssh}" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -N -L "${port_local}:localhost:80" root@127.0.0.1
