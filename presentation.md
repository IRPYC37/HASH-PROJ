# Taylor Shift's Ticket Shop

## 1. Objectif

Déployer une boutique PrestaShop capable d'absorber une hausse de trafic lors
de l'ouverture des ventes, tout en séparant infrastructure et configuration.

## 2. Architecture

```text
Internet -> ALB public -> EC2 / Auto Scaling Group -> Docker + PrestaShop
																			|
																			-> RDS MariaDB privé
```

- Terraform crée le VPC, les subnets, les security groups, l'ALB, les EC2,
	l'ASG, RDS, les secrets, IAM, S3 et CloudWatch.
- Ansible installe Docker, déploie PrestaShop, configure Nginx, durcit SSH,
	installe Node Exporter et planifie les sauvegardes.
- L'inventaire Ansible est généré par les ressources `ansible_host` et
	`ansible_group` écrites dans le state Terraform.

## 3. Trafic et disponibilité

L'ALB exécute un health check sur chaque cible et ne transmet les requêtes
qu'aux instances saines. L'ASG remplace une instance défaillante et peut
augmenter le nombre d'instances jusqu'à trois. RDS est partagé par les EC2,
ce qui évite une base différente sur chaque serveur.

## 4. Sécurité

Les security groups séparent ALB, EC2 et RDS. RDS n'est pas public. Les secrets
sont placés dans Secrets Manager ou Vault, les outputs Terraform ne montrent
jamais de mot de passe, et l'IAM autorise seulement l'envoi des sauvegardes
vers S3.

## 5. Démonstration

1. Exécuter `terraform apply`.
2. Afficher `ansible-inventory --graph`.
3. Lancer le playbook Ansible deux fois et montrer `changed=0` au second passage.
4. Ouvrir l'endpoint `alb_endpoint`.
5. Vérifier la connexion RDS depuis PrestaShop.
6. Arrêter une instance et montrer son remplacement par l'ASG.

## 6. Limites

La solution est limitée par la taille RDS, trois instances maximum, le coût,
la région AWS et l'absence de CDN/cache. Le bootstrap de l'ASG assure le
démarrage Docker ; la configuration détaillée des instances de référence est
gérée par Ansible.
