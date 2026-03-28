# Katib Demo And Evaluation Guide

## Purpose

This guide is for demonstrating the local MLOps platform from the first coding step up to a Katib optimization result, while keeping the work understandable enough that you can present it yourself.

The current platform in this repository is:

- local Kubernetes with `kind`
- `MetalLB` for `LoadBalancer` IP assignment
- `Istio` for ingress and traffic routing
- `Katib` for hyperparameter tuning
- `code-server` as the browser IDE
- a sample ML service based on the Iris dataset

## Short Answer: How Reliable Is Katib?

Katib is reliable for the part of the ML lifecycle it is designed for:

- hyperparameter tuning
- early stopping
- neural architecture search
- orchestrating repeatable experiment trials on Kubernetes

Katib is not a complete MLOps platform by itself. It does not replace:

- data versioning
- feature engineering workflows
- artifact storage
- model registry
- CI/CD
- production model serving
- monitoring and governance

### Practical Evaluation

For a university demo, research workflow, internal platform prototype, or controlled server environment, Katib is a credible and practical choice.

For a serious production platform, Katib should be treated as one subsystem inside a larger stack.

### Why This Assessment Is Reasonable

From the official Kubeflow Katib overview:

- Katib is a Kubernetes-native AutoML project
- it supports hyperparameter tuning, early stopping, and NAS
- it is framework-agnostic
- it integrates with Kubernetes jobs, Kubeflow training jobs, Argo Workflows, and Tekton Pipelines
- as of the Kubeflow documentation page last modified on October 26, 2025, Katib is still marked as `Beta`

From the Katib GitHub releases page:

- as of March 28, 2026, the latest GitHub release visible is `v0.19.0`, published on October 30, 2025

Important local note for this repo:

- this project currently installs `Katib v0.17.0` for the laptop lab because that version is already integrated and tested here

### What To Say To Your Professor

You can say this:

> Katib is reliable for Kubernetes-native experiment management and hyperparameter optimization, but it is only one layer of a full MLOps system. It is strong for trial orchestration and metric comparison, but a future production platform still needs pipelines, registry, serving, monitoring, storage, and governance around it.

## What Is Katib's Role In An ML Project?

Katib belongs in the experimentation and optimization part of the ML lifecycle.

Its job is:

1. take one training workload
2. vary the hyperparameters
3. run multiple trials
4. collect metrics such as `accuracy`
5. compare trials
6. identify the best parameter set

In this repository, Katib does not write the ML code for you. It does not decide the dataset or business objective. It only automates and manages the optimization search process.

## What You Need For A Complete Local ML Environment

### A. Local Platform Tools

These are the base tools needed on the laptop:

- Docker Desktop
- `kind`
- `kubectl`
- `helm`
- `istioctl`
- `python3`
- `git`

### B. Cluster Modules Already In This Repo

These are the Kubernetes-side modules already used here:

- `kind` cluster
- default storage class
- `MetalLB`
- `Istio`
- `Katib`
- `code-server`
- the sample Iris API deployment and service

### C. Python Packages Needed For The Current Demo

The sample ML project in this repo uses:

- `fastapi`
- `numpy`
- `scikit-learn`
- `uvicorn`

If your future project changes framework, add the relevant ML stack:

- `xgboost` for boosted trees
- `pytorch` for neural networks
- `tensorflow` or `keras` for deep learning
- `pandas` for data preparation
- `matplotlib` or `seaborn` for exploration
- `jupyterlab` if you want notebook-based exploration outside Katib

### D. What Is Missing If You Want A More Complete MLOps Platform

For a stronger future server deployment, add these components:

- object storage such as `MinIO` or cloud `S3` for datasets, artifacts, and pipeline outputs
- `Kubeflow Pipelines` for end-to-end workflow orchestration
- `Kubeflow Model Registry` or another registry for model versions and metadata
- `KServe` for production model serving
- `Prometheus` and `Grafana` for metrics and dashboards
- `cert-manager` plus real DNS/TLS for secure ingress
- a container registry for images
- authentication, RBAC, and secret management

For larger GPU or distributed workloads, also add:

- `Kubeflow Trainer`
- GPU drivers and operators
- a batch scheduler such as `Kueue` if the server will run multiple teams or queued jobs

## Recommended Testing Strategy

Do not test only the Katib UI. Test the whole path.

### Level 1: Code Test

Goal:

- confirm the training code runs and prints a numeric metric

For this repo, the critical code files are:

- [model.py](/Users/youseffayyaz/Documents/GitHub/ML_Ops/apps/iris-service/mlops_iris/model.py)
- [katib_objective.py](/Users/youseffayyaz/Documents/GitHub/ML_Ops/apps/iris-service/mlops_iris/katib_objective.py)
- [serve.py](/Users/youseffayyaz/Documents/GitHub/ML_Ops/apps/iris-service/mlops_iris/serve.py)

Success criteria:

- the training function returns a valid accuracy
- the objective prints `accuracy=<value>`
- the serving API responds to `healthz` and `predict`

### Level 2: Image Build Test

Goal:

- confirm the training code is containerized correctly

Success criteria:

- Docker image builds successfully
- image can be loaded into `kind`

### Level 3: Kubernetes Deployment Test

Goal:

- confirm the app is running in the cluster

Success criteria:

- the `vscode`, `istio`, `katib`, and `iris-service` pods are `Running`
- the `istio-ingressgateway` service has the expected external IP

### Level 4: Ingress And Service Test

Goal:

- confirm external access and routing work

Success criteria:

- `http://172.19.255.206/` opens `code-server`
- `http://172.19.255.206/katib/` opens Katib
- `http://172.19.255.206/iris/healthz` returns OK

### Level 5: Katib Experiment Test

Goal:

- confirm Katib can launch trials, collect metrics, and choose a best trial

Success criteria:

- the experiment reaches `Succeeded`
- at least one trial is completed
- Katib reports an optimal trial with parameter values and metric values

### Level 6: Repeatability Test

Goal:

- confirm the result is reproducible enough for demonstration

Success criteria:

- rerunning the experiment produces valid trials again
- the metric remains in the same reasonable performance range

### Level 7: Failure Test

Goal:

- prove the platform detects configuration mistakes

Examples:

- wrong `objectiveMetricName`
- wrong container command
- invalid image name
- impossible parameter range

Success criteria:

- Katib marks the experiment or trials as failed
- logs explain the cause

## The Best Demo Case For This Platform

### Primary Demo Case

Use the project already inside this repository:

- GitHub repo: <https://github.com/josephfayyaz/ML_Ops>

Why this is the best demo case:

- it already fits your laptop cluster
- it already has a working Katib experiment
- it is small enough to explain in a meeting
- it demonstrates the full path from Python code to Kubernetes result

### The ML Case

The current sample project does this:

- loads the Iris dataset
- trains a `RandomForestClassifier`
- exposes an inference API with FastAPI
- exposes Katib objective metrics through stdout
- searches these hyperparameters:
  - `n_estimators`
  - `max_depth`
  - `min_samples_split`

### Current Verified Result In This Cluster

At the time of writing, the current experiment in this cluster is:

- experiment name: `iris-random-search`
- status: `Succeeded`
- best trial metric: `accuracy=0.9667`
- best parameters:
  - `n_estimators=52`
  - `max_depth=5`
  - `min_samples_split=9`

This is useful in a demo because you can show both:

- the procedure
- the optimization result

## Optional External Reference Project

If you want an official external reference after the Iris demo, use the Katib examples from the upstream project:

- Katib repo: <https://github.com/kubeflow/katib>
- Katib examples list: <https://github.com/kubeflow/katib/tree/master/examples>

That is a good second step because it gives you comparison material from the upstream project itself.

## How You Should Demonstrate The System Yourself

This is the recommended professor demo flow.

### Step 1: Explain The Architecture

Show the architecture first:

- one stable laptop IP: `172.19.255.206`
- `Istio` handles the browser entrypoint
- `Katib` runs optimization trials
- the sample ML container is both the trainable workload and the served API

### Step 2: Show The Source Code

Open these files and explain them in order:

1. [model.py](/Users/youseffayyaz/Documents/GitHub/ML_Ops/apps/iris-service/mlops_iris/model.py)
2. [katib_objective.py](/Users/youseffayyaz/Documents/GitHub/ML_Ops/apps/iris-service/mlops_iris/katib_objective.py)
3. [serve.py](/Users/youseffayyaz/Documents/GitHub/ML_Ops/apps/iris-service/mlops_iris/serve.py)
4. [iris-experiment.yaml](/Users/youseffayyaz/Documents/GitHub/ML_Ops/manifests/katib/iris-experiment.yaml)

What to explain:

- `model.py` defines how the model is trained
- `katib_objective.py` is what Katib actually runs in each trial
- `serve.py` exposes the inference endpoint
- `iris-experiment.yaml` defines the search space and objective

### Step 3: Run The Platform

On a fresh laptop boot:

```bash
sudo ifconfig lo0 alias 172.19.255.206/32 up
bash scripts/bootstrap.sh
```

Then open:

- `http://172.19.255.206/`
- `http://172.19.255.206/katib/`
- `http://172.19.255.206/iris/`

### Step 4: Show The System Tests

Run these commands:

```bash
kubectl get pods -A
kubectl get svc -A
kubectl get experiments -n katib-experiments
kubectl get trials -n katib-experiments
curl -s http://172.19.255.206/iris/healthz
curl -s http://172.19.255.206/iris/
```

To demonstrate Istio load balancing on the two ML API replicas:

```bash
for i in 1 2 3 4 5 6; do
  curl -s http://172.19.255.206/iris/healthz
  echo
done
```

You should see different `podName` values over repeated calls.

### Step 5: Show A Controlled Change

For example, change one of these:

- the Katib search range in [iris-experiment.yaml](/Users/youseffayyaz/Documents/GitHub/ML_Ops/manifests/katib/iris-experiment.yaml)
- the objective goal
- the ML algorithm parameters in [model.py](/Users/youseffayyaz/Documents/GitHub/ML_Ops/apps/iris-service/mlops_iris/model.py)

Then rerun:

```bash
bash scripts/bootstrap.sh
```

This gives you a clean demonstration of:

- code change
- image rebuild
- redeploy
- experiment rerun
- new result

### Step 6: Show The Katib Result

Use either the Katib UI or CLI.

CLI commands:

```bash
kubectl get experiment -n katib-experiments iris-random-search -o yaml
kubectl get trials -n katib-experiments
```

What to point out:

- objective metric name
- search algorithm
- search space
- best trial
- best parameter assignment
- best metric value

## How To Judge Whether The System Is Good Enough For The Future

### Good Signals

The platform is promising if:

- you can rebuild and rerun experiments consistently
- Katib results are easy to inspect
- the training image is reproducible
- Istio routing is stable
- the model API can be tested independently from Katib

### Warning Signals

The current laptop version is not yet enough for production if:

- artifacts are not stored externally
- there is no model registry
- there is no authentication or TLS
- logs and metrics are not centralized
- there is no approval or release workflow
- there is no automated pipeline from training to deployment

## Recommended Future Server Architecture

If you move from the laptop to a real server, the next practical architecture is:

1. Kubernetes cluster with persistent storage
2. object storage for datasets and model artifacts
3. `Kubeflow Pipelines` for workflow orchestration
4. `Katib` for optimization
5. `Kubeflow Model Registry` for model metadata and lifecycle control
6. `KServe` for serving
7. `Prometheus` and `Grafana` for monitoring
8. ingress with TLS and authentication
9. image registry and CI/CD or GitOps

If the workload becomes large or GPU-heavy, add:

- `Kubeflow Trainer`
- scheduler support for queued GPU jobs
- GPU monitoring and quota controls

## Suggested Conclusion For Your Presentation

You can present the platform like this:

> This laptop setup proves that the core MLOps workflow is valid: code can be packaged, deployed on Kubernetes, exposed through Istio, optimized with Katib, and verified by measurable results. Katib is reliable for experiment orchestration and hyperparameter search, but a future server deployment should add pipelines, registry, serving, monitoring, and governance to become a complete production platform.

## Sources

- Kubeflow Katib overview: <https://www.kubeflow.org/docs/components/katib/overview/>
- Kubeflow Katib installation: <https://www.kubeflow.org/docs/components/katib/installation/>
- Katib GitHub releases: <https://github.com/kubeflow/katib/releases>
- Katib GitHub repository: <https://github.com/kubeflow/katib>
- Kubeflow Pipelines concepts: <https://www.kubeflow.org/docs/components/pipelines/concepts/pipeline/>
- Kubeflow Trainer overview: <https://www.kubeflow.org/docs/components/trainer/overview/>
- Kubeflow Model Registry overview: <https://www.kubeflow.org/docs/components/model-registry/overview/>
- KServe overview: <https://kserve.github.io/website/docs/admin-guide/overview>
