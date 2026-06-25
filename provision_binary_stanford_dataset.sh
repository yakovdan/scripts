#!/usr/bin/env bash
set -euo pipefail
mkdir -p /workspace
mkdir -p /workspace/repos
mkdir -p $DATA_DIR
mkdir -p $OUTPUT_DIR

cd /workspace/repos
git clone "https://${GH_PAT}@github.com/$GH_USER/Calcium.git"
cd /workspace/repos/Calcium
git checkout origin/dev_TrainingGeneralizedDiceRandCrop

cd /workspace/repos
git clone "https://${GH_PAT}@github.com/$GH_USER/planned-rand-crop.git"
cd /workspace/repos/planned-rand-crop
pip install --no-deps .

pip install lightning numpy matplotlib scipy pydicom nibabel tqdm einops boto3 botocore wandb tensorboard dotenv
pip install monai-weekly

wandb login $WANDB_KEY

cd /
wget https://github.com/Backblaze/B2_Command_Line_Tool/releases/latest/download/b2-linux
chmod +x ./b2-linux
b2-linux account authorize $B2_KEY_ID $B2_APP_KEY
cd $DATA_DIR
b2-linux file download b2://calcium-dataset/binary_dataset_high_unified.zip  binary_dataset_high_unified.zip
unzip binary_dataset_high_unified.zip
