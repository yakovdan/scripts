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

# --- download & unpack dataset -----------------------------------------------
# Source key within the calcium-dataset bucket and the local zip name are both
# env-driven (DATASET_KEY / DATASET_ZIP).
cd "$DATA_DIR"
if [ -f "$DATASET_ZIP" ]; then
  echo "$DATASET_ZIP already present, skipping download"
else
  retry /b2-linux file download "b2://calcium-dataset/${DATASET_KEY}" "$DATASET_ZIP"
fi
retry unzip -o "$DATASET_ZIP" -d "$DATA_DIR"

echo "=== provisioning finished OK $(date -u) ==="