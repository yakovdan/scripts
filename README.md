# Provisioning env variables

`provision_stanford_dataset.sh` is a Vast.ai provisioning script. The variables
below control the dataset and (optional) finetune-weights download steps. They
must be present in the onstart/provisioning context.

## Dataset (required)

The script fails fast (`require_env`) if either of these is unset.

| Variable      | Meaning                                                        |
|---------------|----------------------------------------------------------------|
| `DATASET_KEY` | Object key **relative to the bucket root** `b2://calcium-dataset/`. |
| `DATASET_ZIP` | Local filename to save the download as, inside `$DATA_DIR`.     |

Resulting download:
`b2://calcium-dataset/${DATASET_KEY}` → `$DATA_DIR/$DATASET_ZIP`, then unzipped
into `$DATA_DIR`.

Example:
```bash
DATASET_KEY=binary_dataset_high_unified.zip
DATASET_ZIP=binary_dataset_high_unified.zip
```

## Finetune weights (optional)

This section runs **only when both** variables are set; otherwise it is skipped
and provisioning continues. They are *not* in `require_env`.

| Variable                | Meaning                                                                 |
|-------------------------|-------------------------------------------------------------------------|
| `FINETUNE_WEIGHTS_KEY`  | Object key **relative to the `checkpoints/` prefix**, i.e. downloaded from `b2://calcium-dataset/checkpoints/${FINETUNE_WEIGHTS_KEY}`. |
| `FINETUNE_WEIGHTS_FILE` | Local filename to save the weights as, inside `$DATA_DIR`.               |

Note the path difference: the dataset key is relative to the bucket root, but
the weights key is relative to `checkpoints/`.

Example:
```bash
FINETUNE_WEIGHTS_KEY=run42/best.ckpt
FINETUNE_WEIGHTS_FILE=finetune_init.ckpt
# downloads b2://calcium-dataset/checkpoints/run42/best.ckpt
#        -> $DATA_DIR/finetune_init.ckpt
```

## Derived variable (produced by the script)

| Variable           | Meaning                                                              |
|--------------------|---------------------------------------------------------------------|
| `FINETUNE_WEIGHTS` | Full local path `$DATA_DIR/$FINETUNE_WEIGHTS_FILE`. Set only when the weights step runs. |

`FINETUNE_WEIGHTS` is exported and **persisted** to
`/workspace/repos/Calcium/.env` (any prior `FINETUNE_WEIGHTS=` line is replaced,
so re-runs stay idempotent) so downstream training can read it.
