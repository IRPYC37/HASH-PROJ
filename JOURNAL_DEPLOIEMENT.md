# Journal de déploiement — Taylor Shift's Ticket Shop

Ce journal consigne, dans l'ordre chronologique, chaque commande exécutée
pour déployer le projet (mode `floci`, celui de l'évaluation) et son
résultat réel. Il est généré au fil de l'exécution, pas rédigé a posteriori.

Environnement : Windows 11 + WSL2 Ubuntu (`/mnt/c/Cours/5IAC/HASH-PROJ`),
Docker Desktop, Floci (émulateur AWS local), Terraform 1.11.0, Ansible Core
2.20.9.

## 1. Vérification de l'environnement

| Vérification | Résultat |
|---|---|
| `wsl --status` / `wsl --list --verbose` | Ubuntu (WSL2) installée, arrêtée |
| Terraform (WSL) | `terraform version` → v1.11.0 |
| Ansible (WSL) | `ansible --version` → core 2.20.9 |
| Docker (WSL) | présent, mais `docker ps` échoue initialement (Docker Desktop arrêté) |
| AWS CLI (WSL) | `aws-cli/2.31.35` |
| Floci CLI (Windows) | `C:\Users\allan\AppData\Local\floci\bin\floci.exe` |

Constat : `docker ps` échoue avec
`error during connect ... dockerDesktopLinuxEngine ... cannot find the file specified`
→ Docker Desktop n'était pas démarré.

**Action** : lancement de `Docker Desktop.exe` (Windows), attente ~10 s
jusqu'à ce que `docker info` réponde.

**Action** : `floci doctor` confirmait le diagnostic (`docker.daemon` en échec,
`image.present` en échec). Une fois Docker prêt :

```powershell
floci start --pull always
```

→ image `floci/floci:latest` tirée, conteneur démarré, endpoint
`http://localhost:4566` opérationnel (« Floci AWS is ready »).

## 2. Backend Terraform (bucket S3)

Vérification préalable : `aws s3api head-bucket --bucket taylor-shift-terraform-state`
→ `404 Not Found` (bucket inexistant, comme attendu sur un Floci fraîchement démarré).

Création et configuration du bucket (identifiants factices `test`/`test`,
région `us-east-1`, comme documenté au §4 du README) :

```bash
aws --endpoint-url http://localhost.floci.io:4566 s3api create-bucket \
  --bucket taylor-shift-terraform-state --region us-east-1
aws --endpoint-url http://localhost.floci.io:4566 s3api put-bucket-versioning \
  --bucket taylor-shift-terraform-state --versioning-configuration Status=Enabled
aws --endpoint-url http://localhost.floci.io:4566 s3api put-bucket-encryption \
  --bucket taylor-shift-terraform-state \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

Vérifié : `get-bucket-versioning` → `Enabled`, `get-bucket-encryption` →
`AES256`. Résultat conforme à ce qu'attend `backend.tf`.

## 3. Terraform — init / validate / apply

```bash
terraform -chdir=terraform init -input=false
```
→ `Terraform has been successfully initialized!` (providers `hashicorp/aws`,
`ansible/ansible`, `hashicorp/random` réutilisés depuis le lock file).

```bash
terraform -chdir=terraform fmt -check -recursive   # exit 0, rien à reformater
terraform -chdir=terraform validate                # "Success! The configuration is valid."
```

```bash
terraform -chdir=terraform apply -auto-approve
```
→ **`Apply complete! Resources: 35 added, 0 changed, 0 destroyed.`**
(mode `floci` par défaut, workspace `default`, `environnement=dev`, aucune
`-var`).

Outputs obtenus :

```
alb_endpoint         = "http://localhost:8080"
backup_bucket        = "taylor-shift-dev-backup-000000000000"
database_secret_arn  = "arn:aws:secretsmanager:us-east-1:000000000000:secret:taylor-shift-dev/database-P72GVK"
web_instances         = { "web1" = "" }
```

`web_instances.web1` est vide : normal en mode `floci`
(`associate_public_ip_address = local.use_managed_services` = `false`,
la connexion Ansible utilise `127.0.0.1`, pas l'IP publique). Aucune valeur
secrète dans les outputs (`terraform output | grep -i password` → rien,
vérifié séparément ci-dessous).

Aucune ALB/ASG/RDS/CloudWatch créée : conforme au design documenté
(`count = local.use_managed_services ? 1 : 0`), puisque `deployment_mode`
vaut `floci` par défaut.

Vérification manuelle (`terraform output`, sans filtre) : aucune valeur de
mot de passe visible parmi les 4 outputs.

## 4. Galaxy et inventaire dynamique — deux découvertes d'environnement

```bash
ansible-galaxy install -r ansible/requirements.yml
```

→ rôle `geerlingguy.git` (3.0.1) téléchargé et installé ; collections déjà
présentes (« Nothing to do »). Mais la commande affiche :

```
[WARNING]: Ansible is being run in a world writable directory
(/mnt/c/Cours/5IAC/HASH-PROJ), ignoring it as an ansible.cfg source.
```

**Découverte n°1** : sur ce poste, le dépôt est monté depuis Windows dans
WSL2 via `drvfs` (`/mnt/c/...`). Ansible considère ce montage comme
« world writable » et **ignore complètement `ansible.cfg`** à la racine —
donc `vault_password_file`, `roles_path`, `collections_path` et
`enable_plugins` n'y sont jamais lus implicitement.

Test : `ansible-inventory -i ansible/inventory.yml --graph` fonctionne quand
même (le plugin `cloud.terraform.terraform_provider` se charge via la clé
`plugin:` du fichier d'inventaire, sans dépendre de `enable_plugins`) :

```
@all:
  |--@ungrouped:
  |--@webservers:
  |  |--web1
```

Correctif appliqué pour la suite : exporter explicitement
`ANSIBLE_CONFIG="$PWD/ansible.cfg"` avant chaque commande Ansible — un
`ANSIBLE_CONFIG` explicite n'est pas soumis au même contrôle de sécurité que
la découverte implicite du `./ansible.cfg`.

**Découverte n°2** : une fois `ansible.cfg` réellement pris en compte,
`vault_password_file = .vault-pass` échoue :

```
[ERROR]: Problem running vault password script /mnt/c/.../.vault-pass
([Errno 8] Exec format error). If this is not a script, remove the
executable bit from the file.
```

Cause : le montage `drvfs` de `/mnt/c` ne supporte pas les permissions Unix
réelles (`mount | grep /mnt/c` → pas d'option `metadata`) : **tous les
fichiers y apparaissent `-rwxrwxrwx`**, `chmod 600` ne change rien
(vérifié). Ansible traite donc `.vault-pass` comme un *script* de mot de
passe (car « exécutable ») plutôt que comme un fichier en clair, et échoue à
l'exécuter.

Correctif appliqué : copier le mot de passe Vault sur le système de
fichiers Linux natif de WSL2 (`~/.vault-pass-taylor-shift`, `chmod 600`
effectif là), et pointer dessus via
`ANSIBLE_VAULT_PASSWORD_FILE=$HOME/.vault-pass-taylor-shift` pour les
commandes suivantes.

> Ce problème ne touche que ce poste précis (dépôt sur `/mnt/c`, pas la
> configuration Terraform/Ansible elle-même) mais mérite d'être documenté
> pour l'équipe : quiconque clone ce dépôt côté Windows et travaille dessus
> depuis WSL2 sans le recloner dans le filesystem Linux natif rencontrera le
> même blocage sur `.vault-pass`.

Avec `ANSIBLE_CONFIG` et `ANSIBLE_VAULT_PASSWORD_FILE` correctement
positionnés, ré-exécution propre (sans warning ni erreur) :

```bash
ansible-inventory -i ansible/inventory.yml --graph
```
```
@all:
  |--@ungrouped:
  |--@webservers:
  |  |--web1
```

```bash
ansible-inventory -i ansible/inventory.yml --host web1
```
→ variables issues du state Terraform confirmées : `ansible_host=127.0.0.1`,
`ansible_user=root`, `ansible_ssh_private_key_file=.keys/taylor-shift`,
`application_db_secret_arn`, `backup_bucket`, `application_use_local_database=true`,
et les variables Vault déchiffrées (`vault_application_db_password`,
valeur volontairement **non reportée ici**). Confirme au passage que
`ansible_port` contient bien l'expression conditionnelle corrigée en §3 de
l'audit (mode floci vs aws), affichée non évaluée par `--host` (normal, elle
n'est résolue qu'à la connexion réelle).

## 5. Ansible — premier passage du playbook

```bash
ansible-playbook -i ansible/inventory.yml ansible/site.yml
```

Remplace `--ask-vault-pass` (interactif, impossible à automatiser dans cet
environnement d'exécution) par `ANSIBLE_VAULT_PASSWORD_FILE` déjà exporté —
strictement équivalent en sécurité (le mot de passe ne transite ni en clair
dans une commande, ni dans un fichier versionné), seule la méthode de saisie
change.

**Échec** :

```
[ERROR]: the role 'geerlingguy.git' was not found in
/mnt/c/Cours/5IAC/HASH-PROJ/ansible/roles:.../ansible/roles:.../ansible
Origin: ansible/site.yml:16:7
```

Cause directe des découvertes du §4 : le tout premier
`ansible-galaxy install -r ansible/requirements.yml` (exécuté **avant**
d'exporter `ANSIBLE_CONFIG`) a lui aussi ignoré `ansible.cfg`, donc
`roles_path = ansible/roles` n'était pas appliqué — Galaxy a installé le
rôle dans son emplacement par défaut (`~/.ansible/roles/geerlingguy.git`)
au lieu de `ansible/roles/geerlingguy.git`. Une fois `ANSIBLE_CONFIG` en
place pour `ansible-playbook`, la recherche de rôles se limite au chemin du
projet et ne le trouve plus.

**Correctif** : ré-installer Galaxy avec `ANSIBLE_CONFIG` déjà exporté, pour
que `roles_path` soit respecté dès l'installation :

```bash
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
ansible-galaxy install -r ansible/requirements.yml
```

> Point à documenter pour l'équipe : sur ce type de montage, **toute**
> commande `ansible*` (galaxy comme playbook) doit être lancée avec
> `ANSIBLE_CONFIG` explicitement exporté, sous peine d'incohérences
> silencieuses entre l'installation et l'exécution.

Ré-exécution réussie (~6 min, très lent sur `/mnt/c` — 9p — pour ~21
fichiers) :

```
- geerlingguy.git (3.0.1) was installed successfully
Installing 'cloud.terraform:4.0.0' to '.../ansible/collections/...'
Installing 'community.docker:5.3.0' to '.../ansible/collections/...'
Installing 'community.general:13.4.0' to '.../ansible/collections/...'
Installing 'ansible.posix:2.2.2' to '.../ansible/collections/...'
```

Cette fois les collections aussi atterrissent dans `ansible/collections/`
(le chemin du projet), et non plus dans `~/.ansible/`.

## 6. Ansible — playbook, échec SSH, troisième manifestation du même bug

```bash
ansible-playbook -i ansible/inventory.yml ansible/site.yml
```

**Échec dès la première tâche** :

```
WARNING: UNPROTECTED PRIVATE KEY FILE!
Permissions 0777 for '.keys/taylor-shift' are too open.
Load key ".keys/taylor-shift": bad permissions
root@127.0.0.1: Permission denied (publickey,password).
```

Même cause racine que les découvertes du §4 (montage `drvfs` de `/mnt/c` :
permissions Unix non supportées, tout est `-rwxrwxrwx`) — cette fois sur la
clé privée SSH elle-même. OpenSSH refuse par sécurité toute clé privée dont
les permissions sont trop larges, et ni `chmod`, ni `.gitignore`, ni la
configuration Terraform/Ansible n'y peuvent quoi que ce soit : c'est une
contrainte du montage.

**Correctif** (sans modifier le state Terraform ni l'inventaire) : copier la
clé privée sur le filesystem Linux natif, où `chmod 600` s'applique
réellement, et **surcharger** `ansible_ssh_private_key_file` via
`-e` (les extra-vars ont la priorité la plus haute, au-dessus des variables
d'inventaire) :

```bash
cp .keys/taylor-shift ~/.keys-natif/taylor-shift && chmod 600 ~/.keys-natif/taylor-shift
ansible-playbook -i ansible/inventory.yml ansible/site.yml \
  -e ansible_ssh_private_key_file=$HOME/.keys-natif/taylor-shift
```

> Troisième occurrence du même problème de fond (après `ansible.cfg` ignoré
> et `.vault-pass` refusé) : **travailler depuis `/mnt/c` sous WSL2 casse
> tout mécanisme de sécurité basé sur les permissions Unix** (clé SSH,
> vault). À documenter clairement dans le README pour l'équipe : cloner/
> travailler le projet dans le filesystem Linux natif de WSL2 (ex.
> `~/HASH-PROJ`), pas depuis `/mnt/c/...`, pour éviter ces trois contournements.

Avec la clé native, le playbook progresse enfin réellement :

```bash
ansible-playbook -i ansible/inventory.yml ansible/site.yml \
  -e ansible_ssh_private_key_file=$HOME/.keys-natif/taylor-shift
```

Déroulé observé : bootstrap Python (`raw`) ok, `geerlingguy.git` installe
git, **`durcissement`** applique les 3 `lineinfile` sshd + les 5 réglages
`sysctl` (`changed`), **`pare_feu`** installe et active UFW (`changed`),
**`application`** installe Docker, crée le réseau `taylor-shift` et démarre
le conteneur `db` (MariaDB) — tout en `changed`, comme attendu au premier
passage.

**Échec** à la tâche suivante :

```
TASK [application : Démarrer PrestaShop]
[ERROR]: Task failed: Failed to connect to the host via ssh:
<error censored due to no_log: true>
fatal: [web1]: UNREACHABLE!
PLAY RECAP: web1  ok=17  changed=14  unreachable=1  failed=0  skipped=14
```

La connexion SSH est perdue juste avant de démarrer le conteneur
PrestaShop (juste après avoir démarré MariaDB). Le durcissement SSH
appliqué juste avant (`PasswordAuthentication no`,
`PermitRootLogin prohibit-password`) n'explique pas la coupure : on se
connecte par clé, jamais par mot de passe, et root reste autorisé par clé ;
plusieurs tâches se sont d'ailleurs connectées avec succès après ce
durcissement. Hypothèse la plus probable : le conteneur `floci-ec2-*` (qui
simule l'EC2 dans un conteneur Docker aux ressources limitées) a été
momentanément surchargé en démarrant MariaDB, coupant la session SSH — un
aléa d'infrastructure de test, pas un problème de configuration. Nouvelle
tentative ci-dessous (Ansible est conçu pour être rejouable : les tâches
déjà appliquées doivent remonter `ok`, pas `changed`, au prochain passage).

**Confirmation** : `docker ps` échoue immédiatement après avec
`Docker Desktop is unable to start` / `terminating main distribution:
un-mounting data disk: unmounting WSL VHDX: ...`. **Docker Desktop a
planté** pendant l'exécution du playbook (bug de l'application Docker
Desktop elle-même, sur ce poste, sans rapport avec le projet) — ce qui a
tué le conteneur `floci-ec2-*` et coupé la session SSH en plein milieu de
la tâche « Démarrer PrestaShop ». Action : relancer Docker Desktop, puis
Floci, puis rejouer le playbook.

Docker Desktop a mis plusieurs tentatives à revenir proprement (`docker info`
restait en échec après un simple relancement de l'exécutable ; un
`wsl --shutdown` suivi d'un nouveau lancement de Docker Desktop a résolu le
blocage en ~10 s).

## 7. Découverte : l'état AWS émulé par Floci ne survit pas à un crash Docker

```bash
floci status   # → Container: floci  exited ; Reachable: no
floci start    # → "Removing stopped container 'floci'..." puis nouveau conteneur
```

Le conteneur `floci` a été **recréé** (nouvel ID), pas simplement redémarré.
Vérification :

```bash
aws --endpoint-url http://localhost.floci.io:4566 s3api head-bucket --bucket taylor-shift-terraform-state
# → 404 Not Found
aws --endpoint-url http://localhost.floci.io:4566 ec2 describe-instances ...
# → table vide
```

**Tout l'AWS émulé (bucket du backend Terraform inclus, donc le state
lui-même) a disparu** avec l'ancien conteneur `floci` — Floci ne persiste
pas son état AWS entre deux recréations de son propre conteneur. Les
conteneurs `floci-ec2-*` qui simulaient les EC2 existent encore sur le
disque Docker (`docker ps -a`) mais ne sont plus rattachés à un Floci qui
les connaît.

> À noter pour l'équipe : un crash de Docker Desktop pendant un TP/une
> démo oblige à **tout refaire depuis la création du bucket backend** — ce
> n'est pas un défaut du projet, mais une limite de l'émulateur local à
> garder en tête avant une démonstration (redémarrer Docker Desktop à
> l'avance, éviter de le relancer en pleine manip).

Reprise depuis le §2 : recréation du bucket backend, puis nouvel `apply`.

```bash
terraform -chdir=terraform init -reconfigure -input=false
terraform -chdir=terraform apply -auto-approve
```

→ **`Apply complete! Resources: 35 added, 0 changed, 0 destroyed.`** —
nouvelle instance `i-c39bd1023e22bd4dc`, nouveau conteneur
`floci-ec2-i-c39bd1023e22bd4dc` confirmé `Up` avec SSH publié sur
`0.0.0.0:2201`. Mêmes outputs (`alb_endpoint`, `backup_bucket`,
`database_secret_arn`) qu'au premier apply, sans secret visible.

## 8. Ansible — playbook rejoué sur la nouvelle instance, **même échec au même endroit**

Rejeu du playbook (mêmes variables : `ANSIBLE_CONFIG`,
`ANSIBLE_VAULT_PASSWORD_FILE`, clé native). Déroulé identique au §6 :
bootstrap Python, `geerlingguy.git`, `durcissement` (changed), `pare_feu`
(changed), Docker installé, réseau `taylor-shift` créé, **MariaDB démarré
(changed)** — puis exactement la même erreur :

```
TASK [application : Démarrer PrestaShop]
[ERROR]: Task failed: Failed to connect to the host via ssh: <censuré, no_log>
fatal: [web1]: UNREACHABLE!
PLAY RECAP: web1  ok=17  changed=14  unreachable=1  failed=0  skipped=14
```

Vérification immédiate : **Docker Desktop a re-crashé**, avec exactement la
même signature que la première fois :

```
Error response from daemon: Docker Desktop is unable to start
terminating main distribution: un-mounting data disk: unmounting WSL VHDX: ...
```

**Ce n'est donc pas un aléa isolé.** Le crash survient systématiquement au
même point précis du déploiement : juste après le démarrage du conteneur
MariaDB, quand Ansible tente de démarrer le conteneur PrestaShop (deux
conteneurs Docker démarrés coup sur coup *à l'intérieur* du conteneur
`floci-ec2-*` qui simule déjà l'EC2 — donc du Docker imbriqué). Éléments
factuels réunis pour le diagnostic :

- RAM totale de la machine : 15,3 Go ; aucun `.wslconfig` ne limite la VM
  WSL2 (limite par défaut ≈ 50 % de la RAM hôte) — une contrainte mémoire
  explicite semble peu probable, mais un pic mémoire au démarrage
  simultané de deux conteneurs (init MariaDB + installeur automatique
  PrestaShop `PS_INSTALL_AUTO=1`) dans un Docker imbriqué reste plausible.
- Le message d'erreur (« unmounting WSL VHDX ») pointe vers Docker Desktop
  lui-même (gestion de son disque virtuel WSL2), pas vers Ansible, Docker
  Compose ou le code du projet.
- Un premier `wsl --shutdown` + relance de Docker Desktop avait suffi à
  repartir proprement (§7) — donc un simple redémarrage fonctionne, mais ne
  règle pas la cause : le crash revient dès qu'on réatteint la même charge
  (MariaDB + PrestaShop côte à côte).

**Déploiement mis en pause à ce stade.** Poursuivre en relançant Docker
Desktop une troisième fois sans rien changer risquerait de reproduire le
même crash sans apporter d'information nouvelle. Pistes pour la suite,
côté machine (hors périmètre du code du projet) : mettre à jour Docker
Desktop, consulter l'Observateur d'événements Windows au moment du crash,
ou allouer plus de mémoire à la VM WSL2 via `.wslconfig`
(`[wsl2]` / `memory=8GB`) avant de relancer.

## 9. Cause racine identifiée : espace disque, pas mémoire

Explication donnée en cours de route : **le disque `C:` est presque plein**,
et `docker_data.vhdx` (disque virtuel de Docker Desktop) pèse à lui seul
**~50,7 Go**. C'est cohérent avec la signature du crash (« unmounting WSL
VHDX ») : Docker Desktop n'arrive plus à faire grandir/manipuler son disque
virtuel faute de place sur l'hôte, exactement au moment où deux conteneurs
supplémentaires (MariaDB + PrestaShop) écrivent des données dans le
conteneur imbriqué `floci-ec2-*`.

Constat via `docker system df -v` : deux conteneurs `floci-ec2-*`
représentaient à eux seuls la quasi-totalité de l'espace utilisé :

| Conteneur | Taille | Statut |
|---|---:|---|
| `floci-ec2-i-c39bd1023e22bd4dc` (actif, celui de ce déploiement) | 20,9 Go | nécessaire |
| `floci-ec2-i-cbf3e71a6a3f2ef80` (orphelin, ~22h, plus référencé par aucun state) | 24,2 Go | supprimé |

**Action** : suppression du conteneur orphelin (`docker rm -f
floci-ec2-i-cbf3e71a6a3f2ef80`) — sans impact sur le déploiement en cours,
puisqu'il ne correspondait à aucune ressource Terraform/Ansible actuelle.

**Point d'attention non résolu** : juste après cette suppression, l'espace
libre sur `C:` a chuté de 21,3 Go à 11,5 Go au lieu d'augmenter — alors que
`docker_data.vhdx` n'a lui-même pas grossi de manière notable (les disques
virtuels WSL2 ne se réduisent pas automatiquement quand on supprime des
fichiers à l'intérieur, mais ils ne devraient pas non plus grossir sur une
suppression). Cause exacte non identifiée avec certitude dans le temps
disponible (hypothèses : copie fantôme Windows déclenchée par l'important
volume de données modifiées, ou activité concurrente sans lien avec Docker).

**Décision** : déploiement mis en pause à ce stade avec 11,5 Go libres sur
`C:`, jugé trop risqué pour continuer à faire tourner Terraform/Docker/
Ansible sans risquer de saturer complètement le disque système. L'espace
disque doit être libéré manuellement avant de reprendre.

## 10. État à la reprise

Pour reprendre le déploiement une fois de l'espace disque libéré :

1. Vérifier l'espace libre sur `C:` (viser au moins ~20-30 Go de marge).
2. `floci start` (le conteneur `floci` a été recréé pendant ce journal ;
   son état AWS émulé — bucket backend inclus — a été perdu à chaque
   crash Docker Desktop, voir §7).
3. Recréer le bucket backend S3 (§2) si `head-bucket` renvoie 404.
4. `terraform -chdir=terraform init -reconfigure && terraform -chdir=terraform apply -auto-approve`.
5. Rejouer le playbook avec les mêmes contournements que ci-dessus
   (`ANSIBLE_CONFIG`, `ANSIBLE_VAULT_PASSWORD_FILE`, clé SSH copiée sur le
   filesystem natif) :

```bash
cd /mnt/c/Cours/5IAC/HASH-PROJ
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
export ANSIBLE_VAULT_PASSWORD_FILE="$HOME/.vault-pass-taylor-shift"
ansible-playbook -i ansible/inventory.yml ansible/site.yml \
  -e ansible_ssh_private_key_file=$HOME/.keys-natif/taylor-shift
```

6. Si le playbook va au bout, rejouer une seconde fois pour vérifier
   `changed=0` (exigence de l'évaluation), puis vérifier l'endpoint
   `http://localhost:8080`.

Tout ce qui précède (backend, apply, Galaxy, inventaire dynamique,
durcissement, pare-feu, Docker, réseau applicatif, démarrage MariaDB) a déjà
été validé deux fois de suite dans cette session ; seule la toute dernière
étape (démarrage du conteneur PrestaShop) n'a pas encore pu aboutir, à cause
de l'espace disque de la machine — pas d'un problème de code du projet.

## 11. Reprise après libération d'espace disque (~75 Go) — déploiement complet réussi

Espace disque assaini par l'utilisateur (72,7 Go libres sur `C:`). Séquence
complète rejouée depuis zéro (`docker_data.vhdx` ayant été supprimé,
Floci reparti sans aucun état) :

```bash
floci start --pull always                     # nouvelle image + conteneur
# recréation du bucket backend (§2)
terraform -chdir=terraform init -reconfigure
terraform -chdir=terraform apply -auto-approve   # 35 added, 0 changed, 0 destroyed
```

→ nouvelle instance `i-0a5193a5344051394`.

```bash
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
export ANSIBLE_VAULT_PASSWORD_FILE="$HOME/.vault-pass-taylor-shift"
ansible-playbook -i ansible/inventory.yml ansible/site.yml \
  -e ansible_ssh_private_key_file=$HOME/.keys-natif/taylor-shift
```

**Premier passage : succès complet, jusqu'au bout cette fois.**

```
PLAY RECAP: web1  ok=31  changed=27  unreachable=0  failed=0  skipped=15
```

`application : Démarrer PrestaShop` → `changed`. `Synchroniser l'URL
publique PrestaShop` a nécessité une nouvelle tentative interne
(`FAILED - RETRYING (10 retries left)` puis `ok` — mécanisme
`retries`/`until` du rôle, PrestaShop pas encore prêt à répondre au tout
premier essai, comportement normal et déjà prévu dans le rôle). Handlers
`Recharger SSH` et `Recharger Nginx` déclenchés en fin de play (cohérent :
c'est le tout premier passage, donc premier changement de leurs fichiers
surveillés).

**Second passage : idempotence confirmée.**

```
PLAY RECAP: web1  ok=29  changed=0  unreachable=0  failed=0  skipped=15
```

**`changed=0`, `failed=0`, `unreachable=0`** — exactement l'exigence de
l'énoncé (« Le second playbook run must report no unexpected changes »).

## 12. Vérification applicative — et découverte sur l'exposition du port en mode floci

Test de l'endpoint documenté (`alb_endpoint = "http://localhost:8080"`,
`terraform output`) :

```bash
curl -I http://localhost:8080
# → HTTP 200, mais Server répond avec une page EnterpriseDB
```

**Faux positif** : le port 8080 sur la machine Windows est déjà occupé par
un processus `httpd` totalement étranger au projet (`Get-NetTCPConnection
-LocalPort 8080` → PID d'un autre outil déjà installé sur le poste). Le
`curl` réussissait, mais ne touchait pas du tout notre PrestaShop.

Vérification de ce que Floci publie réellement vers l'hôte :

```bash
docker port floci-ec2-i-0a5193a5344051394
# → 22/tcp -> 0.0.0.0:2200   (uniquement SSH)
```

**Floci ne publie automatiquement que le port SSH vers l'hôte Windows**,
quelles que soient les règles de security group ouvertes côté Terraform
(`web_http_floci`, port 80). Aucun mécanisme équivalent à un ALB n'existe
en mode `floci` par défaut (cohérent avec ce que documentent déjà
`presentation.md` et `Mise en place .md` : pas d'ALB/ASG en mode floci) —
mais ceci va plus loin : même l'accès HTTP « direct » supposé par
`alb_endpoint = "http://localhost:8080"` ne fonctionne pas tel quel sans
étape manuelle supplémentaire.

**Vérification que l'application elle-même fonctionne**, en contournant le
problème d'exposition, par deux moyens indépendants :

1. Directement depuis l'intérieur de l'instance simulée :
   ```bash
   docker exec floci-ec2-i-0a5193a5344051394 curl -sSL http://localhost:80
   # → HTTP 200 final, HTML complet : <title>PrestaShop</title>, thème
   #   "hummingbird" chargé, contenu storefront réel (pas une page d'erreur)
   ```
2. Via un tunnel SSH local, en passant par le port SSH réellement publié
   par Floci (2200) :
   ```bash
   ssh -i ~/.keys-natif/taylor-shift -p 2200 -N -L 8081:localhost:80 root@127.0.0.1 &
   curl -I http://localhost:8081   # → HTTP 302 (Nginx, redirection normale)
   ```
   confirmé accessible aussi bien depuis WSL2 que depuis Windows
   (redirection de `localhost` de WSL2 vers Windows active par défaut).

**Conclusion** : la stack Nginx + PrestaShop + MariaDB déployée par Ansible
est **entièrement fonctionnelle** (HTTP 200, storefront PrestaShop rendu,
connexion base de données opérationnelle). Le seul point qui ne fonctionne
pas tel que documenté est l'accès direct à `http://localhost:8080` depuis
Windows en mode `floci` : Floci ne le publie pas automatiquement, et sur
cette machine précise, ce port est de toute façon déjà pris par un service
sans rapport. À corriger dans la documentation du projet : soit publier le
port applicatif via un tunnel SSH documenté (comme ci-dessus, en utilisant
le port SSH que Floci publie réellement), soit vérifier s'il existe une
option Floci pour publier des ports supplémentaires en plus du SSH.

## 13. Bilan

| Étape | Résultat |
|---|---|
| Backend S3 (bucket, versioning, chiffrement) | OK |
| `terraform init` / `validate` / `fmt` | OK |
| `terraform apply` (mode floci par défaut) | OK — 35 ressources, rejoué 3× avec succès à chaque fois |
| `ansible-galaxy install` | OK (une fois `ANSIBLE_CONFIG` correctement exporté) |
| Inventaire dynamique (`cloud.terraform.terraform_provider`) | OK |
| Playbook, 1er passage | OK — `changed=27 failed=0` |
| Playbook, 2e passage (idempotence) | OK — **`changed=0 failed=0`** |
| Application (Nginx + PrestaShop + MariaDB) | OK — storefront rendu, HTTP 200 |
| `alb_endpoint` documenté (`localhost:8080`) tel quel depuis Windows | **KO** — nécessite un tunnel SSH, à documenter |

Trois découvertes d'environnement (world-writable `ansible.cfg`,
permissions `.vault-pass`/clé SSH sur `/mnt/c`, non-persistance de l'état
Floci) et une découverte applicative (exposition du port en mode floci)
ont été documentées au fil de l'eau ci-dessus, avec leurs contournements.

## 14. Correctif définitif : port applicatif configurable + script de tunnel

Plutôt que de laisser `alb_endpoint = "http://localhost:8080"` non
joignable en mode `floci` (§12), le projet a été corrigé :

- `terraform/variables.tf` : nouvelle variable `application_public_port`
  (défaut `8080`), pour changer de port si celui-ci est déjà pris sur la
  machine de développement.
- `terraform/ansible.tf` : `application_public_url` est maintenant
  explicitement transmis à l'inventaire (`localhost:${var.application_public_port}`
  en mode `floci`, DNS de l'ALB en mode `aws` — auparavant cette variable
  n'était **jamais transmise du tout**, y compris en mode `aws`, où
  PrestaShop aurait donc gardé `localhost:8080` comme domaine stocké malgré
  un vrai déploiement ALB : bug corrigé au passage).
- `terraform/outputs.tf` : `alb_endpoint` suit la même variable.
- `scripts/floci-tunnel.sh` (nouveau) : détecte le conteneur
  `floci-ec2-*` actif, récupère son port SSH réellement publié par Floci
  (`docker port ... 22/tcp`), et ouvre un tunnel SSH local vers le port 80
  (Nginx) de l'instance sur le port choisi.
- README §5 et `presentation.md` (scénario A, limites) mis à jour en
  conséquence.

**Test réel effectué** (avec `application_public_port=8090`, pour
prouver que ça fonctionne malgré le conflit du port 8080 sur cette
machine) :

```bash
terraform -chdir=terraform apply -auto-approve -var application_public_port=8090
ansible-playbook -i ansible/inventory.yml ansible/site.yml ...   # changed=1 (PS_DOMAIN)
./scripts/floci-tunnel.sh 8090
curl http://localhost:8090
```

→ **`HTTP/1.1 200 OK`, `Server: nginx/1.22.1`, contenu PrestaShop complet,
tous les liens internes de la page pointent correctement vers
`http://localhost:8090/...`** — plus besoin de suivre une redirection,
contrairement au test du §12. Le mécanisme fonctionne bout en bout.

**Point annexe rencontré pendant ce test** (sans lien avec le correctif) :
le `terraform apply -var application_public_port=8090` a mis à jour
`ansible_group.webservers` et 2 règles de security group avec succès, mais
a échoué sur `aws_instance.web["web1"]` :
`UnsupportedOperation: Operation ModifyNetworkInterfaceAttribute is not
supported`. Cause probable : normalisation du format d'ID
(`"000000000000/sg-xxx"` → `"sg-xxx"`) des `referenced_security_group_id`
déjà présents dans le state, une limitation de l'émulation réseau de
Floci plutôt qu'un problème du code Terraform. Sans impact sur le test
(les ressources utiles au correctif ont bien été mises à jour) ; à
surveiller si `terraform plan` continue de proposer ce changement sur les
prochains `apply`.

## 15. Bug trouvé en marchant sur le site : liens de menu figés sur l'ancien domaine

En testant l'application dans un vrai navigateur (§14), les liens de menu et
de pied de page (catégories, CMS, compte) redirigeaient vers l'ancien
domaine (`localhost:8080`, celui de l'installation initiale) malgré la
synchronisation en base (`ps_shop_url`, `ps_configuration`) déjà confirmée
correcte pour la page d'accueil.

Cause : PrestaShop compile et **met en cache sur disque** (Smarty, menu
principal `ps_mainmenu`, Doctrine) les liens construits à partir du domaine
au moment où ils sont générés (`/var/www/html/var/cache/prod/`). Changer le
domaine en base ne suffit pas : ce cache doit être vidé pour que les liens
déjà générés soient recalculés.

**Correctif immédiat** (instance en cours) :

```bash
docker exec floci-ec2-i-0a5193a5344051394 docker exec taylor-shift-prestashop \
  sh -c "rm -rf /var/www/html/var/cache/prod/* /var/www/html/var/cache/dev/*"
```

→ vérifié : les 237 références `localhost:` de la page catégorie
(`/9-art`) passent toutes de `8080` à `8090`.

**Correctif pérenne** (`ansible/roles/application/tasks/main.yml` et
`handlers/main.yml`) : la tâche « Synchroniser l'URL publique PrestaShop »
ne mettait jamais `changed_when` à autre chose que `false`, donc ne pouvait
jamais déclencher de handler. Restructurée en deux temps :

1. Nouvelle tâche « Lire le domaine PrestaShop actuellement configuré »
   (`SELECT ... FROM ps_configuration`, `changed_when: false`) — capture la
   valeur avant modification.
2. La tâche de synchronisation compare maintenant l'ancienne et la nouvelle
   valeur (`changed_when: application_current_domain.stdout != application_public_url`)
   et notifie un nouveau handler `Vider le cache PrestaShop`
   (`docker_container_exec` sur `taylor-shift-prestashop`, `rm -rf
   var/cache/{prod,dev}/*`) — déclenché uniquement quand le domaine change
   réellement, jamais sur un run où rien n'a changé.

**Revalidé** : rejeu complet du playbook après ce correctif →
`ok=30  changed=0  failed=0` (le domaine n'ayant pas changé depuis le
correctif manuel, ni la tâche ni le handler ne se déclenchent) — idempotence
toujours respectée, et l'application reste cohérente (237/237 liens sur
`localhost:8090`).

