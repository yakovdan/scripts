#!/usr/bin/env bash
set -euo pipefail
mkdir -p /workspace
mkdir -p /workspace/repos
mkdir -p $DATA_DIR
mkdir -p $OUTPUT_DIR

cd /workspace/repos
git clone "https://${GH_PAT}@github.com/$GH_USER/Calcium.git"
cd /workspace/repos/Calcium
git checkout dev_TrainingGeneralizedDiceRandCrop

cd /workspace/repos
git clone "https://${GH_PAT}@github.com/$GH_USER/planned-rand-crop.git"
cd /workspace/repos/planned-rand-crop
pip install --no-deps .

pip install lightning numpy matplotlib scipy pydicom nibabel tqdm einops boto3 botocore wandb tensorboard
pip install monai-weekly

wandb login $WANDB_KEY

cd /venv/main/bin
wget https://github.com/Backblaze/B2_Command_Line_Tool/releases/latest/download/b2-linux
chmod +x ./b2-linux
b2-linux account authorize $B2_KEY_ID $B2_APP_KEY
cd $DATA_DIR
for i in {0..440}; do b2-linux file download b2://calcium-dataset/stanford-aimi/image$(printf %05d $i).npz image$(printf %05d $i).npz ; done
for i in {0..440}; do b2-linux file download b2://calcium-dataset/stanford-aimi/label$(printf %05d $i).npz label$(printf %05d $i).npz ; done