# Stack voix L40S : Gemma 4 26B + Parakeet + Qwen3 TTS

Pipeline conversation vocale sur **NVIDIA L40S (48 Go VRAM)** :

```
Micro → Parakeet TDT 0.6B (STT) → vLLM Gemma 4 26B-A4B → Qwen3 TTS → Audio
```

Interface **Parlor-style** (WebSocket, VAD, barge-in, clone vocal, saisie texte).

## Coûts AWS (g6e.xlarge, Frankfurt)

| État | Coût |
|------|------|
| **Running** | ~2,33 €/h GPU |
| **Stopped** | 0 €/h GPU — disque EBS ~15–20 €/mois |

> **Stop ≠ Terminate** : l’instance arrêtée conserve le disque (venv, modèles, config). Le NVMe éphémère (swap) est recréé au boot ; les modèles HF sont migrés sur EBS automatiquement avant l’arrêt.

## Démarrage rapide (depuis ton Mac)

```bash
git clone https://github.com/soupape34/l40s-voice-stack.git
cd l40s-voice-stack
cp deploy/aws.env.example deploy/aws.env   # déjà configuré pour l’instance test
chmod +x deploy/*.sh remote/*.sh *.sh

./deploy/status.sh    # état + IP
./deploy/up.sh        # start EC2 + sync + services (~3–5 min)
./deploy/tunnel.sh    # autre terminal → http://localhost:8080
```

## Arrêter (économiser le GPU)

```bash
./deploy/down.sh      # migre modèles HF → EBS + stop EC2
```

### Auto-stop idle (30 min)

Sans interaction WebSocket / texte / clone → l’instance **s’arrête seule** (persist modèles inclus).

- Grace **15 min** après boot (chargement vLLM)
- Config : `IDLE_MINUTES`, `IDLE_GRACE_MINUTES` dans `.env`
- Nécessite IAM : `cd terraform && terraform apply`

### GitHub Actions

| Workflow | Action |
|----------|--------|
| **EC2 Start** | Start + post-boot (manuel) |
| **EC2 Stop** | Persist + stop (manuel + cron 23h UTC) |

Setup secrets/variables : voir [terraform/README.md](terraform/README.md).

## Commandes deploy

| Script | Action |
|--------|--------|
| `./deploy/status.sh` | État instance, IP, coût |
| `./deploy/up.sh` | Start + sync code + post-boot + services |
| `./deploy/down.sh` | Persist modèles + stop EC2 |
| `./deploy/start.sh` | Start EC2 seulement |
| `./deploy/stop.sh` | Stop EC2 (avec confirmation) |
| `./deploy/sync.sh` | Push code sans toucher venv/modèles |
| `./deploy/tunnel.sh` | SSH `-L 8080:localhost:8080` |
| `./deploy/up.sh --running-only` | Redémarrer services si instance déjà up |

Config : `deploy/aws.env` (gitignored).

## Première installation (nouvelle machine)

Sur une L40S vierge :

```bash
huggingface-cli login
./install.sh
cp .env.example .env
./deploy/up.sh --no-sync   # ou start-all.sh sur la machine
```

## Architecture services (tmux `voice`)

| Fenêtre | Service | Port |
|---------|---------|------|
| vllm | Gemma 4 26B FP8 | 8000 |
| tts | Qwen3 CustomVoice + clone Base | 8002 |
| web | Parlor UI + WebSocket | 8080 |

```bash
ssh ubuntu@<IP> -i ~/.ssh/id_ed25519
tmux attach -t voice
```

## Modèles

| Rôle | Modèle |
|------|--------|
| LLM | `google/gemma-4-26B-A4B-it` |
| TTS défaut | `Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice` (Serena) |
| TTS clone | `Qwen/Qwen3-TTS-12Hz-0.6B-Base` |
| STT | `nvidia/parakeet-tdt-0.6b-v3` |

## VRAM (1× L40S 48 Go)

| Composant | VRAM |
|-----------|------|
| Gemma 26B FP8 | ~28–35 Go |
| Qwen3 TTS | ~2–4 Go |
| Parakeet | ~1 Go |

## Interface web

Tunnel obligatoire pour le micro (HTTPS/localhost) :

```bash
./deploy/tunnel.sh
open http://localhost:8080
```

- **Micro** : bouton pour couper l’écoute (pas la voix agent)
- **Clone vocal** : upload wav/m4a
- **Voix défaut** : retour Serena
- **Texte** : envoi sans micro

## Dépannage

- **OOM vLLM** : baisser `MAX_MODEL_LEN` ou `GPU_MEMORY_UTIL` dans `.env`
- **TTS transformers** : TTS utilise `.venv-tts` (transformers 4.57), vLLM `.venv` (5.x)
- **Après stop/start** : `./deploy/up.sh` recrée swap + tmux ; modèles sur EBS si `down.sh` a été utilisé
- **Parakeet webm/m4a** : `ffmpeg` requis
