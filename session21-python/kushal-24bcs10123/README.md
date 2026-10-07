# Session 21 – Final DevOps Project: StudyTrack

**Name:** Kushal Talati  
**Enrollment No:** 24BCS10123  
**Repository / branch:** [`kushaltalati/devops-heros`](https://github.com/kushaltalati/devops-heros) → branch [`capstone-kushal-s21`](https://github.com/kushaltalati/devops-heros/tree/capstone-kushal-s21/session21-python/kushal-24bcs10123) (the pipeline and Argo CD watch this branch; the same tree is in my sessions 13–21 PR)  
**Pipeline:** [`.github/workflows/24bcs10123-final-project.yml`](https://github.com/kushaltalati/devops-heros/blob/capstone-kushal-s21/.github/workflows/24bcs10123-final-project.yml) – green run: __GREEN_RUN_URL__  
**Images:** `ghcr.io/kushaltalati/studytrack-backend`, `ghcr.io/kushaltalati/studytrack-frontend` (tag `sha-<7 chars>` + `latest`, multi-arch amd64/arm64)  
**Environment:** kind v0.33.0 cluster `kushal-lab` (Kubernetes v1.37.0, 1 control-plane + 2 workers) on Docker Desktop 29.0.1, macOS / Apple Silicon – the same cluster as sessions 9–20, with metrics-server, ingress-nginx, kube-prometheus-stack (ns `monitoring`) and Argo CD (ns `argocd`) already installed from the earlier sessions. Terraform 1.16.4, Helm 3.19, Trivy 0.75, LocalStack 4.0.3.

StudyTrack is my own small application: a study log. You record blocks of study time (subject, topic, minutes, status), mark them done, and the dashboard shows total minutes, progress against a daily goal and a per-subject breakdown. Same shape as the course's TaskBoard reference (FastAPI + PostgreSQL + React, one resource with full CRUD) but my own domain, code and schema.

Every command below was really run; raw output is in [`docs/outputs/`](docs/outputs), browser/terminal captures in [`screenshots/`](screenshots).

```text
kushal-24bcs10123/
├── README.md
├── backend/                 # FastAPI + SQLAlchemy + Alembic, pytest, Dockerfile (non-root)
│   ├── app/                 # config.py db.py models.py schemas.py metrics.py main.py
│   ├── alembic/versions/0001_create_study_entries.py
│   ├── tests/               # conftest.py (sqlite in-memory) + test_api.py (11 tests)
│   └── Dockerfile, entrypoint.sh, requirements*.txt, pytest.ini
├── frontend/                # React + Vite, multi-stage Dockerfile -> nginx-unprivileged
├── docker-compose.yml       # postgres + backend + frontend
├── k8s/namespace.yaml
├── helm/studytrack/         # chart: deployments (probes), services, configmap, secret, pvc+postgres, ingress, hpa, servicemonitor
├── gitops/argocd-application.yaml
├── monitoring/              # kube-prometheus-stack values, PrometheusRule, Grafana dashboard json
├── terraform/               # VPC, 2 public subnets, IGW/route table, security group, S3 (+ EKS module)
├── troubleshooting/         # broken-image, broken-service, broken-config
├── scripts/                 # run-local.sh load-test.sh k8s-verify.sh prom-queries.sh
├── .github/workflows/24bcs10123-final-project.yml   (copy of the root workflow)
├── docs/outputs/            # raw logs, numbered by module
└── screenshots/
```

## Architecture

```text
 developer ── git push ──> GitHub (kushaltalati/devops-heros, branch capstone-kushal-s21)
                                │
                                ▼  GitHub Actions
          test ─┬─ SAST (bandit, semgrep) ─┐
                ├─ SCA  (pip-audit, npm)   ├─ build+push ──> ghcr.io/kushaltalati/studytrack-{backend,frontend}:sha-xxxxxxx
                ├─ secret scan (gitleaks)  │        │
                └─ helm lint/template ─────┘        ▼
                                              trivy gate (HIGH/CRITICAL => fail)
                                                    │
                                                    ▼
                                   deploy job: writes image.tag into helm/studytrack/values.yaml, commits
                                                    │
                       Argo CD (ns argocd) watches the branch/path, auto-sync + self-heal
                                                    │
     ┌──────────────────────────────── kind cluster kushal-lab, namespace studytrack ─────────────────────────┐
     │  Ingress studytrack.local ──/──> Service studytrack-frontend ──> Deployment frontend (nginx, 2 pods)   │
     │        (ingress-nginx)   ──/api──> Service studytrack-backend ──> Deployment backend (uvicorn, 2..6)    │
     │                                                     │  HPA 50% cpu       │ probes: startup/ready/live   │
     │                                                     ▼                    ▼                              │
     │                                        Service studytrack-postgres ──> Deployment postgres + PVC 1Gi    │
     │   ConfigMap studytrack-config  Secret studytrack-db-secret  ServiceMonitor ──> Prometheus ──> Grafana   │
     └────────────────────────────────────────────────────────────────────────────────────────────────────────┘

 terraform/  ──> VPC 10.42.0.0/16, 2 public subnets, IGW, route table, web SG, S3 backups bucket, [EKS module]
                 applied/destroyed against LocalStack (see M7 for why not real AWS)
```

## Rubric map

| Module | What proves it |
|---|---|
| M1 Application | [`backend/app/main.py`](backend/app/main.py) (`/health`, `/ready`, `/metrics`, `GET/POST/PUT/DELETE /api/entries`, `/api/entries/summary`), [`alembic/versions/0001_create_study_entries.py`](backend/alembic/versions/0001_create_study_entries.py), [`frontend/src/App.jsx`](frontend/src/App.jsx), [`docker-compose.yml`](docker-compose.yml); logs [02](docs/outputs/02-api-smoke-test.txt), [03](docs/outputs/03-compose-db-and-nonroot.txt); screenshot [01](screenshots/01-compose-frontend-localhost-3000.png) |
| M2 Testing | [`backend/tests/`](backend/tests) – 11 tests over 7 endpoints, SQLite in-memory via `conftest.py`, [`pytest.ini`](backend/pytest.ini); log [04](docs/outputs/04-pytest-local.txt) + the `Unit tests` job in every run |
| M3 Git/GitHub | this public repo, __COMMIT_COUNT__ commits on the branch (`git log --oneline upstream/main..capstone-kushal-s21`), [`.gitignore`](.gitignore) excludes `.env`, `__pycache__`, `node_modules`, `.venv`, tfstate |
| M4 Docker | [`backend/Dockerfile`](backend/Dockerfile) (uid 10001), [`frontend/Dockerfile`](frontend/Dockerfile) (node build stage → `nginx-unprivileged`, uid 101), [`docker-compose.yml`](docker-compose.yml); logs [01](docs/outputs/01-docker-compose-up.txt), [03](docs/outputs/03-compose-db-and-nonroot.txt) |
| M5 CI/CD | [workflow](.github/workflows/24bcs10123-final-project.yml); green run __GREEN_RUN_URL__; images tagged `sha-<git sha>`; logs [41](docs/outputs/41-ci-run-green.txt), [42](docs/outputs/42-ghcr-images.txt) |
| M6 DevSecOps | trivy on both images with `exit-code: 1` for HIGH/CRITICAL; plus bandit, semgrep, pip-audit, npm audit, gitleaks; logs [06](docs/outputs/06-trivy-local-images.txt), [07](docs/outputs/07-sast-local.txt), [40](docs/outputs/40-ci-run-blocked-by-sca.txt) (a run the SCA gate really blocked) |
| M7 Terraform | [`terraform/`](terraform) incl. [`modules/eks`](terraform/modules/eks), [`terraform.tfvars.example`](terraform/terraform.tfvars.example); logs [20](docs/outputs/20-terraform-init-validate.txt)–[25](docs/outputs/25-terraform-destroy.txt) |
| M8 Kubernetes + Helm | [`k8s/namespace.yaml`](k8s/namespace.yaml), [`helm/studytrack/`](helm/studytrack); logs [50](docs/outputs/50-helm-install.txt), [51](docs/outputs/51-k8s-verify.txt), [52](docs/outputs/52-hpa-load-test.txt); screenshot [10](screenshots/10-ingress-studytrack-local.png) |
| M9 Observability | `/metrics` ([02](docs/outputs/02-api-smoke-test.txt)), ServiceMonitor, [`monitoring/`](monitoring); logs [60](docs/outputs/60-prometheus-targets-and-queries.txt), [61](docs/outputs/61-grafana-dashboard.txt) |
| M10 Docs / demo | this README; GitOps demo in [53](docs/outputs/53-argocd-sync-and-selfheal.txt): push → pipeline → tag bump → Argo CD rollout |

__BODY__
