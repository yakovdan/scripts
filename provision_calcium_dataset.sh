#!/usr/bin/env bash
# Vast.ai provisioning script.
# Logs everything to /workspace/provision.log, retries flaky network steps,
# and is safe to re-run (idempotent).

# --- logging / tracing -------------------------------------------------------
mkdir -p /workspace
exec > >(tee -a /workspace/provision.log) 2>&1
set -x
set -uo pipefail        # note: NOT -e, so a single failure won't silently abort
echo "=== provisioning started $(date -u) ==="

# --- activate runtime env ----------------------------------------------------
# Provisioning runs non-interactively, so ~/.bashrc (which puts the conda env on
# PATH) is never sourced. Prepend the env's bin so pip/python/wandb all resolve
# to /venv/main instead of base, matching the interactive shell.
VENV=/venv/main
if [ -x "$VENV/bin/python" ]; then
  export PATH="$VENV/bin:$PATH"
  echo "using $($VENV/bin/python -c 'import sys; print(sys.executable)')"
else
  echo "FATAL: expected env at $VENV not found"; exit 1
fi

# --- helpers -----------------------------------------------------------------
retry() {
  local n=0 max=5 delay=5
  until "$@"; do
    n=$((n + 1))
    if [ "$n" -ge "$max" ]; then
      echo "FATAL: command failed after $max attempts: $*"
      return 1
    fi
    echo "retry $n/$max in ${delay}s: $*"
    sleep "$delay"
  done
}

require_env() {
  local missing=0 v
  for v in "$@"; do
    if [ -z "${!v:-}" ]; then
      echo "FATAL: required env var '$v' is not set"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || exit 1
}

# --- sanity: confirm required env vars are present in the onstart context -----
echo "--- environment ---"
env | sort
require_env DATA_DIR OUTPUT_DIR GH_PAT GH_USER WANDB_KEY B2_KEY_ID B2_APP_KEY DATASET_KEY DATASET_ZIP

# --- directories -------------------------------------------------------------
mkdir -p /workspace/repos
mkdir -p "$DATA_DIR"
mkdir -p "$OUTPUT_DIR"

# --- clone Calcium -----------------------------------------------------------
cd /workspace/repos
if [ -d Calcium/.git ]; then
  echo "Calcium already cloned, fetching"
  retry git -C Calcium fetch --all --prune
else
  retry git clone "https://${GH_PAT}@github.com/$GH_USER/Calcium.git"
fi
git -C Calcium checkout origin/dev_TrainingGeneralizedDiceRandCrop

# --- clone & install planned-rand-crop ---------------------------------------
cd /workspace/repos
if [ -d planned-rand-crop/.git ]; then
  echo "planned-rand-crop already cloned, fetching"
  retry git -C planned-rand-crop fetch --all --prune
else
  retry git clone "https://${GH_PAT}@github.com/$GH_USER/planned-rand-crop.git"
fi
retry pip install --no-deps /workspace/repos/planned-rand-crop

# --- python deps -------------------------------------------------------------
retry pip install lightning numpy matplotlib scipy pydicom nibabel tqdm einops boto3 botocore wandb tensorboard dotenv
retry pip install monai-weekly

# --- wandb -------------------------------------------------------------------
retry wandb login "$WANDB_KEY"

# --- backblaze b2 cli --------------------------------------------------------
cd /
if [ ! -x /b2-linux ]; then
  retry wget -O /b2-linux https://github.com/Backblaze/B2_Command_Line_Tool/releases/latest/download/b2-linux
  chmod +x /b2-linux
fi
retry /b2-linux account authorize "$B2_KEY_ID" "$B2_APP_KEY"

# --- download & unpack datasets ----------------------------------------------
# Two datasets, each unzipped into its own subdir under $DATA_DIR:
#   - env-driven dataset (DATASET_KEY / DATASET_ZIP)      -> $DATA_DIR/stanford
#   - fixed calcium_alldoses.zip from the bucket root     -> $DATA_DIR/local_calcium
STANFORD_DIR="$DATA_DIR/stanford"
CALCIUM_DIR="$DATA_DIR/local_calcium"
mkdir -p "$STANFORD_DIR" "$CALCIUM_DIR"

# stanford dataset (env-driven)
cd "$DATA_DIR"
if [ -f "$DATASET_ZIP" ]; then
  echo "$DATASET_ZIP already present, skipping download"
else
  retry /b2-linux file download "b2://calcium-dataset/${DATASET_KEY}" "$DATASET_ZIP"
fi
retry unzip -o "$DATASET_ZIP" -d "$STANFORD_DIR"

# calcium dataset (fixed)
cd "$DATA_DIR"
if [ -f calcium_alldoses.zip ]; then
  echo "calcium_alldoses.zip already present, skipping download"
else
  retry /b2-linux file download "b2://calcium-dataset/calcium_alldoses.zip" calcium_alldoses.zip
fi
retry unzip -o calcium_alldoses.zip -d "$CALCIUM_DIR"

# --- optional: download finetune weights -------------------------------------
# Only runs when both FINETUNE_WEIGHTS_KEY and FINETUNE_WEIGHTS_FILE are set;
# otherwise this section is skipped entirely.
if [ -n "${FINETUNE_WEIGHTS_KEY:-}" ] && [ -n "${FINETUNE_WEIGHTS_FILE:-}" ]; then
  cd "$DATA_DIR"
  if [ -f "$FINETUNE_WEIGHTS_FILE" ]; then
    echo "$FINETUNE_WEIGHTS_FILE already present, skipping download"
  else
    retry /b2-linux file download "b2://calcium-dataset/checkpoints/${FINETUNE_WEIGHTS_KEY}" "$FINETUNE_WEIGHTS_FILE"
  fi
  export FINETUNE_WEIGHTS="$DATA_DIR/$FINETUNE_WEIGHTS_FILE"
  echo "FINETUNE_WEIGHTS=$FINETUNE_WEIGHTS"
  # persist to the Calcium .env (replace any prior entry to stay idempotent)
  CALCIUM_ENV=/workspace/repos/Calcium/.env
  touch "$CALCIUM_ENV"
  grep -v '^FINETUNE_WEIGHTS=' "$CALCIUM_ENV" > "$CALCIUM_ENV.tmp" || true
  mv "$CALCIUM_ENV.tmp" "$CALCIUM_ENV"
  echo "FINETUNE_WEIGHTS=$FINETUNE_WEIGHTS" >> "$CALCIUM_ENV"
else
  echo "FINETUNE_WEIGHTS_KEY/FINETUNE_WEIGHTS_FILE not set, skipping weights download"
fi

echo "=== provisioning finished OK $(date -u) ==="