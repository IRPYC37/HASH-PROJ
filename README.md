# Taylor Shift's Ticket Shop


Déploiement de la boutique PrestaShop (image `prestashop/prestashop` de Docker
Hub). Terraform crée l'infrastructure, Ansible configure les serveurs et
déploie l'application. Tout tourne sur Floci, comme dans les labs.

## 1. Architecture

```text
Mode floci (défaut) :
  navigateur -> localhost:8080 (relais socat) -> EC2 : Nginx :80 -> PrestaShop :8080 -> MariaDB (conteneur)

Mode aws (-var deployment_mode=aws) :
  Internet -> ALB :80 -> Auto Scaling Group (EC2 : PrestaShop) -> RDS MariaDB (subnet privé)
```

| Composant | Emplacement | Raison |
|---|---|---|
| PrestaShop | EC2, conteneur Docker derrière Nginx | image imposée, reverse proxy configuré par template |
| Base de données | floci : conteneur MariaDB sur l'EC2 / aws : RDS | RDS partagé par toutes les instances, sauvegardes gérées |
| Répartition de charge | ALB (aws) | health check, routage vers les instances saines |
| Montée en charge | Auto Scaling Group (aws) | min/max par environnement |
| Secrets | Ansible Vault (floci), Secrets Manager + rôle IAM (aws) | aucun mot de passe en clair |
| Sauvegardes | cron + bucket S3 chiffré et versionné (module `bucket_sauvegarde`) | restauration par `ansible/restaurer.yml` |
| Inventaire | `ansible_host` / `ansible_group` dans le state | lu par `cloud.terraform.terraform_provider` |

Rôles Ansible : `geerlingguy.git` (Galaxy), `durcissement`, `pare_feu`,
`application`, `nginx`, `sauvegarde`.

## 2. Prérequis

Terraform >= 1.11, ansible-core 2.20.x (la collection `cloud.terraform` 4.0.0
ne fonctionne pas avec la 2.21), AWS CLI v2, Docker et Floci.

Sous Windows, cloner le dépôt dans le dossier Linux de WSL (`~/`) et pas dans
`/mnt/c`. Sinon Ansible ignore `ansible.cfg` et SSH refuse la clé privée.

```bash
floci start
eval $(floci env)
```

## 3. Avant les commandes d'évaluation

Créer la clé SSH du projet (elle n'est pas versionnée) :

```bash
mkdir -p .keys && ssh-keygen -t ed25519 -f .keys/taylor-shift -N ""
```

Créer le bucket du state Terraform, que le backend S3 ne peut pas créer
lui-même :

```bash
aws --endpoint-url http://localhost.floci.io:4566 s3api create-bucket \
  --bucket taylor-shift-terraform-state
aws --endpoint-url http://localhost.floci.io:4566 s3api put-bucket-versioning \
  --bucket taylor-shift-terraform-state --versioning-configuration Status=Enabled
```

Pour dev (workspace `default`), le state est `terraform.tfstate` à la racine du
bucket. Les autres environnements sont dans
`taylor-shift/<workspace>/terraform.tfstate`. Le verrou est géré par
`use_lockfile`.

Le mot de passe Vault est donné à part. Il est demandé par `--ask-vault-pass`,
pas besoin de fichier `.vault-pass`. Le fichier
`ansible/group_vars/all/vault.yml` est déjà chiffré.

## 4. Déploiement

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply
ansible-galaxy install -r ansible/requirements.yml
ansible-inventory -i ansible/inventory.yml --graph
ansible-playbook -i ansible/inventory.yml ansible/site.yml --ask-vault-pass
ansible-playbook -i ansible/inventory.yml ansible/site.yml --ask-vault-pass
```

Le second passage doit finir avec `changed=0`.

### Accès à l'application

En dev : http://localhost:8080. L'URL est aussi donnée par
`terraform -chdir=terraform output floci_urls` et affichée à la fin du playbook.

Floci ne publie vers le poste que le port SSH des instances. Le rôle
`application` lance donc sur le poste un petit conteneur relais (`socat`) qui
renvoie vers Nginx. Ports utilisés : dev 8080, staging 8090, prod 8100
(+1 par instance supplémentaire). Ce port sert aussi de domaine à PrestaShop.

### Vérifier la base

La page d'accueil affiche le catalogue, qui vient de MariaDB. Pour vérifier
directement :

```bash
ansible webservers -i ansible/inventory.yml -b --ask-vault-pass -m ansible.builtin.shell \
  -a 'docker exec db sh -c "mariadb -uroot -p\$MYSQL_ROOT_PASSWORD -e \"SELECT COUNT(*) FROM prestashop.ps_product\""'
```

## 5. Environnements

Chaque environnement a son workspace et son fichier de réglages
(`terraform/envs/<env>.tfvars`), à utiliser ensemble. dev utilise le workspace
`default`, celui des commandes d'évaluation. `terraform/checks.tf` vérifie que
le workspace correspond à l'environnement.

```bash
terraform -chdir=terraform workspace select -or-create staging
terraform -chdir=terraform apply -var-file=envs/staging.tfvars
terraform -chdir=terraform workspace select default
```

Les tailles sont définies dans `terraform/environments.tf`. `envs/prod.tfvars`
passe en mode aws : il faut y mettre l'IP de l'opérateur dans
`allowed_ssh_cidr`.

| Env | EC2 | Type | ASG min/max | RDS | Rétention |
|---|---:|---|---:|---|---:|
| dev | 1 | t3.micro | 1/2 | db.t3.micro | 1 j |
| staging | 2 | t3.small | 1/3 | db.t3.micro | 3 j |
| prod | 2 | t3.medium | 2/4 | db.t3.small | 7 j |

En mode floci, chaque environnement a ses propres ports (voir partie 4), donc
dev et staging peuvent tourner en même temps.

## 6. Trafic, panne et limites

- Mode aws : l'ALB teste `/` toutes les 30 s. Après 3 échecs, l'instance est
  retirée et le trafic part vers les autres. L'ASG la remplace (health check
  ELB) et une alarme CloudWatch se déclenche. Quand la charge monte, une
  politique de suivi de cible (`aws_autoscaling_policy`, 60 % de CPU moyen
  réglable avec `asg_cpu_target`) ajoute des instances jusqu'à `asg_max_size`,
  puis les retire quand la charge baisse, sans descendre sous `asg_min_size`.
- Mode floci : une seule EC2. Les conteneurs redémarrent tout seuls
  (`unless-stopped`). Si l'instance disparaît, le site est coupé jusqu'au
  prochain `terraform apply` suivi du playbook.

Limites :

- ALB, ASG, RDS et CloudWatch ne sont pas créés sur Floci, donc le mode aws n'a
  pas été déployé. Pour un vrai compte, il faut adapter `provider.tf` et
  `backend.tf`, qui pointent vers Floci.
- Sur Floci, relancer `apply` sur une infrastructure existante échoue. Il faut
  faire `destroy` puis `apply`.
- Les instances créées par l'ASG sont préparées par `user_data`, pas par
  Ansible.
- Le scaling met quelques minutes à réagir. Pour l'ouverture des ventes, mieux
  vaut monter `asg_min_size` à l'avance.
- Les images produits restent sur chaque instance (pas d'EFS) et RDS est sur
  une seule zone de disponibilité.
- Pas de CDN ni de cache devant l'ALB.

## 7. Sécurité

- Un security group par couche : l'ALB accepte le port 80, les EC2 n'acceptent
  que l'ALB, RDS n'accepte que les EC2. En floci il n'y a pas d'ALB, donc le
  port 80 des EC2 est ouvert.
- SSH : `0.0.0.0/0` est accepté seulement en mode floci. En mode aws, Terraform
  refuse l'apply tant que `allowed_ssh_cidr` n'est pas restreint
  (`-var 'allowed_ssh_cidr=<IP>/32'`).
- Mots de passe de la base : dans Ansible Vault en mode floci. En mode aws, ils
  sont dans Secrets Manager (créé seulement dans ce mode) et les EC2 les lisent
  grâce à leur rôle IAM. Aucun output ne contient de secret.
- La clé privée est passée à Ansible par son chemin, jamais par son contenu.
- Durcissement SSH (pas de mot de passe), sysctl et pare-feu UFW (ports 22 et
  80).

## 8. Exploitation

Une sauvegarde tourne chaque nuit à 2 h : dump SQL dans
`/var/backups/taylor-shift`, envoyé sur S3 en mode aws. Pour restaurer :

```bash
ansible-playbook -i ansible/inventory.yml ansible/restaurer.yml --ask-vault-pass \
  -e serveur=web1 \
  -e restauration_archive=/var/backups/taylor-shift/taylor-shift-AAAA-MM-JJ.tar.gz
```

Sans `-e serveur=...`, le playbook ne touche aucune machine.

En mode aws, les alarmes CloudWatch (instance en échec, CPU RDS) sont envoyées
sur un topic SNS. `-var alert_email=<adresse>` permet de s'y abonner par
e-mail.

Pour détruire dev (le relais local n'est pas géré par Terraform) :

```bash
terraform -chdir=terraform destroy
docker rm -f taylor-shift-dev-http-web1
```

Pour staging ou prod, sélectionner le workspace et ajouter
`-var-file=envs/<env>.tfvars`, comme dans la partie 5.
