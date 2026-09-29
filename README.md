# Taylor Shift's Ticket Shop

Groupe : Allan Pinto, Cyprien Fournier

Infrastructure de la boutique de billets Taylor Shift, basée sur PrestaShop
(image `prestashop/prestashop` de Docker Hub). Terraform crée l'infrastructure
AWS et génère l'inventaire Ansible. Ansible configure ensuite les serveurs et
déploie l'application.

Le projet est déployé en local sur Floci, un émulateur des API AWS déployé via
Docker.

## Architecture globale

```text
Mode floci (défaut) :
  navigateur -> localhost:8080 (relais socat) -> EC2 : Nginx :80 -> PrestaShop :8080 -> MariaDB (conteneur)

Mode aws (-var deployment_mode=aws) :
  Internet -> ALB :80 -> Auto Scaling Group (EC2 : PrestaShop) -> RDS MariaDB (subnet privé)
```

- Mode `floci` (par défaut) : une EC2 porte toute l'application. Nginx reçoit
  les requêtes et les transmet à PrestaShop, qui utilise une base MariaDB en
  conteneur sur la même machine.
- Mode `aws` : la cible de production. Un Application Load Balancer répartit
  les requêtes entre plusieurs EC2 qui partagent une base RDS privée.
- Terraform écrit l'inventaire Ansible dans son state, Ansible le lit : aucune
  adresse n'est écrite à la main.

## Stack technique

### Infrastructure

- Terraform (providers `aws`, `ansible`, `random`)
- Floci pour émuler AWS en local
- State distant dans un bucket S3, verrouillé par `use_lockfile`

### Configuration

- Ansible (ansible-core 2.20)
- Collections Galaxy : `cloud.terraform`, `community.docker`,
  `community.general`, `ansible.posix`
- Rôle Galaxy : `geerlingguy.git`
- Rôles du projet : `durcissement`, `pare_feu`, `nginx`, `application`,
  `sauvegarde`
- Ansible Vault pour les mots de passe

### Application

- PrestaShop et MariaDB en conteneurs Docker
- Nginx en reverse proxy

## Choix techniques (et pourquoi)

- **PrestaShop sur EC2 en conteneur** : image imposée, et Nginx devant permet
  de configurer le proxy par template Ansible.
- **RDS en production** : une seule base partagée par toutes les instances,
  avec sauvegardes gérées par AWS. Sur Floci, MariaDB tourne en conteneur.
- **ALB + Auto Scaling Group** : répartition de charge, remplacement des
  instances en panne et ajout d'instances quand le trafic monte.
- **Inventaire dynamique `cloud.terraform.terraform_provider`** : recréer une
  instance ne demande aucune modification côté Ansible.
- **Ansible Vault et Secrets Manager** : Vault chiffre les secrets du dépôt,
  Secrets Manager garde le mot de passe RDS, lu par les EC2 via leur rôle IAM.
- **Relais socat** : Floci ne rend joignable que le port SSH des instances, le
  relais expose le site sur le poste.
- **Un workspace par environnement** : dev, staging et prod ont chacun leur
  state et ne peuvent pas s'écraser.

## Installation

### Prérequis

- Terraform >= 1.11
- ansible-core 2.20.x (la collection `cloud.terraform` 4.0.0 ne fonctionne pas
  avec la 2.21)
- AWS CLI v2, Docker et Floci
- Sous Windows : cloner le dépôt dans le dossier Linux de WSL (`~/`), pas dans
  `/mnt/c`, sinon Ansible ignore `ansible.cfg` et SSH refuse la clé privée

Démarrer Floci et charger ses identifiants :

```bash
floci start
eval $(floci env)
```

Si `floci env` n'est pas disponible dans WSL, exporter les identifiants à la
main (Floci ne les vérifie pas) :

```bash
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
```

### Préparation

Clé SSH du projet (non versionnée) : Terraform installe la clé publique sur
les instances, Ansible utilise la clé privée pour s'y connecter.

```bash
mkdir -p .keys && ssh-keygen -t ed25519 -f .keys/taylor-shift -N ""
```

Bucket du state Terraform. Terraform en a besoin dès `init`, il ne peut donc
pas le créer lui-même.

```bash
aws --endpoint-url http://localhost.floci.io:4566 s3api create-bucket \
  --bucket taylor-shift-terraform-state
aws --endpoint-url http://localhost.floci.io:4566 s3api put-bucket-versioning \
  --bucket taylor-shift-terraform-state --versioning-configuration Status=Enabled
```

- Le state de dev est `terraform.tfstate` à la racine du bucket, ceux des
  autres environnements sont sous `taylor-shift/<workspace>/terraform.tfstate`.
- Floci garde ses données en mémoire : après un redémarrage de Docker ou de
  Floci, tout disparaît et il faut reprendre à partir du bucket.
- Les mots de passe de la base sont chiffrés dans
  `ansible/group_vars/all/vault.yml`. Le mot de passe du coffre est transmis
  séparément (fichier `.env` fourni avec la remise) et demandé
  par `--ask-vault-pass`.

### Déploiement

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply
ansible-galaxy install -r ansible/requirements.yml
ansible-inventory -i ansible/inventory.yml --graph
ansible-playbook -i ansible/inventory.yml ansible/site.yml --ask-vault-pass
ansible-playbook -i ansible/inventory.yml ansible/site.yml --ask-vault-pass
```

- `ansible-inventory` doit afficher le groupe `webservers` avec `web1`.
- Le premier playbook installe tout (quelques minutes, le temps de télécharger
  les images et d'installer PrestaShop).
- Le second doit finir avec `changed=0`.

### Accès à l'application

L'application est disponible sur : http://localhost:8080

- L'URL est aussi donnée par `terraform -chdir=terraform output floci_urls`.
- Erreur 502 juste après le premier passage : attendre une minute, PrestaShop
  termine son installation.
- Ports par environnement : dev 8080, staging 8090, prod 8100 (+1 par instance
  supplémentaire). Si 8080 est déjà pris, en choisir un autre avec
  `-var floci_http_port_base=<port>` lors de l'`apply`.

### Vérifier la base

Le catalogue affiché sur la page d'accueil vient de MariaDB. Pour interroger la
base directement (19 produits avec les données de démonstration) :

```bash
ansible webservers -i ansible/inventory.yml -b --ask-vault-pass -m ansible.builtin.shell \
  -a 'docker exec db sh -c "mariadb -uroot -p\$MYSQL_ROOT_PASSWORD -e \"SELECT COUNT(*) FROM prestashop.ps_product\""'
```

## Environnements

Chaque environnement a son workspace et son fichier `terraform/envs/<env>.tfvars`,
toujours utilisés ensemble. dev utilise le workspace `default`.

```bash
terraform -chdir=terraform workspace select -or-create staging
terraform -chdir=terraform apply -var-file=envs/staging.tfvars
terraform -chdir=terraform workspace select default
```

| Env | EC2 | Type | ASG min/max | RDS | Rétention |
|---|---:|---|---:|---|---:|
| dev | 1 | t3.micro | 1/2 | db.t3.micro | 1 j |
| staging | 2 | t3.small | 1/3 | db.t3.micro | 3 j |
| prod | 2 | t3.medium | 2/4 | db.t3.small | 7 j |

- Les tailles sont définies dans `terraform/environments.tf`.
- `envs/prod.tfvars` passe en mode aws : y mettre l'IP de l'opérateur dans
  `allowed_ssh_cidr`.
- `terraform/checks.tf` signale un workspace qui ne correspond pas à
  l'environnement.
- Les ressources et les ports sont propres à chaque environnement : dev et
  staging peuvent tourner en même temps.

## Trafic et pannes

### Chemin d'une requête

- Mode aws : le navigateur contacte l'ALB, seul point d'entrée public. L'ALB
  envoie chaque requête à une EC2 en bonne santé. Toutes les EC2 utilisent la
  même base RDS, donc n'importe laquelle peut répondre.
- Mode floci : une seule EC2 reçoit tout le trafic par le relais.

### Montée en charge

- Une politique de suivi de cible (`aws_autoscaling_policy`) vise 60 % de CPU
  moyen (`asg_cpu_target`).
- Au-dessus, l'Auto Scaling Group ajoute des instances jusqu'à `asg_max_size`.
- Quand la charge baisse, il les retire, sans descendre sous `asg_min_size`.

### Si une instance tombe

- Mode aws : l'ALB teste `/` toutes les 30 s. Après 3 échecs, il retire
  l'instance et envoie le trafic aux autres, sans coupure pour les clients.
- Une instance de l'ASG est remplacée automatiquement. Une EC2 configurée par
  Ansible (`web1`, ...) est recréée par `terraform apply` puis le playbook.
- Une alarme CloudWatch signale l'instance en échec.
- Mode floci : une seule instance, le site est coupé. Les conteneurs
  redémarrent seuls (`unless-stopped`), mais si l'instance disparaît il faut
  relancer `terraform apply` puis le playbook.

### Limites

- Le mode aws n'a été ni déployé ni testé : la démonstration utilise le mode
  floci. Pour un vrai compte, adapter `provider.tf` et `backend.tf`, qui
  pointent vers Floci.
- Sur Floci, relancer `apply` sur une infrastructure existante échoue : faire
  `destroy` puis `apply`.
- Les instances ajoutées par l'ASG sont préparées par `user_data`, pas par
  Ansible.
- Le scaling met quelques minutes à réagir : monter `asg_min_size` avant
  l'ouverture des ventes.
- Les images produits restent sur chaque instance (pas d'EFS) et RDS n'est que
  dans une zone de disponibilité.
- Pas de CDN ni de cache devant l'ALB.

## Sécurité

- Un security group par couche : l'ALB accepte le port 80, les EC2 n'acceptent
  que l'ALB, RDS n'accepte que les EC2 et n'est pas public. En floci, sans ALB,
  le port 80 des EC2 est ouvert.
- SSH ouvert à tous par défaut, acceptable en local sur Floci. En mode aws,
  Terraform affiche un avertissement tant que `allowed_ssh_cidr` n'est pas
  restreint (`-var 'allowed_ssh_cidr=<IP>/32'`).
- Mots de passe de la base : Ansible Vault en floci, Secrets Manager en aws.
  Aucun output Terraform ne contient de secret.
- La clé privée est passée à Ansible par son chemin, jamais par son contenu.
- Sur les instances : SSH par clé uniquement, réglages réseau du noyau durcis
  (sysctl) et pare-feu UFW limité aux ports 22 et 80.

## Exploitation

### Sauvegarde et restauration

- Le script `/usr/local/sbin/taylor-shift-backup` tourne chaque nuit à 2 h.
- Il exporte la base dans `/var/backups/taylor-shift` et garde 7 jours
  d'archives. En mode aws, il les envoie aussi dans un bucket S3 chiffré et
  versionné.
- `ansible/restaurer.yml` arrête PrestaShop, réinjecte le dump dans MariaDB et
  redémarre PrestaShop :

```bash
ansible-playbook -i ansible/inventory.yml ansible/restaurer.yml --ask-vault-pass \
  -e serveur=web1 \
  -e restauration_archive=/var/backups/taylor-shift/taylor-shift-AAAA-MM-JJ.tar.gz
```

Sans `-e serveur=...`, le playbook ne touche aucune machine. En mode aws, la
base RDS se restaure depuis ses sauvegardes automatiques (rétention par
environnement, voir le tableau des environnements).

### Supervision

En mode aws, deux alarmes CloudWatch surveillent les instances en échec
derrière l'ALB et le CPU de RDS. Elles sont visibles dans la console
CloudWatch.

### Mises à jour

- Version de PrestaShop : changer `application_image` dans
  `ansible/roles/application/defaults/main.yml`, puis relancer le playbook
  (tester d'abord en staging).
- Mot de passe du coffre : `ansible-vault rekey ansible/group_vars/all/vault.yml`.
- Secrets : `ansible-vault edit ansible/group_vars/all/vault.yml`. Les mots de
  passe MariaDB ne sont appliqués qu'à la création de la base : après un
  changement, redéployer (`destroy` puis `apply` et playbook).
- Dépendances Galaxy : modifier les versions dans `ansible/requirements.yml`,
  puis `ansible-galaxy install -r ansible/requirements.yml --force`.
- Taille et nombre d'instances : `terraform/environments.tf`.

### Destruction

Pour détruire dev (le relais local n'est pas géré par Terraform) :

```bash
terraform -chdir=terraform destroy
docker rm -f taylor-shift-dev-http-web1
```

Pour staging ou prod, sélectionner le workspace et ajouter
`-var-file=envs/<env>.tfvars`.
