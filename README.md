# Taylor Shift's Ticket Shop

Déploiement de la boutique PrestaShop (image `prestashop/prestashop` de Docker
Hub) : Terraform crée l'infrastructure, Ansible configure les serveurs et
déploie l'application. L'environnement cible est Floci, comme dans les labs.

## 1. Architecture

```text
Mode floci (défaut) :
  navigateur -> localhost:30080 (relais socat) -> EC2 : Nginx :80 -> PrestaShop :8080 -> MariaDB (conteneur)

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

Terraform ≥ 1.11, ansible-core 2.20.x (`cloud.terraform` 4.0.0 ne marche pas
en 2.21), AWS CLI v2, Docker, Floci.

Sous Windows, travailler dans WSL et cloner le dépôt dans le dossier personnel
Linux (`~/`), pas sous `/mnt/c` : sinon Ansible ignore `ansible.cfg` (dossier
« world writable ») et SSH refuse la clé privée (droits `777`).

```bash
floci start
eval $(floci env)
```

## 3. Avant les commandes d'évaluation

Clé SSH du projet (ignorée par git) :

```bash
mkdir -p .keys && ssh-keygen -t ed25519 -f .keys/taylor-shift -N ""
```

Bucket du state Terraform (le backend S3 ne peut pas le créer lui-même) :

```bash
aws --endpoint-url http://localhost.floci.io:4566 s3api create-bucket \
  --bucket taylor-shift-terraform-state
aws --endpoint-url http://localhost.floci.io:4566 s3api put-bucket-versioning \
  --bucket taylor-shift-terraform-state --versioning-configuration Status=Enabled
```

Le state du workspace `default` (dev) est `terraform.tfstate` à la racine du
bucket ; les autres workspaces sont stockés sous
`taylor-shift/<workspace>/terraform.tfstate`. Verrou natif par `use_lockfile`.

Le mot de passe Vault est transmis séparément par l'équipe et saisi par
`--ask-vault-pass` : aucun fichier `.vault-pass` n'est nécessaire.
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

**http://localhost:30080** (web1 ; web2 = 30081…). L'URL est donnée par
`terraform -chdir=terraform output floci_urls` et affichée par la dernière
tâche du playbook.

Floci ne publie sur le poste que le port SSH des instances (en 2.1.0, le relais
du port 80 décrit dans les labs n'est pas créé). Le rôle `application` démarre
donc sur le poste un conteneur relais `taylor-shift-http-web1` (`alpine/socat`)
vers Nginx, sur le port fixé par Terraform (`floci_http_port_base`, 30080 par
défaut). Ce port est aussi le domaine enregistré dans PrestaShop.

### Vérifier la base

La page d'accueil affiche le catalogue, lu dans MariaDB. Depuis le poste :

```bash
ansible webservers -i ansible/inventory.yml -b --ask-vault-pass -m ansible.builtin.shell \
  -a 'docker exec db sh -c "mariadb -uroot -p\$MYSQL_ROOT_PASSWORD -e \"SELECT COUNT(*) FROM prestashop.ps_product\""'
```

## 5. Environnements

Un workspace par environnement ; `var.environnement` doit avoir la même valeur
(vérifié par `terraform/checks.tf`).

```bash
terraform -chdir=terraform workspace new staging
terraform -chdir=terraform apply -var environnement=staging
```

| Env | EC2 | Type | ASG min/max | RDS | Rétention |
|---|---:|---|---:|---|---:|
| dev | 1 | t3.micro | 1/2 | db.t3.micro | 1 j |
| staging | 2 | t3.small | 1/3 | db.t3.micro | 3 j |
| prod | 2 | t3.medium | 2/4 | db.t3.small | 7 j |

## 6. Trafic, panne et limites

- **Mode aws** : l'ALB interroge `/` toutes les 30 s ; après 3 échecs, une
  instance est retirée du routage et le trafic va aux autres. L'ASG (health
  check ELB) la remplace, et une alarme CloudWatch signale l'hôte en échec.
  En cas de pic, une politique de suivi de cible (`aws_autoscaling_policy`,
  CPU moyen visé `asg_cpu_target` = 60 %) ajoute des instances jusqu'à
  `asg_max_size`, puis les retire quand la charge retombe (jamais sous
  `asg_min_size`).
- **Mode floci** : une seule EC2. Les conteneurs redémarrent seuls
  (`unless-stopped`) ; si l'instance disparaît, le site est coupé jusqu'au
  prochain `terraform apply` + playbook.

Limites :

- Floci ne sert que le mode floci : ALB, ASG, RDS et CloudWatch n'y sont pas
  créés. Le mode aws n'a pas été déployé : `provider.tf` et `backend.tf`
  pointent vers Floci et doivent être adaptés pour un vrai compte.
- Floci 2.1.0 rattache l'instance au security group par défaut et renvoie les
  ID de SG référencés sous la forme `000000000000/sg-…` : un second `apply` sur
  une infrastructure existante propose donc des modifications que Floci refuse
  (`ModifyNetworkInterfaceAttribute`). Pour rejouer : `destroy` puis `apply`.
- Les instances de l'ASG sont préparées par `user_data`, pas par Ansible.
- Le scaling réagit au CPU en quelques minutes : un pic brutal à l'ouverture
  des ventes doit être anticipé en montant `asg_min_size` avant la vente.
- Les fichiers PrestaShop (images produits) restent locaux à chaque instance
  (pas d'EFS), et RDS est mono-AZ.
- Pas de CDN ni de cache devant l'ALB.

## 7. Sécurité

- Security groups séparés : ALB ouvert en 80, EC2 joignables depuis l'ALB
  seulement, RDS depuis les EC2 seulement.
- SSH : `0.0.0.0/0` n'est accepté qu'en mode floci (bac à sable local). En mode
  aws, Terraform refuse l'apply tant que `allowed_ssh_cidr` n'est pas restreint
  (`-var 'allowed_ssh_cidr=<IP>/32'`).
- Mot de passe de la base : Ansible Vault en mode floci ; en mode aws, secret
  Secrets Manager (créé seulement dans ce mode) lu par les EC2 via leur rôle IAM.
  Aucun output ne contient de secret.
- Clé privée transmise à Ansible par son chemin, jamais par son contenu.
- Durcissement SSH (pas de mot de passe), sysctl, pare-feu UFW (22 et 80).

## 8. Exploitation

Sauvegarde quotidienne à 2 h (dump SQL dans `/var/backups/taylor-shift`,
envoi S3 en mode aws). Restauration :

```bash
ansible-playbook -i ansible/inventory.yml ansible/restaurer.yml --ask-vault-pass \
  -e restauration_archive=/var/backups/taylor-shift/taylor-shift-AAAA-MM-JJ.tar.gz
```

Destruction :

```bash
terraform -chdir=terraform destroy -var environnement=<env>
```
