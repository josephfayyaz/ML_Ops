# Student Workspace

This is your personal MLOps project area.

## What You Have

- your own Kubernetes namespace
- your own MinIO bucket
- your own browser IDE workspace
- your own Katib experiments and trials
- your own training, evaluation, and serving manifests

## Typical Flow

1. Upload your dataset from the portal.
2. Edit `project.yaml`.
3. Edit files under `student_lab/`.
4. Run `python -m student_lab.render_manifests`.
5. Run `kubectl apply -f manifests/rendered/katib-experiment.yaml`.
6. Run `kubectl create -f manifests/rendered/train-job.yaml`.
7. Run `kubectl create -f manifests/rendered/evaluate-job.yaml`.
8. Run `kubectl apply -f manifests/rendered/serve-deployment.yaml`.

If you upload a dataset with different column names, update `dataset.target_column`
and `dataset.feature_columns` in `project.yaml` before rerendering manifests.

## Compute Profiles

- `cpu`
- `nvidia-sim`
- `amd-sim`
- `nvidia-real`
- `amd-real`

Use the simulated profiles on this laptop. The real profiles are for the future Linux GPU server.
