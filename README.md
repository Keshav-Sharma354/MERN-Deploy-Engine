# MERN Deploy Engine: DevSecOps Edition 🛡️🚀

Welcome to the **MERN Deploy Engine**, a modern, containerized full-stack application leveraging the MERN stack (MongoDB, Express.js, React, Node.js). 

As a DevOps Engineer, I've transformed this standard MERN application into a robust, shift-left **DevSecOps** environment. This repository doesn't just run code—it ensures that every commit is automatically tested, scanned for vulnerabilities, and validated against strict security benchmarks before it's allowed anywhere near production.

---

## 🏗️ Architecture & Containerization 

The application is fully containerized for consistency across all environments (Dev/Test/Prod).

- **Frontend:** React application served via a custom Dockerized container on port `5173`.
- **Backend:** Node/Express REST API served via Docker on port `5050`.
- **Database:** MongoDB container with local volume mounting for data persistence on port `27017`.

### Local Development Setup

To spin up the entire cluster locally with a single command, ensure Docker and Docker Compose are installed on your machine.

```bash
# Starts the frontend, backend, and MongoDB network securely
docker compose up -d
```

*(Alternatively, you can build and run individual components. See the legacy setup instructions below.)*

---

## 🔒 DevSecOps CI/CD Pipeline

Security is treated as a first-class citizen here. We utilize **GitHub Actions** to enforce an automated, multi-tiered security pipeline on every Push and Pull Request to the `main` branch. 

Our pipeline is configured to **automatically fail the build** if critical vulnerabilities or code smells exceed our defined thresholds.

### 1. Static Application Security Testing (SAST)
We use **SonarQube** to analyze source code for bugs, vulnerabilities, and code smells.
- Automatically scans the source code natively.
- Enforces a rigorous **Quality Gate**. If the code fails the gate, the pipeline breaks.

### 2. Software Composition Analysis (SCA)
We rely on **Aqua Trivy** to perform dependency vulnerability scanning.
- Scans both `/mern/frontend` and `/mern/backend` `package.json`/`package-lock.json` dependency trees.
- The pipeline intentionally triggers an exit-code `1` (failing the build) if **CRITICAL** or **HIGH** CVEs are detected in third-party libraries.

### 3. Dynamic Application Security Testing (DAST)
We deploy a live ephemeral environment using Docker Compose directly inside the CI runner to aggressively test the running application via **OWASP ZAP**.
- Waits for the application's React frontend and API to become healthy.
- Executes an OWASP ZAP Full Scan against the live local cluster.
- Instantly breaks the build if active vulnerabilities are detected during runtime.

### 📊 Security Reports Generation
Every CI run automatically archives its findings for audit purposes. You can download the generated `trivy-frontend-report.txt`, `trivy-backend-report.txt`, and the ZAP HTML reports directly from the GitHub Actions **Artifacts** tab.

---

## ⚙️ CI/CD Pre-Requisites (GitHub Secrets)

To make the pipeline function correctly in your own fork, you will need to populate the following GitHub Repository Secrets (`Settings > Secrets and variables > Actions`):
- `SONAR_TOKEN`: Authentication token generated from your SonarQube / SonarCloud dashboard.
- `SONAR_HOST_URL`: The URL of your SonarQube instance (e.g., `https://sonarcloud.io` or your self-hosted URL).

---

## ☸️ Advanced Kubernetes DevSecOps Cluster

In addition to Docker development, this project ships with a fully hardened Kubernetes directory (`kubernetes/`) representing production-ready deployments.

### Implemented K8s Security Controls 🛡️
1. **Pod Security Standards:** Implementations of `#runAsNonRoot` and total capability drops across `backend`, `frontend`, and `mongodb` deployments.
2. **Strict RBAC:** Principle-of-least-privilege `Role` and `RoleBinding` to lock down container permissions.
3. **Zero-Trust Network Policies:** Traffic is default-denied across the namespace. We enforce whitelist-only transit (`frontend` -> `backend` -> `mongodb`).
4. **Runtime Security with Falco:** Helm values configured (`kubernetes/security/falco-values.yaml`) to monitor kernel syscalls and alert on anomalous behaviors (e.g., unexpected shell executions, rogue database access, files written into read-only mounts).
5. **Prometheus Monitoring + Alertmanager:** Custom `PrometheusRule` thresholds (`kubernetes/monitoring/prometheus-alerts.yaml`) deployed to monitor for CPU anomalies, crash loop backoffs, and sustained HTTP 500 error floods.

**Deployment Instructions (Minikube / k3s / EKS):**
```bash
# 1. Apply Namespace and strict RBAC
kubectl apply -f kubernetes/app/1-namespace-rbac.yaml

# 2. Block all unknown traffic via Network Policies
kubectl apply -f kubernetes/app/2-network-policies.yaml

# 3. Deploy the Hardened Application Set
kubectl apply -f kubernetes/app/3-deployments.yaml
```

---

## 🛠️ Legacy Manual Docker Setup

If you prefer spinning up containers manually instead of using Docker Compose:

1. **Create the network:**  
   `docker network create demo`
2. **Database:**  
   `docker run --network=demo --name mongodb -d -p 27017:27017 -v ~/opt/data:/data/db mongo:latest`
3. **Frontend:**  
   `cd mern/frontend && docker build -t mern-frontend .`  
   `docker run --name=frontend --network=demo -d -p 5173:5173 mern-frontend`
4. **Backend:**  
   `cd mern/backend && docker build -t mern-backend .`  
   `docker run --name=backend --network=demo -d -p 5050:5050 mern-backend`
