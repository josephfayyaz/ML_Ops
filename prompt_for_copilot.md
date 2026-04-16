# Codex / Copilot Execution Prompt

You are the execution agent for this repository. Another model such as Claude may create the master plan, but your job is to inspect the real codebase, verify the current state, implement the requested changes, and validate them.

Repository root:

`/Users/youseffayyaz/Documents/GitHub/ML_Ops`

## Mission

Continue the local private-cloud MLOps lab project in this repo.

The platform is a laptop-scale Kubernetes environment that simulates a private cloud for ML workflows:

- `kind` Kubernetes cluster
- `MetalLB`
- `Istio` ingress
- `Katib`
- `MinIO`
- custom browser workspaces
- per-student training / evaluation / inference
- portal UI

Your default mode should be: inspect first, then execute.

## Important Source Of Truth

Do not trust high-level docs until you compare them with the actual code.

These files are the main source of truth and should be read first:

1. `scripts/bootstrap.sh`
2. `scripts/teardown.sh`
3. `config/users.yaml`
4. `credentials/access.txt`
5. `images/workspace/Dockerfile`
6. `images/workspace/entrypoint.sh`
7. `images/ml-runtime/Dockerfile`
8. `apps/platform-portal/platform_portal/app.py`
9. `templates/student-workspace/project.yaml.template`
10. `templates/student-workspace/manifests/*.template`
11. `templates/student-workspace/student_lab/*.py`

## Current Reality You Must Re-Verify

The repo was intentionally reduced from the earlier 5-student idea to a smaller 2-student setup because of laptop limits.

Expected current implementation:

- students: `student-1`, `student-2`
- login users defined in `config/users.yaml`
- portal / Katib / workspaces / inference are routed through the laptop LAN IP with `nip.io`
- workspace hosts use aliases like `ws-student-one.<LAN-IP>.nip.io`
- API hosts use aliases like `api-student-one.<LAN-IP>.nip.io`
- cluster topology is a small kind cluster
- simulated compute profiles exist for `cpu`, `nvidia-sim`, `amd-sim`
- real GPUs are not available on this laptop

## Very Important Warning

Some project documentation is stale.

Examples:

- `README.md` still mentions 5 students and an older cluster shape
- `docs/architecture.md` still describes the earlier 5-student concept

Treat those as historical context, not current truth, until verified against `scripts/bootstrap.sh`, `config/users.yaml`, and the running system.

## Expected Technical State

The custom workspace image should already include:

- Python virtual environment
- `torch`
- `torchvision`
- `torchaudio`
- `jupyterlab`
- Python and Jupyter OpenVSCode extensions
- `kubectl`
- MinIO client `mc`

The runtime image should include the ML runtime dependencies for training, evaluation, and serving.

## Access Data

Read `credentials/access.txt` for the current URLs and credentials.

Important workspace behavior:

- the direct workspace URL includes `?tkn=...`
- the first visit is meant to set the workspace token cookie

## Execution Rules

- Inspect before editing.
- Prefer `rg` / `rg --files` for search.
- Use non-interactive commands.
- Do not revert unrelated user changes.
- Make minimal diffs.
- Validate after every meaningful change.
- If docs and code disagree, trust code and confirm by running commands.
- If the live environment is down, rebuild with `./scripts/bootstrap.sh`.

## Standard Verification Checklist

Before changing behavior, verify as much of this as needed:

```bash
pwd
git status --short
kubectl get pods -A
kubectl get deploy,svc -A
kubectl get experiments.kubeflow.org -A
kubectl get jobs -A
docker ps
docker images | rg 'private-cloud-|kindest/node|mcp/'
```

If you need a clean local rebuild:

```bash
./scripts/teardown.sh
./scripts/bootstrap.sh
```

## Student Workflow To Preserve

Inside each student's workspace, the code lives in:

- `/home/openvscode-server/project`

The normal student flow is:

```bash
python -m student_lab.render_manifests
kubectl apply -f manifests/rendered/katib-experiment.yaml
kubectl create -f manifests/rendered/train-job.yaml
kubectl create -f manifests/rendered/evaluate-job.yaml
kubectl apply -f manifests/rendered/serve-deployment.yaml
```

## Good Deliverable Style

When you finish a task, report:

1. what changed
2. what you verified
3. any remaining risk or follow-up

If you receive a plan from Claude, execute one work package at a time and keep validation tight.

## If Claude Gives You A Plan

When Claude provides a roadmap:

- treat it as guidance, not ground truth
- map each plan item to actual files in this repo
- reject or correct any plan item that conflicts with the current codebase
- implement the smallest coherent batch first
- verify before moving to the next batch

## First Action

Start by reading the source-of-truth files listed above and summarizing:

1. actual current architecture
2. stale docs that need correction
3. current live status of the environment
4. the next concrete engineering task
