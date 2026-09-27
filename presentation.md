# Taylor Shift's Ticket Shop

## 1. Objectif

Héberger la boutique PrestaShop et tenir la hausse de trafic à l'ouverture des
ventes. Terraform pour l'infrastructure, Ansible pour la configuration.

## 2. Architecture

```text
Mode floci (démo) :
  navigateur -> localhost:30080 (relais socat) -> EC2 : Nginx -> PrestaShop -> MariaDB (conteneur)

Mode aws (cible) :
  Internet -> ALB -> Auto Scaling Group (EC2 : PrestaShop) -> RDS MariaDB privé
```

- Terraform : VPC, subnets publics/privés, security groups, EC2, bucket S3 de
  sauvegarde durci (module). En mode aws en plus : ALB, Launch Template, ASG
  et sa politique de scaling, RDS, Secrets Manager, IAM, alarmes CloudWatch.
- Ansible : durcissement, pare-feu, Docker + PrestaShop + base, Nginx,
  sauvegardes. Inventaire généré depuis le state Terraform.

## 3. Choix techniques

- Base managée (RDS) en cible : partagée par toutes les instances, sauvegardes
  gérées. En démo Floci, MariaDB tourne en conteneur sur l'EC2.
- ALB + ASG : répartition, remplacement automatique, montée en charge par
  suivi de cible CPU (60 %), bornée par environnement (jusqu'à 4 instances en
  prod).
- State S3 avec verrou natif, un workspace par environnement.
- Secrets : Ansible Vault côté dépôt (base locale en floci), Secrets Manager
  côté infrastructure (RDS en aws), lu par les EC2 via leur rôle IAM.

## 4. Si une instance tombe

- aws : l'ALB la retire après 3 health checks ratés, l'ASG la remplace,
  l'alarme CloudWatch se déclenche.
- floci : une seule instance, le site est coupé jusqu'au redéploiement.

## 5. Démonstration

1. `terraform -chdir=terraform apply`
2. `ansible-inventory -i ansible/inventory.yml --graph`
3. Playbook deux fois : `changed=0` au second passage.
4. Ouvrir http://localhost:30080 (URL affichée à la fin du playbook).
5. Vérifier la base (commande du README §4).

## 6. Limites

- Floci ne permet pas de montrer ALB, ASG ni RDS : le mode aws n'a pas été
  déployé.
- Instances de l'ASG préparées par `user_data`, pas par Ansible.
- Fichiers PrestaShop locaux à chaque instance, RDS mono-AZ, pas de CDN.
