# Projet de fin HASH — Taylor Shift's Ticket Shop

## Consigne et notation du projet 

Taylor Shift's Ticket Shop
Project Context:
Group project of 3.

Taylor Shift's technical team has developed an e-commerce application for concert ticket sales. Your agency is responsible for deploying and configuring the infrastructure needed to host it and handle increased traffic when ticket sales begin.

The Challenge:
Deploy a scalable and reliable infrastructure for the existing application. The application is already developed, so your responsibility is limited to infrastructure deployment, server configuration, and documentation.

Key Objectives:
Infrastructure Deployment: Provision the infrastructure with Terraform.
Configuration Management: Configure the servers and deploy the application with Ansible.
Traffic Handling: Design the solution to remain available and responsive when traffic increases.
Documentation: Provide a concise README that allows the technical team to understand, operate, and maintain the solution.

Instructions:
Infrastructure Deployment:
Deploy the application using the generic PrestaShop image available on Docker Hub and connect it to a suitable database or data store.

Your solution must contain at least one EC2 instance provisioned with Terraform and configured with Ansible. It must also contain other relevant AWS resources.

You are free to decide which components run on EC2 and which use managed AWS services. For example, the application may run on EC2 with a managed database, or the database may run on EC2 while other components use AWS services. The completed architecture must work, support scaling, and be explained in the documentation.

Traffic Handling:
Explain how requests reach the application and how the proposed architecture handles increased traffic. You are free to choose the relevant AWS services and scaling strategy. Include the limits of your approach and describe what happens if an application instance becomes unavailable in your README.md and presentation

Configuration Management:
Use Ansible to configure the infrastructure provisioned by Terraform and deploy the application.

Your solution must use dynamic inventory with `cloud.terraform.terraform_provider`, reusable roles, Ansible Galaxy, Ansible Vault, templates, and handlers. Playbooks must be idempotent and must not contain plaintext secrets, private keys, or manually copied host addresses.

Deliverables:
Infrastructure Code: The Terraform code used to provision the infrastructure.
Configuration Code: The Ansible code used to configure the servers and deploy the application.
Documentation: A concise README that explains how to deploy, operate, and maintain the solution.
Presentation: A brief presentation covering the infrastructure choices, configuration management, and key considerations.

Project Testing:
The project will be tested using the commands below. You must document how to setup the backend for terraform state before the commands are run.


```sh
terraform -chdir=terraform init
terraform -chdir=terraform apply
ansible-galaxy install -r ansible/requirements.yml
ansible-inventory -i ansible/inventory.yml --graph
ansible-playbook -i ansible/inventory.yml ansible/site.yml --ask-vault-pass
ansible-playbook -i ansible/inventory.yml ansible/site.yml --ask-vault-pass
```

The second playbook run must report no unexpected changes. The evaluator will then access the documented application endpoint and verify its database or data-store connection.


Evaluation (30 pts)
Working solution (10 pts):

eCommerce application is deployed and reachable (3 pts)
Application is connected to a working database or data store (3 pts)
At least one EC2 instance is provisioned with Terraform and configured with Ansible (2 pts)
The complete solution can be deployed again from the submitted automation (2 pts)

Terraform and AWS infrastructure (7 pts):

Relevant AWS resources form a coherent architecture with a justified traffic-handling strategy (2 pts)
Code organisation, modules, variables, variable descriptions, and outputs (2 pts)
Environment separation (prod, staging, dev) (1 pt)
Remote state, locking, data sources, and resource references (1 pt)
Secure networking and secret handling (1 pt)

Ansible integration (6 pts):

Dynamic inventory generated from Terraform (2 pts)
Reusable roles and Ansible Galaxy (1 pt)
Ansible Vault and secure secret handling (1 pt)
Idempotent playbooks using templates and handlers (2 pts)

README for developers (4 pts):

Clarity and reproducible instructions (2 pts)
Briefness (1 pt)
Solution design choices, including the placement of components (1 pt)

Presentation (3 pts):

Clear explanation of the solution (1 pt)
Working demonstration (1 pt)
Ability to justify technical choices (1 pt)

Deadline:
Submit the project by the deadline communicated by the instructor.

## TODO global

- [ ] Déployer PrestaShop depuis l'image Docker Hub demandée.
- [ ] Connecter PrestaShop à une base persistante et fonctionnelle.
- [ ] Provisionner au moins une EC2 avec Terraform et la configurer avec Ansible.
- [ ] Ajouter les ressources AWS nécessaires à la sécurité, la disponibilité et la montée en charge.
- [ ] Utiliser l'inventaire dynamique `cloud.terraform.terraform_provider`.
- [ ] Utiliser Galaxy, Vault, des rôles, des templates et des handlers.
- [ ] Garantir `changed=0` au second lancement Ansible.
- [ ] Ne versionner aucun secret, aucune clé privée ni adresse copiée manuellement.
- [ ] Documenter déploiement, exploitation, maintenance, limites, sauvegarde et restauration.
- [ ] Préparer la présentation et une démonstration fonctionnelle.

## 1. Préparer l'environnement

- [ ] Travailler dans WSL2 Ubuntu, comme dans les labs J3 et J4.
- [ ] Installer Terraform `1.11+`, Ansible Core `2.20.x`, AWS CLI v2, Docker et OpenSSH.
- [ ] Vérifier les outils :

```bash
terraform version
ansible --version
ansible-galaxy --version
aws --version
docker --version
ssh -V
```

- [ ] Ne pas utiliser Ansible `2.21+` avec la collection `cloud.terraform` du J4.
- [ ] Pour Floci uniquement, utiliser des identifiants factices :

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

- [ ] Vérifier que Terraform, Ansible et Docker sont accessibles depuis WSL2.

## 2. Protéger le dépôt

- [ ] Créer la clé SSH :

```bash
mkdir -p .keys
ssh-keygen -t ed25519 -f .keys/taylor-shift -N ""
```

- [ ] Ne jamais versionner la clé privée.
- [ ] Vérifier dans `.gitignore` :

```gitignore
.keys/*
.vault-pass
.terraform/
*.tfstate
*.tfstate.*
collections/
roles/geerlingguy.git/
```

- [ ] Ne mettre aucun secret dans Git, un template, une variable en clair ou un output Terraform.

## 3. Choisir l'architecture

Architecture recommandée selon J4 :

```text
Internet -> Route 53 -> Application Load Balancer
								 -> Auto Scaling Group
									 -> EC2 + Docker + PrestaShop
								 -> RDS MySQL/MariaDB
```

- [ ] Placer PrestaShop sur EC2 dans Docker.
- [ ] Placer la base dans RDS, afin qu'elle soit partagée par toutes les EC2.
- [ ] Utiliser l'ALB pour répartir les requêtes et exécuter les health checks.
- [ ] Utiliser l'ASG pour remplacer une EC2 défaillante et absorber les pics.
- [ ] Expliquer le chemin d'une requête et le comportement lors d'une panne.
- [ ] Documenter les limites : capacité RDS, taille de l'ASG, coûts, région et absence éventuelle de cache.

Ressources à prévoir :

- [ ] VPC, subnets publics/privés, Internet Gateway et routes.
- [ ] Security groups séparés pour ALB, EC2 et RDS.
- [ ] ALB, listener, target group et health check.
- [ ] Launch Template, ASG et au moins une EC2.
- [ ] RDS MySQL/MariaDB.
- [ ] Secrets Manager, IAM et S3.
- [ ] `ansible_host` et `ansible_group` dans le state Terraform.

## 4. Organiser Terraform

Compléter `terraform/` par responsabilité :

| Fichier | TODO |
|---|---|
| `versions.tf` | [ ] Versions Terraform et providers épinglées. |
| `provider.tf` | [ ] Provider AWS configuré. |
| `backend.tf` | [ ] State distant S3 et verrouillage. |
| `variables.tf` | [ ] Types, descriptions, validations et variables sensibles. |
| `reseau.tf` | [ ] VPC, subnets, routes et security groups. |
| `instances.tf` | [ ] Clé publique, Launch Template, EC2 et ASG. |
| `load_balancer.tf` | [ ] ALB, listener, target group et health checks. |
| `database.tf` | [ ] RDS et sécurité réseau. |
| `ansible.tf` | [ ] Inventaire Ansible dans le state. |
| `secrets.tf` | [ ] Secrets Manager et paramètres SSM non secrets. |
| `iam.tf` | [ ] Permissions minimales. |
| `sauvegardes.tf` | [ ] Sauvegardes, versioning et chiffrement S3. |
| `supervision.tf` | [ ] Supervision si elle est provisionnée par Terraform. |
| `outputs.tf` | [ ] Endpoints et noms de ressources, jamais les valeurs secrètes. |

- [ ] Ajouter les modules réutilisables dans `terraform/modules/`.
- [ ] Utiliser les références Terraform et les data sources plutôt que des IDs écrits à la main.
- [ ] Séparer les states `dev`, `staging` et `prod`.

## 5. Créer et vérifier le backend

- [ ] Créer le bucket S3 avant Terraform.
- [ ] Activer versioning, chiffrement et verrouillage.
- [ ] Documenter son nom, sa région et sa création.

```bash
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan
```

- [ ] Vérifier que le backend distant est utilisé.
- [ ] Ne jamais committer `.terraform/` ou `*.tfstate`.

## 6. Séparer les environnements

Conserver :

```text
ansible/inventories/
├── dev/
├── staging/
└── prod/
```

- [ ] Créer une variable Terraform `environnement` limitée à ces trois valeurs.
- [ ] Utiliser un state, des noms et des secrets différents par environnement.
- [ ] Adapter nombre d'instances, tailles et limites à chaque environnement.

## 7. Générer l'inventaire avec Terraform

- [ ] Créer une ressource `ansible_host` par EC2 dans `terraform/ansible.tf`.
- [ ] Créer une ressource `ansible_group` pour `webservers`.
- [ ] Transmettre l'ID Terraform, l'utilisateur et les variables applicatives.
- [ ] Ne jamais recopier IP, port SSH ou hostname.
- [ ] Transmettre un chemin vers la clé, jamais son contenu :

```hcl
ansible_ssh_private_key_file = ".keys/taylor-shift"
```

- [ ] Ne jamais utiliser `file(".keys/taylor-shift")` pour la clé privée : son contenu fuiterait dans le state.

## 8. Activer l'inventaire dynamique

Dans `ansible/inventory.yml` :

```yaml
plugin: cloud.terraform.terraform_provider
project_path: ../terraform
```

Dans `ansible/ansible.cfg` :

- [ ] Définir l'inventaire, `roles_path`, `collections_path` et `interpreter_python`.
- [ ] Autoriser `cloud.terraform.terraform_provider`.
- [ ] Définir `vault_password_file = ../.vault-pass` après création du fichier.

```bash
ansible-inventory -i ansible/inventory.yml --graph
ansible-inventory -i ansible/inventory.yml --host web1
```

- [ ] Vérifier que les hôtes viennent du state Terraform.

## 9. Installer Galaxy

Dans `ansible/requirements.yml` :

- [ ] Déclarer `cloud.terraform` en version `4.0.0`.
- [ ] Déclarer `community.crypto` pour HTTPS si nécessaire.
- [ ] Déclarer `ansible.posix` pour durcissement et clés SSH.
- [ ] Déclarer les rôles externes utilisés avec une version épinglée.

```bash
ansible-galaxy install -r ansible/requirements.yml
ansible-galaxy collection list
ansible-galaxy role list
ansible-doc -t inventory cloud.terraform.terraform_provider
```

- [ ] Vérifier que la collection de l'inventaire est bien installée.
- [ ] Lire la documentation d'une collection avant d'utiliser ses modules.

## 10. Construire les rôles Ansible

Respecter la structure J3 :

```text
ansible/roles/
├── application/{defaults,tasks,handlers,templates,files}
├── nginx/{defaults,tasks,handlers,templates}
├── durcissement/{defaults,tasks,handlers,templates}
├── pare_feu/{defaults,tasks,handlers}
├── node_exporter/{defaults,tasks,handlers}
└── sauvegarde/{defaults,tasks,handlers,templates}
```

- [ ] `application` installe Docker, déploie PrestaShop et configure RDS.
- [ ] `nginx` configure reverse proxy, HTTPS, headers et limites.
- [ ] `durcissement` configure SSH, sysctl et clés autorisées.
- [ ] `pare_feu` filtre les ports localement.
- [ ] `node_exporter` expose les métriques.
- [ ] `sauvegarde` sauvegarde les données et planifie la tâche.
- [ ] Préfixer les variables par le rôle : `application_`, `nginx_`, etc.

## 11. Appliquer la méthode J3-05/J3-06

| Besoin | Module |
|---|---|
| Objet, dossier, droits | `file` |
| Contenu fixe | `copy` |
| Contenu calculé | `template` |
| Une ligne existante | `lineinfile` |
| Paquet | `apt` ou module adapté à l'OS |
| Service | `service` |
| Utilisateur | `user` |
| Téléchargement | `get_url` avec checksum |
| Commande inévitable | `register`, `changed_when`, `failed_when` |

- [ ] Ne pas utiliser `shell` ou `command` lorsqu'un module existe.
- [ ] Ne pas appliquer `lineinfile` sur un fichier produit par `template`.
- [ ] Utiliser `raw` uniquement pour installer Python sur une image qui ne l'a pas.

## 12. Déployer PrestaShop

- [ ] Créer `roles/application/templates/docker-compose.yml.j2`.
- [ ] Utiliser l'image PrestaShop demandée.
- [ ] Définir PrestaShop et sa connexion RDS.
- [ ] Passer hostname, base, utilisateur et mot de passe par variables.
- [ ] Définir les volumes persistants nécessaires.
- [ ] Créer les dossiers avec `file` et le compose avec `template`.
- [ ] Démarrer l'application avec un module Docker idempotent.
- [ ] Ajouter un handler déclenché uniquement lorsque la configuration change.
- [ ] Vérifier la réponse HTTP et la connexion à la base.

## 13. Utiliser Ansible Vault

```bash
umask 077
read -rsp "Mot de passe Vault : " VAULT_PASS
printf '%s\n' "$VAULT_PASS" > .vault-pass
unset VAULT_PASS
ansible-vault create ansible/group_vars/all/vault.yml
```

- [ ] Vérifier que le fichier commence par `$ANSIBLE_VAULT;`.
- [ ] Stocker les secrets applicatifs dans Vault ou les récupérer depuis Secrets Manager.
- [ ] Ajouter `vault_password_file = ../.vault-pass` dans `ansible/ansible.cfg`.
- [ ] Utiliser `no_log: true` sur les tâches manipulant des secrets.
- [ ] Ne jamais afficher une valeur secrète dans un output Terraform ou un log.

## 14. Écrire le playbook et les handlers

Dans `ansible/site.yml` :

- [ ] Déclarer les groupes et `gather_facts`.
- [ ] Déclarer les rôles uniquement, sans détailler leurs tâches.
- [ ] Appliquer dans cet ordre : `durcissement`, `pare_feu`, Docker, `nginx`, `application`, `node_exporter`, `sauvegarde`.

Handlers à prévoir :

- [ ] Recharger Nginx si son template change.
- [ ] Recharger SSH après validation de sa configuration.
- [ ] Redémarrer l'application uniquement après changement du compose.
- [ ] Redémarrer Node Exporter si sa configuration change.
- [ ] Ne jamais redémarrer un service systématiquement.
- [ ] Utiliser `validate` pour refuser une configuration invalide.

## 15. Valider progressivement

```bash
ansible-playbook -i ansible/inventory.yml ansible/site.yml --syntax-check
ansible-playbook -i ansible/inventory.yml ansible/site.yml --list-hosts
ansible-playbook -i ansible/inventory.yml ansible/site.yml --list-tasks
ansible -i ansible/inventory.yml webservers -m ansible.builtin.ping
```

- [ ] Installer Python une seule fois avec `raw` si nécessaire.
- [ ] Prévisualiser avec `--check --diff`.
- [ ] Appliquer avec `--ask-vault-pass`.
- [ ] Rejouer immédiatement.
- [ ] Obtenir au second passage `changed=0`, `failed=0`, `unreachable=0`.
- [ ] Vérifier qu'aucun handler ne s'exécute sans changement.

```bash
ansible-playbook -i ansible/inventory.yml ansible/site.yml --check --diff --ask-vault-pass
ansible-playbook -i ansible/inventory.yml ansible/site.yml --ask-vault-pass
ansible-playbook -i ansible/inventory.yml ansible/site.yml --ask-vault-pass
```

## 16. Vérifier disponibilité, sauvegarde et supervision

- [ ] Vérifier l'endpoint ALB avec `curl -I`.
- [ ] Vérifier la page PrestaShop et la connexion RDS.
- [ ] Créer une donnée et vérifier sa persistance.
- [ ] Arrêter une EC2 et vérifier son remplacement par l'ASG.
- [ ] Installer Node Exporter et déployer Prometheus.
- [ ] Ajouter des alertes pour disponibilité, charge et disque.
- [ ] Activer sauvegardes RDS et sauvegardes S3 chiffrées/versionnées.
- [ ] Utiliser des permissions IAM minimales.
- [ ] Prévoir une copie dans une autre région si nécessaire.
- [ ] Compléter `ansible/restaurer.yml`.
- [ ] Tester réellement une restauration et documenter le résultat.

## 17. Rejouer exactement l'évaluation

Documenter auparavant la création du backend, puis exécuter :

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply
ansible-galaxy install -r ansible/requirements.yml
ansible-inventory -i ansible/inventory.yml --graph
ansible-playbook -i ansible/inventory.yml ansible/site.yml --ask-vault-pass
ansible-playbook -i ansible/inventory.yml ansible/site.yml --ask-vault-pass
```

- [ ] Terraform crée au moins une EC2 et les ressources nécessaires.
- [ ] Galaxy installe toutes les dépendances.
- [ ] L'inventaire dynamique affiche les hôtes.
- [ ] PrestaShop est accessible.
- [ ] PrestaShop utilise la base de données.
- [ ] Le second playbook est idempotent.

## 18. Finaliser README et présentation

README :

- [ ] Expliquer objectif, périmètre et prérequis.
- [ ] Expliquer architecture, placement des composants et chemin d'une requête.
- [ ] Expliquer Terraform, Ansible, Galaxy, Vault et les environnements.
- [ ] Expliquer montée en charge, limites et panne d'une EC2.
- [ ] Documenter backend, déploiement, validation, destruction, sauvegarde et restauration.

Présentation :

- [ ] Présenter les choix d'architecture.
- [ ] Présenter la séparation Terraform/Ansible.
- [ ] Montrer l'inventaire dynamique.
- [ ] Montrer PrestaShop et la connexion à la base.
- [ ] Montrer le second lancement sans changement.
- [ ] Justifier sécurité, montée en charge, sauvegardes et gestion des pannes.

## Ordre global obligatoire

1. [ ] Préparer WSL2 et les versions.
2. [ ] Générer la clé SSH et protéger Git.
3. [ ] Créer le backend Terraform.
4. [ ] Décrire et valider le réseau.
5. [ ] Décrire EC2, RDS, ALB et Auto Scaling.
6. [ ] Ajouter Secrets Manager et IAM.
7. [ ] Ajouter `ansible_host` et `ansible_group`.
8. [ ] Initialiser et valider Terraform.
9. [ ] Installer Galaxy.
10. [ ] Configurer l'inventaire dynamique.
11. [ ] Créer Vault.
12. [ ] Écrire les rôles, templates et handlers.
13. [ ] Déployer PrestaShop et RDS.
14. [ ] Vérifier application, persistance et haute disponibilité.
15. [ ] Rejouer Ansible et obtenir `changed=0`.
16. [ ] Tester supervision, panne, sauvegarde et restauration.
17. [ ] Finaliser README, présentation et démonstration.
18. [ ] Refaire le déploiement depuis un dépôt propre.
