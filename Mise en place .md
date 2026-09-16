# Mise en place du projet

> Ce document est alimenté petit à petit. Les sections déjà écrites couvrent la préparation de l'environnement et la protection du dépôt.

Les outils ne sont pas installés par ce document. Il vérifie seulement leur présence et indique quoi installer si un prérequis manque.

## 1. Préparer l'environnement

Le projet doit être exécuté depuis Ubuntu dans WSL2 sous Windows, comme dans les labs J3 et J4. Depuis PowerShell, vérifier l'installation avec :

Depuis PowerShell, vérifier WSL2 et Ubuntu :

```powershell
wsl --status
wsl --list --verbose
```

Si WSL2 ou Ubuntu est absent, il faut l'installer avant de continuer. Les commandes suivantes sont à exécuter dans le terminal Ubuntu WSL pour vérifier les outils :

```bash
terraform version
ansible --version
ansible-galaxy --version
aws --version
docker --version
ssh -V
```

Vérifier également que les exécutables sont accessibles depuis WSL2 :

```bash
command -v terraform ansible ansible-galaxy aws docker ssh
```

Si une commande est absente ou si sa version est incorrecte, installer l'outil correspondant avant de continuer :

| Outil absent ou incorrect | Action à effectuer |
|---|---|
| Terraform | Installer Terraform `1.11+`. |
| Ansible Core | Installer Ansible Core `2.20.x`. |
| Ansible Galaxy | Installer Ansible Core `2.20.x`. |
| AWS CLI | Installer AWS CLI v2. |
| Docker | Installer Docker Desktop et activer son intégration WSL2. |
| SSH | Installer le client OpenSSH dans Ubuntu. |

La collection `cloud.terraform` utilisée dans le J4 doit être exécutée avec Ansible Core `2.20.x`. Il ne faut pas utiliser Ansible `2.21+` avec cette version de la collection.

Pour Floci uniquement, utiliser des identifiants AWS factices :

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

Terraform, Ansible et Docker doivent être accessibles depuis le même environnement WSL2. Cette contrainte est importante car Ansible devra lancer Terraform pour lire l'inventaire dynamique.

### 1.1 Vérifier Docker

Docker Desktop doit être démarré et son intégration WSL2 activée pour Ubuntu.

```bash
docker ps
```

La commande doit répondre sans erreur. Une liste vide de conteneurs est normale. Si Docker est absent ou inaccessible, l'installer ou corriger son intégration WSL2, puis relancer le contrôle.

## 2. Protéger le dépôt et créer la clé SSH

Le point 2 consiste à préparer une clé SSH dédiée au projet et à empêcher Git de versionner les fichiers sensibles. Cette méthode reprend J3-05 et J4 : seule la clé publique est transmise à l'infrastructure, tandis que la clé privée reste sur la machine de travail.

Le fichier `.gitignore` doit contenir les exclusions suivantes :

```gitignore
.keys/*
.vault-pass
.terraform/
*.tfstate
*.tfstate.*
collections/
roles/geerlingguy.git/
```

Ces règles empêchent notamment le versionnage de la clé privée, du mot de passe Vault, du state Terraform et des dépendances téléchargées par Ansible Galaxy. Aucun secret ne doit être ajouté dans Git, un template, une variable en clair ou un output Terraform.

Créer ensuite le dossier local des clés et limiter ses permissions :

```bash
mkdir -p .keys
chmod 700 .keys
```

Générer une paire de clés Ed25519 dédiée au projet :

```bash
ssh-keygen -t ed25519 -f .keys/taylor-shift -N ""
chmod 600 .keys/taylor-shift
chmod 644 .keys/taylor-shift.pub
```

La commande crée deux fichiers :

- `.keys/taylor-shift` est la clé privée. Elle ne doit jamais être copiée dans Git, Terraform state ou un message ;
- `.keys/taylor-shift.pub` est la clé publique. Elle pourra être importée dans Floci ou transmise à Terraform pour configurer les EC2.

Vérifier que Git ignore bien les deux fichiers :

```bash
git check-ignore -v .keys/taylor-shift .keys/taylor-shift.pub
```

La commande doit afficher la règle `.keys/*` pour chaque fichier. Si elle n'affiche rien, corriger `.gitignore` avant de continuer.

Vérifier également l'état du dépôt :

```bash
git status --short
```

La clé privée et la clé publique ne doivent pas apparaître comme fichiers non suivis. La clé publique ne sera utilisée qu'au prochain point, lors de la préparation de Floci ou de la création Terraform des EC2.
