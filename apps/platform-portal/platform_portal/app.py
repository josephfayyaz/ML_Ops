from __future__ import annotations

from dataclasses import dataclass
from datetime import timezone
import html
import json
import os
from pathlib import Path
import re
from typing import Any
from urllib.parse import quote

import boto3
from botocore.client import Config as BotoConfig
from botocore.exceptions import ClientError
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse, Response, StreamingResponse
from itsdangerous import BadSignature, URLSafeTimedSerializer
from kubernetes import client, config
from kubernetes.client.exceptions import ApiException
from kubernetes.config.config_exception import ConfigException
import yaml


GROUP = "kubeflow.org"
VERSION = "v1beta1"
EXPERIMENTS_PLURAL = "experiments"
USERS_FILE = Path(os.getenv("USERS_FILE", "/etc/mlops/users.yaml"))
SESSION_SECRET = os.getenv("SESSION_SECRET", "replace-me")
SESSION_COOKIE = "mlops_portal_session"
OBJECT_STORAGE_ENDPOINT = os.getenv("OBJECT_STORAGE_ENDPOINT", "http://minio.platform.svc.cluster.local:9000")
OBJECT_STORAGE_SECURE = os.getenv("OBJECT_STORAGE_SECURE", "false").lower() == "true"
OBJECT_STORAGE_ACCESS_KEY = os.getenv("OBJECT_STORAGE_ACCESS_KEY", "")
OBJECT_STORAGE_SECRET_KEY = os.getenv("OBJECT_STORAGE_SECRET_KEY", "")
KATIB_HOST = os.getenv("KATIB_HOST", "")
PUBLIC_BASE_DOMAIN = os.getenv("PUBLIC_BASE_DOMAIN", "")

app = FastAPI(title="private-cloud-portal", version="2.0.3")
_KUBE_READY = False
_S3: Any | None = None


@dataclass
class User:
    username: str
    role: str
    password: str
    namespace: str | None = None


def load_users() -> dict[str, User]:
    payload = yaml.safe_load(USERS_FILE.read_text(encoding="utf-8")) or {}
    users = {}
    for item in payload.get("users", []):
        user = User(
            username=item["username"],
            role=item["role"],
            password=item["password"],
            namespace=item.get("namespace"),
        )
        users[user.username] = user
    return users


def serializer() -> URLSafeTimedSerializer:
    return URLSafeTimedSerializer(SESSION_SECRET, salt="private-cloud-portal")


def ensure_kube() -> None:
    global _KUBE_READY
    if _KUBE_READY:
        return
    try:
        config.load_incluster_config()
    except ConfigException:
        config.load_kube_config()
    _KUBE_READY = True


def s3_client() -> Any:
    global _S3
    if _S3 is None:
        _S3 = boto3.client(
            "s3",
            endpoint_url=OBJECT_STORAGE_ENDPOINT,
            aws_access_key_id=OBJECT_STORAGE_ACCESS_KEY,
            aws_secret_access_key=OBJECT_STORAGE_SECRET_KEY,
            region_name="us-east-1",
            use_ssl=OBJECT_STORAGE_SECURE,
            config=BotoConfig(signature_version="s3v4", s3={"addressing_style": "path"}),
        )
    return _S3


def get_current_user(request: Request) -> User | None:
    token = request.cookies.get(SESSION_COOKIE)
    if not token:
        return None
    try:
        payload = serializer().loads(token, max_age=60 * 60 * 12)
    except BadSignature:
        return None
    return load_users().get(payload["username"])


def require_user(request: Request) -> User:
    user = get_current_user(request)
    if user is None:
        raise HTTPException(status_code=401, detail="login required")
    return user


def student_names(users: dict[str, User]) -> list[str]:
    return [user.namespace for user in users.values() if user.role == "student" and user.namespace]


def can_access(user: User, student: str) -> bool:
    return user.role == "admin" or user.namespace == student


def workspace_host(student: str) -> str:
    return f"ws-{student_host_slug(student)}.{PUBLIC_BASE_DOMAIN}"


def api_host(student: str) -> str:
    return f"api-{student_host_slug(student)}.{PUBLIC_BASE_DOMAIN}"


def student_host_slug(student: str) -> str:
    return {
        "student-1": "student-one",
        "student-2": "student-two",
        "student-3": "student-three",
        "student-4": "student-four",
        "student-5": "student-five",
    }.get(student, student.replace("1", "one").replace("2", "two").replace("3", "three").replace("4", "four").replace("5", "five"))


def workspace_token(student: str) -> str:
    user = load_users().get(student)
    if user is None:
        return ""
    return re.sub(r"[^0-9A-Za-z-]", "-", user.password)


def deployment_ready(namespace: str, name: str) -> bool:
    ensure_kube()
    api = client.AppsV1Api()
    try:
        deployment = api.read_namespaced_deployment_status(name=name, namespace=namespace)
    except ApiException as exc:
        if exc.status in {403, 404}:
            return False
        raise
    return (deployment.status.available_replicas or 0) > 0


def list_bucket_objects(bucket: str, prefix: str) -> list[dict[str, Any]]:
    try:
        response = s3_client().list_objects_v2(Bucket=bucket, Prefix=prefix)
    except ClientError:
        return []
    items = []
    for entry in response.get("Contents", []):
        key = entry["Key"]
        if key.endswith("/"):
            continue
        items.append(
            {
                "key": key,
                "name": key.split("/")[-1],
                "size": entry["Size"],
                "updated": entry["LastModified"].astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
                "updated_at": entry["LastModified"].timestamp(),
            }
        )
    return sorted(items, key=lambda value: value["updated_at"], reverse=True)


def latest_json(bucket: str, prefix: str, suffix: str) -> dict[str, Any] | None:
    objects = list_bucket_objects(bucket, prefix)
    for item in objects:
        if not item["key"].endswith(suffix):
            continue
        try:
            response = s3_client().get_object(Bucket=bucket, Key=item["key"])
        except ClientError:
            return None
        return json.loads(response["Body"].read())
    return None


def list_experiments(namespace: str) -> list[dict[str, Any]]:
    ensure_kube()
    api = client.CustomObjectsApi()
    try:
        response = api.list_namespaced_custom_object(
            group=GROUP,
            version=VERSION,
            namespace=namespace,
            plural=EXPERIMENTS_PLURAL,
        )
    except ApiException as exc:
        if exc.status == 404:
            return []
        raise

    results = []
    for item in response.get("items", []):
        metadata = item.get("metadata", {})
        status = item.get("status", {})
        best = status.get("currentOptimalTrial", {})
        params = {
            entry.get("name"): entry.get("value")
            for entry in best.get("parameterAssignments", [])
        }
        metrics = {}
        for metric in best.get("observation", {}).get("metrics", []):
            key = metric.get("name")
            value = metric.get("min", metric.get("max", metric.get("latest")))
            if key and value is not None:
                metrics[key] = float(value)
        state = next(
            (
                condition.get("type")
                for condition in reversed(status.get("conditions", []))
                if condition.get("status") == "True"
            ),
            "Unknown",
        )
        results.append(
            {
                "name": metadata.get("name", ""),
                "created": metadata.get("creationTimestamp", ""),
                "status": state,
                "parameters": params,
                "metrics": metrics,
                "trials": status.get("trials", 0),
                "trials_succeeded": status.get("trialsSucceeded", 0),
            }
        )
    return sorted(results, key=lambda value: value["created"], reverse=True)


def student_snapshot(student: str) -> dict[str, Any]:
    bucket = student
    experiments = list_experiments(student)
    latest_experiment = experiments[0] if experiments else None
    latest_model = latest_json(bucket, "models/", "metadata.json")
    latest_eval = latest_json(bucket, "evaluations/", "report.json")
    datasets = list_bucket_objects(bucket, "datasets/")
    workspace_ready = deployment_ready(student, "workspace")
    api_ready = latest_model is not None and deployment_ready(student, f"{student}-model-api")
    token = workspace_token(student)
    return {
        "student": student,
        "workspace_url": f"http://{workspace_host(student)}/?tkn={quote(token)}" if token else f"http://{workspace_host(student)}",
        "workspace_ready": workspace_ready,
        "api_url": f"http://{api_host(student)}",
        "api_ready": api_ready,
        "katib_url": f"http://{KATIB_HOST}",
        "latest_experiment": latest_experiment,
        "latest_model": latest_model,
        "latest_eval": latest_eval,
        "datasets": datasets,
        "models": list_bucket_objects(bucket, "models/"),
        "evaluations": list_bucket_objects(bucket, "evaluations/"),
    }


def render_artifact_list(student: str, items: list[dict[str, Any]]) -> str:
    if not items:
        return "<p class='empty'>No files yet.</p>"
    rows = []
    for item in items[:6]:
        rows.append(
            "<li>"
            f"<a href='/files/{html.escape(student)}/{html.escape(item['key'])}'>{html.escape(item['name'])}</a>"
            f"<span>{html.escape(item['updated'])}</span>"
            "</li>"
        )
    return "<ul class='artifact-list'>" + "".join(rows) + "</ul>"


def render_action(label: str, url: str, enabled: bool = True) -> str:
    if enabled:
        return f"<a href='{html.escape(url)}' target='_blank' rel='noreferrer'>{html.escape(label)}</a>"
    return f"<span class='action-disabled'>{html.escape(label)}</span>"


def render_card(snapshot: dict[str, Any]) -> str:
    experiment = snapshot["latest_experiment"]
    status = "No experiments yet"
    metric = "-"
    params_html = "<span class='chip'>-</span>"
    trial_text = "-"
    if experiment:
        status = experiment["status"]
        if experiment["metrics"]:
            metric_name, metric_value = next(iter(experiment["metrics"].items()))
            metric = f"{metric_name}={metric_value:.4f}"
        if experiment["parameters"]:
            params_html = "".join(
                f"<span class='chip'>{html.escape(name)}={html.escape(str(value))}</span>"
                for name, value in experiment["parameters"].items()
            )
        trial_text = f"{experiment['trials_succeeded']}/{experiment['trials']} trials"

    latest_eval = snapshot["latest_eval"] or {}
    eval_metrics = latest_eval.get("metrics", {})
    eval_html = (
        "<span class='chip'>"
        + html.escape(", ".join(f"{name}={value:.4f}" for name, value in eval_metrics.items()))
        + "</span>"
        if eval_metrics
        else "<span class='chip'>-</span>"
    )

    dataset_name = snapshot["datasets"][0]["name"] if snapshot["datasets"] else "-"
    api_docs_url = f"{snapshot['api_url']}/docs"
    infer_hint = (
        ""
        if snapshot["api_ready"]
        else "<p class='hint'>Inference appears after training a model and applying the serve manifest.</p>"
    )
    quickstart = (
        "<details class='quickstart'>"
        "<summary>Run these commands in the workspace terminal</summary>"
        "<pre>"
        "python -m student_lab.render_manifests\n"
        "kubectl apply -f manifests/rendered/katib-experiment.yaml\n"
        "kubectl create -f manifests/rendered/train-job.yaml\n"
        "kubectl create -f manifests/rendered/evaluate-job.yaml\n"
        "kubectl apply -f manifests/rendered/serve-deployment.yaml"
        "</pre>"
        "</details>"
    )

    return (
        "<section class='student-card'>"
        f"<div class='student-header'><div><h2>{html.escape(snapshot['student'])}</h2>"
        f"<p>{html.escape(snapshot['student'])} namespace and bucket</p></div>"
        "<div class='actions'>"
        f"{render_action('Workspace', snapshot['workspace_url'], snapshot['workspace_ready'])}"
        f"{render_action('Katib UI', snapshot['katib_url'])}"
        f"{render_action('Inference API', api_docs_url, snapshot['api_ready'])}"
        "</div></div>"
        "<p class='path-tip'>Write your code in <code>project.yaml</code> and the files under <code>student_lab/</code> inside the workspace.</p>"
        f"{quickstart}"
        "<div class='stats'>"
        f"<article><span class='label'>Status</span><strong>{html.escape(status)}</strong></article>"
        f"<article><span class='label'>Best metric</span><strong>{html.escape(metric)}</strong></article>"
        f"<article><span class='label'>Trials</span><strong>{html.escape(trial_text)}</strong></article>"
        f"<article><span class='label'>Dataset</span><strong>{html.escape(dataset_name)}</strong></article>"
        "</div>"
        "<div class='params-block'><span class='section-title'>Best hyperparameters</span>"
        f"<div class='chips'>{params_html}</div></div>"
        "<div class='params-block'><span class='section-title'>Latest evaluation</span>"
        f"<div class='chips'>{eval_html}</div></div>"
        f"{infer_hint}"
        f"<form class='upload-form' action='/upload' method='post' enctype='multipart/form-data'>"
        f"<input type='hidden' name='student' value='{html.escape(snapshot['student'])}'>"
        "<label>Upload dataset<input type='file' name='file' accept='.csv,.txt'></label>"
        "<button type='submit'>Upload</button>"
        "</form>"
        "<div class='artifact-grid'>"
        f"<div><h3>Datasets</h3>{render_artifact_list(snapshot['student'], snapshot['datasets'])}</div>"
        f"<div><h3>Models</h3>{render_artifact_list(snapshot['student'], snapshot['models'])}</div>"
        f"<div><h3>Evaluations</h3>{render_artifact_list(snapshot['student'], snapshot['evaluations'])}</div>"
        "</div></section>"
    )


def dashboard_html(user: User) -> str:
    users = load_users()
    students = student_names(users)
    visible = students if user.role == "admin" else [user.namespace]
    cards = "".join(render_card(student_snapshot(student)) for student in visible if student)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Private Cloud Portal</title>
  <style>
    :root {{
      --ink: #0f172a;
      --muted: #475569;
      --line: #d9e3ee;
      --panel: rgba(255,255,255,0.93);
      --accent: #045d5d;
      --accent-soft: #dff5f3;
      --paper: #f3f7fb;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: "IBM Plex Sans", "Segoe UI", sans-serif;
      color: var(--ink);
      background:
        radial-gradient(circle at top right, rgba(255, 207, 139, 0.28), transparent 28%),
        radial-gradient(circle at top left, rgba(4, 93, 93, 0.14), transparent 24%),
        linear-gradient(180deg, #fbfdff 0%, var(--paper) 100%);
    }}
    main {{ max-width: 1380px; margin: 0 auto; padding: 36px 20px 64px; }}
    .hero {{
      border: 1px solid var(--line);
      border-radius: 28px;
      padding: 28px;
      background: linear-gradient(135deg, rgba(255,255,255,0.96), rgba(236,245,255,0.92));
      box-shadow: 0 24px 64px rgba(15, 23, 42, 0.08);
    }}
    .hero-top {{
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
    }}
    h1 {{ margin: 0 0 8px; font-size: clamp(2rem, 4vw, 3rem); }}
    .hero p {{ margin: 0; color: var(--muted); max-width: 900px; line-height: 1.6; }}
    .hero-top a {{
      text-decoration: none;
      border: 1px solid var(--line);
      padding: 10px 14px;
      border-radius: 999px;
      background: white;
      color: var(--ink);
    }}
    .workflow {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
      margin-top: 20px;
    }}
    .workflow div {{
      border-radius: 18px;
      border: 1px solid var(--line);
      background: rgba(255,255,255,0.88);
      padding: 14px 16px;
    }}
    .students {{ display: grid; gap: 18px; margin-top: 24px; }}
    .student-card {{
      padding: 22px;
      border-radius: 24px;
      border: 1px solid var(--line);
      background: var(--panel);
      box-shadow: 0 18px 48px rgba(15, 23, 42, 0.08);
    }}
    .student-header {{
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
    }}
    .student-header h2 {{ margin: 0 0 4px; }}
    .student-header p {{ margin: 0; color: var(--muted); }}
    .actions {{
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }}
    .actions a {{
      text-decoration: none;
      background: var(--accent-soft);
      color: var(--accent);
      padding: 10px 12px;
      border-radius: 999px;
      font-weight: 600;
    }}
    .action-disabled {{
      padding: 10px 12px;
      border-radius: 999px;
      font-weight: 600;
      background: #eef2f7;
      color: #64748b;
      cursor: not-allowed;
    }}
    .path-tip {{
      margin: 16px 0 0;
      color: var(--muted);
      line-height: 1.6;
    }}
    .path-tip code {{
      background: rgba(4, 93, 93, 0.08);
      padding: 2px 6px;
      border-radius: 8px;
      color: var(--accent);
    }}
    .quickstart {{
      margin-top: 14px;
      border: 1px solid var(--line);
      border-radius: 16px;
      padding: 12px 14px;
      background: rgba(255,255,255,0.82);
    }}
    .quickstart summary {{
      cursor: pointer;
      font-weight: 700;
    }}
    .quickstart pre {{
      margin: 12px 0 0;
      padding: 12px;
      border-radius: 14px;
      background: #0f172a;
      color: #e2e8f0;
      overflow-x: auto;
      font-size: 0.92rem;
      line-height: 1.55;
    }}
    .stats {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 12px;
      margin: 18px 0;
    }}
    .stats article {{
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 14px;
      background: rgba(255,255,255,0.82);
    }}
    .label {{
      display: block;
      color: var(--muted);
      font-size: 0.88rem;
      margin-bottom: 6px;
    }}
    .params-block {{
      margin-top: 14px;
      padding-top: 14px;
      border-top: 1px solid var(--line);
    }}
    .section-title {{
      display: block;
      font-weight: 700;
      margin-bottom: 10px;
    }}
    .chips {{
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }}
    .chip {{
      padding: 8px 10px;
      border-radius: 999px;
      background: rgba(4, 93, 93, 0.08);
      color: var(--accent);
      font-size: 0.92rem;
    }}
    .upload-form {{
      display: flex;
      gap: 10px;
      align-items: end;
      flex-wrap: wrap;
      margin-top: 18px;
    }}
    .upload-form label {{
      display: grid;
      gap: 6px;
      color: var(--muted);
    }}
    .upload-form button {{
      border: none;
      background: var(--accent);
      color: white;
      border-radius: 12px;
      padding: 11px 16px;
      cursor: pointer;
    }}
    .artifact-grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 16px;
      margin-top: 20px;
    }}
    .artifact-list {{
      list-style: none;
      margin: 0;
      padding: 0;
      display: grid;
      gap: 10px;
    }}
    .artifact-list li {{
      border: 1px solid var(--line);
      border-radius: 16px;
      padding: 12px;
      display: grid;
      gap: 4px;
      background: rgba(255,255,255,0.84);
    }}
    .artifact-list a {{ color: var(--accent); text-decoration: none; }}
    .empty {{ color: var(--muted); }}
    .hint {{
      margin: 16px 0 0;
      color: var(--muted);
    }}
    @media (max-width: 720px) {{
      .hero-top, .student-header {{ flex-direction: column; }}
    }}
  </style>
</head>
<body>
  <main>
    <section class="hero">
      <div class="hero-top">
        <div>
          <h1>Private Cloud MLOps Portal</h1>
          <p>This lab runs on the laptop LAN IP with real Kubernetes services, MetalLB, Istio ingress, Katib optimization, MinIO object storage, dedicated student workspaces, training jobs, evaluation jobs, and per-student model-serving endpoints.</p>
        </div>
        <a href="/logout">Log Out</a>
      </div>
      <div class="workflow">
        <div><strong>1. Upload dataset</strong><br>Object storage keeps datasets and artifacts per student.</div>
        <div><strong>2. Edit code</strong><br>Open Workspace and edit <code>project.yaml</code> plus the Python files under <code>student_lab/</code>.</div>
        <div><strong>3. Tune with Katib</strong><br>Katib runs namespace-scoped trials per student.</div>
        <div><strong>4. Train and evaluate</strong><br>Jobs run on selected compute profiles.</div>
        <div><strong>5. Serve and infer</strong><br>Each student gets an inference API endpoint.</div>
      </div>
    </section>
    <section class="students">{cards}</section>
  </main>
</body>
</html>"""


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/", response_class=HTMLResponse)
def root(request: Request):
    user = get_current_user(request)
    if user is None:
        return RedirectResponse("/login", status_code=302)
    return RedirectResponse("/dashboard", status_code=302)


@app.get("/login", response_class=HTMLResponse)
def login_form() -> str:
    return """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Login</title>
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      background:
        radial-gradient(circle at top left, rgba(0, 122, 116, 0.16), transparent 25%),
        radial-gradient(circle at bottom right, rgba(255, 193, 119, 0.22), transparent 30%),
        linear-gradient(180deg, #f8fbff 0%, #eef4f9 100%);
      font-family: "IBM Plex Sans", "Segoe UI", sans-serif;
      color: #0f172a;
    }
    form {
      width: min(92vw, 380px);
      padding: 28px;
      border-radius: 24px;
      background: rgba(255,255,255,0.94);
      box-shadow: 0 24px 60px rgba(15, 23, 42, 0.10);
      border: 1px solid #d7e3ef;
      display: grid;
      gap: 14px;
    }
    h1 { margin: 0 0 6px; }
    p { margin: 0; color: #475569; line-height: 1.5; }
    label { display: grid; gap: 6px; color: #334155; }
    input {
      border-radius: 12px;
      border: 1px solid #c7d4e1;
      padding: 12px;
      font: inherit;
    }
    button {
      border: none;
      border-radius: 12px;
      padding: 12px;
      background: #045d5d;
      color: white;
      font: inherit;
      cursor: pointer;
    }
  </style>
</head>
<body>
  <form method="post" action="/login">
    <div>
      <h1>Private Cloud Login</h1>
      <p>Use one of the default student credentials or the admin account.</p>
    </div>
    <label>Username<input name="username" required></label>
    <label>Password<input name="password" type="password" required></label>
    <button type="submit">Sign In</button>
  </form>
</body>
</html>"""


@app.post("/login")
def login(username: str = Form(...), password: str = Form(...)):
    user = load_users().get(username)
    if user is None or user.password != password:
        raise HTTPException(status_code=401, detail="invalid credentials")
    response = RedirectResponse("/dashboard", status_code=302)
    token = serializer().dumps({"username": user.username})
    response.set_cookie(SESSION_COOKIE, token, httponly=True, samesite="lax")
    return response


@app.get("/logout")
def logout():
    response = RedirectResponse("/login", status_code=302)
    response.delete_cookie(SESSION_COOKIE)
    return response


@app.get("/dashboard", response_class=HTMLResponse)
def dashboard(request: Request):
    user = require_user(request)
    return dashboard_html(user)


@app.post("/upload")
async def upload_dataset(request: Request, student: str = Form(...), file: UploadFile = File(...)):
    user = require_user(request)
    if not can_access(user, student):
        raise HTTPException(status_code=403, detail="forbidden")
    payload = await file.read()
    filename = Path(file.filename or "dataset.csv").name
    key = f"datasets/{filename}"
    s3_client().put_object(Bucket=student, Key=key, Body=payload, ContentType=file.content_type or "text/csv")
    return RedirectResponse("/dashboard", status_code=302)


@app.get("/files/{student}/{path:path}")
def get_file(request: Request, student: str, path: str):
    user = require_user(request)
    if not can_access(user, student):
        raise HTTPException(status_code=403, detail="forbidden")
    try:
        response = s3_client().get_object(Bucket=student, Key=path)
    except ClientError as exc:
        raise HTTPException(status_code=404, detail="not found") from exc
    content_type = response.get("ContentType") or "application/octet-stream"
    return StreamingResponse(response["Body"], media_type=content_type)
