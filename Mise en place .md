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

## 5. Créer et vérifier le backend Terraform

Le bucket du backend doit exister avant `terraform init`. Avec Floci, démarrer
le conteneur puis charger les identifiants fictifs :

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

Créer le bucket une seule fois :

```bash
aws --endpoint-url http://localhost.floci.io:4566 s3api create-bucket \
	--bucket taylor-shift-terraform-state \
	--region us-east-1
```

Activer le versioning et le chiffrement côté serveur :

```bash
aws --endpoint-url http://localhost.floci.io:4566 s3api put-bucket-versioning \
	--bucket taylor-shift-terraform-state \
	--versioning-configuration Status=Enabled

aws --endpoint-url http://localhost.floci.io:4566 s3api put-bucket-encryption \
	--bucket taylor-shift-terraform-state \
	--server-side-encryption-configuration \
	'{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

Initialiser le backend et contrôler Terraform :

```bash
terraform -chdir=terraform init -reconfigure
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan
```

Le fichier `terraform/backend.tf` utilise la clé distante
`taylor-shift/dev/terraform.tfstate`, le verrou natif `use_lockfile = true` et
l'endpoint S3 Floci. Pour un vrai AWS, retirer les options spécifiques à Floci
et utiliser un bucket backend distinct par environnement.

Vérifier le backend :

```bash
terraform -chdir=terraform state pull
aws --endpoint-url http://localhost.floci.io:4566 s3api get-bucket-versioning \
	--bucket taylor-shift-terraform-state
aws --endpoint-url http://localhost.floci.io:4566 s3api get-bucket-encryption \
	--bucket taylor-shift-terraform-state
```

Le state ne doit pas être créé dans le dépôt. Les dossiers `.terraform/` et les
fichiers `*.tfstate` doivent rester ignorés par `.gitignore`.

## 4. Vérifier l'organisation Terraform

La partie Terraform est organisée par responsabilité :

| Fichier | Responsabilité | Vérification |
|---|---|---|
| `versions.tf` | Versions Terraform et providers | `terraform version` puis `terraform init` |
| `provider.tf` | Provider AWS dirigé vers Floci pour les labs | Variables factices `test` et région `us-east-1` |
| `backend.tf` | State S3 et verrouillage natif | `terraform init` puis `terraform state pull` |
| `variables.tf` | Types, descriptions, validations et secrets | `terraform validate` |
| `reseau.tf` | VPC, subnets, routes et security groups | `terraform plan` |
| `instances.tf` | Clé publique et EC2 gérées par Ansible | `terraform state list` |
| `scaling.tf` | Launch Template et Auto Scaling Group | Vérification du plan AWS cible |
| `load_balancer.tf` | ALB, listener, target group et health check | Vérification de l'endpoint ALB |
| `database.tf` | RDS privé et subnet group | Vérification de l'endpoint RDS |
| `ansible.tf` | `ansible_host` et `ansible_group` dans le state | `ansible-inventory --graph` |
| `secrets.tf` | Secrets Manager et paramètre SSM non secret | `terraform output` sans valeur secrète |
| `iam.tf` | Profil EC2 et permissions minimales | Lecture de la policy IAM |
| `sauvegardes.tf` | Versioning, chiffrement et blocage public S3 | Vérification AWS/S3 |
| `supervision.tf` | Alarmes CloudWatch | Vérification CloudWatch |
| `outputs.tf` | Endpoints et ARN non sensibles | Aucun mot de passe dans les outputs |

Vérifier toute la configuration depuis la racine du projet :

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan
```

## 6. Séparer les environnements

Les inventaires Ansible suivants sont conservés pour respecter la séparation
des environnements :

```text
ansible/inventories/
├── dev/
├── staging/
└── prod/
```

L'inventaire principal reste dynamique et vient du state Terraform. Les
répertoires ci-dessus servent à conserver les variables propres à chaque
environnement si le projet en ajoute. La variable `environnement` est limitée
à `dev`, `staging` et `prod`, et le préfixe de toutes les ressources contient
sa valeur.

Le backend S3 utilise un workspace différent pour chaque environnement. Avec
la configuration actuelle, les states sont stockés ainsi :

```text
s3://taylor-shift-terraform-state/taylor-shift/dev/terraform.tfstate
s3://taylor-shift-terraform-state/taylor-shift/staging/terraform.tfstate
s3://taylor-shift-terraform-state/taylor-shift/prod/terraform.tfstate
```

Créer puis sélectionner un environnement avant tout plan ou apply :

```bash
terraform -chdir=terraform workspace list
terraform -chdir=terraform workspace select dev || terraform -chdir=terraform workspace new dev
terraform -chdir=terraform workspace select staging || terraform -chdir=terraform workspace new staging
terraform -chdir=terraform plan -var='environnement=staging'
terraform -chdir=terraform workspace select dev
```

Les profils de capacité sont appliqués automatiquement par
`terraform/environments.tf` :

| Environnement | EC2 | Type EC2 | ASG min/max | RDS | Rétention |
|---|---:|---|---:|---|---:|
| `dev` | 1 | `t3.micro` | 1/2 | `db.t3.micro` | 1 jour |
| `staging` | 2 | `t3.small` | 1/3 | `db.t3.micro` | 3 jours |
| `prod` | 2 | `t3.medium` | 2/4 | `db.t3.small` | 7 jours |

Chaque environnement doit recevoir un mot de passe DB différent via
`TF_VAR_db_password`. Ne jamais exécuter `apply` de `staging` ou `prod` avec
le workspace `dev` sélectionné.

### 6.1 EC2 directe et Auto Scaling

`instances.tf` crée les EC2 de référence qui sont découvertes par l'inventaire
dynamique et configurées par Ansible. `scaling.tf` décrit le Launch Template
et l'ASG pour les instances supplémentaires ou le remplacement d'une instance
défaillante. Le `user_data` du Launch Template installe Docker et démarre
PrestaShop afin qu'une instance créée automatiquement soit utilisable avant
son éventuelle configuration Ansible.

Cette duplication est volontaire pour la démonstration : l'EC2 garantit le
chemin de test Ansible, tandis que l'ASG fournit la capacité et le remplacement
automatique. En production, on peut remplacer l'EC2 de référence par une AMI
préconfigurée et laisser l'ASG gérer toutes les instances.

### 6.2 Secret de base de données

Le mot de passe RDS ne doit pas être écrit dans un output. Pour une cible AWS,
les instances utilisent leur rôle IAM pour lire le secret Secrets Manager au
démarrage. Le secret transmis par `ansible_host` sert uniquement au scénario
Floci simplifié et peut apparaître dans le state : ce mode ne doit pas être
utilisé comme modèle de sécurité production. Le contrôle à effectuer avant
AWS réel est :

```bash
terraform -chdir=terraform output | grep -i password
```

La commande ne doit rien afficher. Pour AWS réel, supprimer toute variable de
mot de passe dans `ansible.tf` et faire récupérer le secret sur l'instance via
Secrets Manager et son profil IAM.

## 7. Générer l'inventaire avec Terraform

L'inventaire n'est pas écrit à la main. `terraform/ansible.tf` crée une
ressource `ansible_host` pour chaque EC2 et une ressource `ansible_group` pour
le groupe `webservers`. Les valeurs sont calculées à partir des ressources
Terraform :

- `terraform_instance_id` et `floci_instance` contiennent l'identifiant de
	l'instance créée ;
- `ansible_host` contient l'adresse publique fournie par l'instance ;
- `ansible_user`, `ansible_port` et le chemin de clé sont transmis comme
	variables de connexion ;
- les paramètres applicatifs et l'environnement viennent des ressources et
	variables Terraform.

Le contenu de la clé privée n'est jamais lu par Terraform. Seul son chemin est
transmis à Ansible :

```hcl
ansible_ssh_private_key_file = "${path.module}/${var.ssh_private_key_path}"
```

Le fichier `ansible/inventory.yml` active le plugin :

```yaml
plugin: cloud.terraform.terraform_provider
project_path: terraform
```

Après `terraform apply`, installer la collection et afficher l'inventaire :

```bash
ansible-galaxy collection install -r ansible/requirements.yml -p ansible/collections
export ANSIBLE_COLLECTIONS_PATH="$PWD/ansible/collections"
export ANSIBLE_INVENTORY_ENABLED=cloud.terraform.terraform_provider
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
ansible-inventory -i ansible/inventory.yml --graph
ansible-inventory -i ansible/inventory.yml --host web1
```

Le graphe doit afficher `webservers` et les hôtes `web1`, `web2`, etc. selon
le nombre d'instances de l'environnement actif. Une adresse IP ou un port
recopié dans un fichier d'inventaire constitue une erreur : toute modification
doit venir de Terraform.
