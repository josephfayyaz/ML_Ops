from datetime import datetime, timezone
import html
import os

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse
from kubernetes import client, config
from kubernetes.config.config_exception import ConfigException


GROUP = "kubeflow.org"
VERSION = "v1beta1"
EXPERIMENTS_PLURAL = "experiments"
NAMESPACE = os.getenv("KATIB_NAMESPACE", "katib-experiments")

app = FastAPI(title="katib-results-dashboard", version="0.1.0")
_KUBE_READY = False


def ensure_kube_config() -> None:
    global _KUBE_READY
    if _KUBE_READY:
        return
    try:
        config.load_incluster_config()
    except ConfigException:
        config.load_kube_config()
    _KUBE_READY = True


def parse_experiment(item: dict) -> dict:
    metadata = item.get("metadata", {})
    spec = item.get("spec", {})
    status = item.get("status", {})
    objective = spec.get("objective", {})
    metric_name = objective.get("objectiveMetricName", "metric")
    objective_type = objective.get("type", "maximize")
    best = status.get("currentOptimalTrial", {})
    metrics = best.get("observation", {}).get("metrics", [])
    best_metric = None
    for metric in metrics:
        if metric.get("name") == metric_name:
            key = "max" if objective_type == "maximize" else "min"
            best_metric = float(metric.get(key, metric.get("latest", 0)))
            break
    params = {
        assignment.get("name"): assignment.get("value")
        for assignment in best.get("parameterAssignments", [])
    }
    return {
        "name": metadata.get("name", ""),
        "created": metadata.get("creationTimestamp", ""),
        "status": next(
            (
                condition.get("type")
                for condition in reversed(status.get("conditions", []))
                if condition.get("status") == "True"
            ),
            "Unknown",
        ),
        "project": (
            "house-prices"
            if metadata.get("name", "").startswith("house-prices")
            else "iris"
            if metadata.get("name", "").startswith("iris")
            else "other"
        ),
        "objectiveMetricName": metric_name,
        "objectiveType": objective_type,
        "bestTrialName": best.get("bestTrialName", "-"),
        "bestMetric": best_metric,
        "trials": status.get("trials", 0),
        "trialsSucceeded": status.get("trialsSucceeded", 0),
        "parameters": params,
    }


def fetch_experiments() -> list[dict]:
    ensure_kube_config()
    api = client.CustomObjectsApi()
    response = api.list_namespaced_custom_object(
        group=GROUP,
        version=VERSION,
        namespace=NAMESPACE,
        plural=EXPERIMENTS_PLURAL,
    )
    experiments = [parse_experiment(item) for item in response.get("items", [])]
    return sorted(experiments, key=lambda item: item["created"], reverse=True)


def format_timestamp(value: str) -> str:
    if not value:
        return "-"
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    local = dt.astimezone(timezone.utc)
    return local.strftime("%Y-%m-%d %H:%M UTC")


def format_metric(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value:.4f}" if value < 1000 else f"{value:,.2f}"


def metric_width(items: list[dict], current: dict) -> float:
    candidates = [item["bestMetric"] for item in items if item["bestMetric"] is not None]
    if not candidates or current["bestMetric"] is None:
        return 0.0
    if current["objectiveType"] == "maximize":
        return max(12.0, 100.0 * current["bestMetric"] / max(candidates))
    best = min(candidates)
    return max(12.0, 100.0 * best / current["bestMetric"])


def render_dashboard(experiments: list[dict]) -> str:
    groups: dict[tuple[str, str], list[dict]] = {}
    for item in experiments:
        key = (item["objectiveMetricName"], item["objectiveType"])
        groups.setdefault(key, []).append(item)

    cards = {
        "total": len(experiments),
        "succeeded": sum(item["status"] == "Succeeded" for item in experiments),
        "running": sum(item["status"] == "Running" for item in experiments),
        "projects": len({item["project"] for item in experiments}),
    }

    sections: list[str] = []
    for (metric_name, objective_type), items in groups.items():
        rows: list[str] = []
        for item in items:
            params = "<br>".join(
                f"<span class='param'>{html.escape(name)}={html.escape(str(value))}</span>"
                for name, value in item["parameters"].items()
            ) or "-"
            width = metric_width(items, item)
            rows.append(
                "<tr>"
                f"<td><strong>{html.escape(item['name'])}</strong><div class='subtle'>{html.escape(item['project'])}</div></td>"
                f"<td>{html.escape(item['status'])}</td>"
                f"<td>{html.escape(item['bestTrialName'])}</td>"
                f"<td><div class='metric'>{format_metric(item['bestMetric'])}</div>"
                f"<div class='bar'><span style='width:{width:.1f}%'></span></div></td>"
                f"<td>{params}</td>"
                f"<td>{item['trialsSucceeded']}/{item['trials']}</td>"
                f"<td>{format_timestamp(item['created'])}</td>"
                "</tr>"
            )
        sections.append(
            "<section class='panel'>"
            f"<h2>{html.escape(metric_name)} ({html.escape(objective_type)})</h2>"
            "<table><thead><tr><th>Experiment</th><th>Status</th><th>Best Trial</th>"
            "<th>Best Metric</th><th>Best Parameters</th><th>Trials</th><th>Created</th>"
            "</tr></thead><tbody>"
            + "".join(rows)
            + "</tbody></table></section>"
        )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Katib Results Dashboard</title>
  <style>
    :root {{
      --ink: #10233a;
      --muted: #5d7288;
      --line: #d7e2ec;
      --paper: #f4f7fb;
      --panel: #ffffff;
      --accent: #0f766e;
      --accent-soft: #d8f3ef;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--ink);
      background:
        radial-gradient(circle at top left, #dff3ff 0, transparent 28%),
        radial-gradient(circle at top right, #fff1d8 0, transparent 24%),
        var(--paper);
    }}
    main {{ max-width: 1240px; margin: 0 auto; padding: 40px 24px 80px; }}
    h1 {{ margin: 0 0 8px; font-size: 2.2rem; }}
    p.lead {{ margin: 0 0 28px; color: var(--muted); max-width: 780px; }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 14px;
      margin-bottom: 24px;
    }}
    .card, .panel {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 18px;
      box-shadow: 0 14px 35px rgba(16, 35, 58, 0.08);
    }}
    .card {{ padding: 18px 20px; }}
    .card .label {{ color: var(--muted); font-size: 0.92rem; }}
    .card .value {{ font-size: 2rem; font-weight: 700; margin-top: 6px; }}
    .panel {{ padding: 18px 18px 8px; margin-top: 16px; overflow-x: auto; }}
    h2 {{ margin: 4px 0 16px; font-size: 1.15rem; }}
    table {{ width: 100%; border-collapse: collapse; min-width: 980px; }}
    th, td {{ text-align: left; padding: 12px 10px; border-top: 1px solid var(--line); vertical-align: top; }}
    th {{ border-top: 0; color: var(--muted); font-size: 0.88rem; font-weight: 600; }}
    .subtle {{ color: var(--muted); font-size: 0.86rem; margin-top: 4px; }}
    .metric {{ font-weight: 700; }}
    .bar {{
      width: 180px;
      height: 10px;
      background: #edf3f8;
      border-radius: 999px;
      margin-top: 8px;
      overflow: hidden;
    }}
    .bar span {{
      display: block;
      height: 100%;
      background: linear-gradient(90deg, #0f766e, #22c55e);
      border-radius: 999px;
    }}
    .param {{
      display: inline-block;
      margin: 0 6px 6px 0;
      padding: 4px 8px;
      border-radius: 999px;
      background: var(--accent-soft);
      font-size: 0.84rem;
    }}
    footer {{
      margin-top: 18px;
      color: var(--muted);
      font-size: 0.9rem;
    }}
  </style>
</head>
<body>
  <main>
    <h1>Katib Results Dashboard</h1>
    <p class="lead">Presentation-friendly summary of Katib experiments, best trials, and best hyperparameters across the Iris and house-prices demos.</p>
    <div class="grid">
      <div class="card"><div class="label">Experiments</div><div class="value">{cards['total']}</div></div>
      <div class="card"><div class="label">Succeeded</div><div class="value">{cards['succeeded']}</div></div>
      <div class="card"><div class="label">Running</div><div class="value">{cards['running']}</div></div>
      <div class="card"><div class="label">Projects</div><div class="value">{cards['projects']}</div></div>
    </div>
    {''.join(sections) or "<section class='panel'><p>No experiments found.</p></section>"}
    <footer>Namespace: {html.escape(NAMESPACE)}. Data is read live from Katib experiment CRDs via the Kubernetes API.</footer>
  </main>
</body>
</html>"""


@app.get("/api/experiments")
def experiments_api() -> JSONResponse:
    return JSONResponse(fetch_experiments())


@app.get("/", response_class=HTMLResponse)
def index() -> HTMLResponse:
    experiments = fetch_experiments()
    return HTMLResponse(render_dashboard(experiments))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("mlops_results_dashboard.app:app", host="0.0.0.0", port=8000)
