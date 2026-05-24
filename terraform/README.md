# Terraform — IAM pour idle auto-stop

Applique un **instance profile** sur l’EC2 existante pour que `idle-watchdog.sh` puisse appeler `ec2 stop-instances` sur elle-même.

## Prérequis

- Terraform ≥ 1.5
- AWS CLI configuré
- Instance existante (`i-0e278c6ee4963512e`)

## Usage

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Import si l’association existe déjà (rare) :

```bash
terraform import aws_iam_instance_profile_association.voice_ec2 i-0e278c6ee4963512e
```

## GitHub Actions — secrets & variables

Dans **Settings → Secrets and variables → Actions** :

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | Clé IAM (start/stop EC2) |
| `AWS_SECRET_ACCESS_KEY` | |
| `SSH_PRIVATE_KEY` | Clé privée SSH (`~/.ssh/id_ed25519`) pour post-boot |

| Variable | Valeur |
|----------|--------|
| `EC2_INSTANCE_ID` | `i-0e278c6ee4963512e` |
| `AWS_REGION` | `eu-central-1` |

Policy IAM minimale pour le user GitHub Actions :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:StartInstances",
        "ec2:StopInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ec2:ResourceTag/Name": "voice-stack-test"
        }
      }
    }
  ]
}
```

## Workflows

| Workflow | Déclencheur |
|----------|-------------|
| **EC2 Start** | Manuel → start + post-boot |
| **EC2 Stop** | Manuel + cron 23h UTC |

## Idle 30 min (sur l’instance)

Configuré par `remote/install-idle-watchdog.sh` (appelé depuis `post-boot.sh`) :

- **30 min** sans interaction WebSocket / clone / texte → stop auto
- **15 min** de grâce après boot (chargement vLLM)
- Vérification toutes les **5 min**

Variables (optionnel, dans `~/.env` sur l’instance) :

```
IDLE_MINUTES=30
IDLE_GRACE_MINUTES=15
IDLE_STOP_ENABLED=1
```

Désactiver : `IDLE_STOP_ENABLED=0` puis `systemctl --user restart voice-idle-watchdog.timer`
