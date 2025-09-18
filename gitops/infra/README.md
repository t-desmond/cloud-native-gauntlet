# Infrastructure Configuration - Kubernetes Manifests

This folder contains infrastructure-level manifests and references used by GitOps (ArgoCD) to manage the cluster and applications.

## Components

- ArgoCD (namespace `argocd`)
- CNPG Operator (namespace `cnpg-system`)
- Linkerd (via ArgoCD application)
- Application definitions for database, Keycloak, and Task API

## Access

- ArgoCD UI: `http://argocd.local` (Traefik)
  - Initial admin password:
    ```bash
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
    ```
- Hostname mappings are added by `scripts/deploy.sh` to `/etc/hosts`.

## GitOps Applications

- Applied via `scripts/deploy.sh`:
  - Linkerd
  - Database (CNPG)
  - Keycloak
  - Task API
  - Grafana
  - Prometheus

## Gitea and runner (current)

- Gitea is deployed under namespace `gitea`.
- The Actions runner is deployed from `apps/gitops/gitea/runner.yaml`.
- The runner registration token is currently provided manually when `scripts/deploy.sh` prompts for it; the script patches the Secret in `runner.yaml` and applies the Deployment.
