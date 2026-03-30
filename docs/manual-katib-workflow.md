# Manual Katib Workflow

This runbook explains how to use the current laptop lab without rerunning `bootstrap.sh`.

## Public URLs

- VS Code: `http://172.19.255.206/`
- Katib UI: `http://172.19.255.206/katib/`
- Iris API: `http://172.19.255.206/iris/`
- House prices API: `http://172.19.255.206/housing/`
- Results dashboard: `http://172.19.255.206/results/`

## What Was Added

- Five Iris comparison experiments under `manifests/katib/manual/`
- One house-prices Katib experiment under `manifests/katib/manual/house-prices-random-search-01.yaml`
- A real housing demo app under `apps/house-prices/`
- A presentation dashboard under `apps/results-dashboard/`
- A shared demo image definition under `images/mlops-demo/`

## Experiment Vs Trial

- An `Experiment` is the Katib search job. It defines the objective, the search space, and how many trials Katib should try.
- A `Trial` is one concrete training run with one concrete hyperparameter set chosen by Katib.

For example:

- `iris-random-search-04-wide-forest` is an Experiment
- `iris-random-search-04-wide-forest-zjwqvrqc` is its best Trial

## Do Not Use `bootstrap.sh` For New Katib Runs

`bootstrap.sh` is a cluster setup script. It also clears the default Katib experiment state. Use it only when rebuilding the lab.

For repeated tuning runs:

1. Keep the cluster running.
2. Apply new experiment YAML files with `kubectl apply -f ...`.
3. View the results in Katib UI or the results dashboard.

## Current Experiment Files

- `manifests/katib/manual/iris-random-search-01.yaml`
- `manifests/katib/manual/iris-random-search-02.yaml`
- `manifests/katib/manual/iris-random-search-03.yaml`
- `manifests/katib/manual/iris-random-search-04.yaml`
- `manifests/katib/manual/iris-random-search-05.yaml`
- `manifests/katib/manual/house-prices-random-search-01.yaml`

## How To Run The Iris Comparison Set

From the repo root:

```bash
kubectl apply -f manifests/katib/manual/iris-random-search-01.yaml
kubectl apply -f manifests/katib/manual/iris-random-search-02.yaml
kubectl apply -f manifests/katib/manual/iris-random-search-03.yaml
kubectl apply -f manifests/katib/manual/iris-random-search-04.yaml
kubectl apply -f manifests/katib/manual/iris-random-search-05.yaml
```

Watch progress:

```bash
kubectl get experiments -n katib-experiments
kubectl get trials -n katib-experiments
```

Then open Katib UI:

- `http://172.19.255.206/katib/`

Or open the dashboard:

- `http://172.19.255.206/results/`

### Current Iris Results

- `iris-random-search-01-baseline`
  Best trial: `iris-random-search-01-baseline-p92pmtxd`
  Best parameters: `n_estimators=119`, `max_depth=5`, `min_samples_split=7`
  Best accuracy: `0.9667`
- `iris-random-search-02-shallow`
  Best trial: `iris-random-search-02-shallow-lvfzgrqp`
  Best parameters: `n_estimators=103`, `max_depth=3`, `min_samples_split=5`
  Best accuracy: `0.9667`
- `iris-random-search-03-deep`
  Best trial: `iris-random-search-03-deep-kzkjq5gh`
  Best parameters: `n_estimators=179`, `max_depth=9`, `min_samples_split=5`
  Best accuracy: `0.9667`
- `iris-random-search-04-wide-forest`
  Best trial: `iris-random-search-04-wide-forest-zjwqvrqc`
  Best parameters: `n_estimators=187`, `max_depth=7`, `min_samples_split=7`
  Best accuracy: `0.9667`
- `iris-random-search-05-regularized`
  Best trial: `iris-random-search-05-regularized-2q49jrqb`
  Best parameters: `n_estimators=140`, `max_depth=3`, `min_samples_split=8`
  Best accuracy: `0.9667`

Note:

- Katib can occasionally overshoot the nominal trial count by one during reconciliation. That is why some Iris experiments finished with 5 or 6 trials even though the YAML target was lower.

## How To Run The House-Prices Demo

Apply the Katib experiment:

```bash
kubectl apply -f manifests/katib/manual/house-prices-random-search-01.yaml
```

Watch it:

```bash
kubectl get experiments -n katib-experiments
kubectl get trials -n katib-experiments
```

The public demo service is already available at:

- `http://172.19.255.206/housing/`

The prediction endpoint is:

```bash
curl -sS -X POST http://172.19.255.206/housing/predict \
  -H 'Content-Type: application/json' \
  -d '{"overallQual":7,"grLivArea":1710,"garageCars":2,"totalBsmtSF":856,"yearBuilt":2003,"fullBath":2,"firstFlrSF":856,"totRmsAbvGrd":8}'
```

Current best Katib result:

- Experiment: `house-prices-random-search-01`
- Best trial: `house-prices-random-search-01-lt4mswnl`
- Best parameters: `n_estimators=104`, `max_depth=14`, `min_samples_split=6`, `min_samples_leaf=3`
- Best `rmse`: `31356.04`

## How To Rerun An Experiment

Delete the old experiment and apply it again:

```bash
kubectl delete experiment -n katib-experiments iris-random-search-01-baseline
kubectl apply -f manifests/katib/manual/iris-random-search-01.yaml
```

If you want to keep the old result and create a second run instead:

1. Copy the YAML file.
2. Change `metadata.name`.
3. Apply the new file.

Example:

```bash
cp manifests/katib/manual/iris-random-search-01.yaml manifests/katib/manual/iris-random-search-06.yaml
```

Then edit:

```yaml
metadata:
  name: iris-random-search-06-extra
```

Then apply it:

```bash
kubectl apply -f manifests/katib/manual/iris-random-search-06.yaml
```

## Where The New Apps Live

- Iris package: `apps/iris-service/mlops_iris/`
- House-prices package: `apps/house-prices/mlops_house_prices/`
- House dataset: `apps/house-prices/data/ames_housing_selected.csv`
- Results dashboard: `apps/results-dashboard/mlops_results_dashboard/`
- Shared image: `images/mlops-demo/Dockerfile`

## How The Dashboard Works

The dashboard reads live Katib Experiment CRDs from Kubernetes and shows:

- experiment status
- best trial
- best metric
- best hyperparameters
- number of succeeded trials
- creation time

Open it here:

- `http://172.19.255.206/results/`
