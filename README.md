# eb-deploy-boilerplate

Deployment boilerplate for AWS Elastic Beanstalk using Docker Compose. CI builds and tests a Docker image once, pushes to ECR, creates an Elastic Beanstalk application version, and updates or creates the target environment idempotently.

## What's Included

| File | Purpose |
|------|---------|
| `templates/Dockerfile.python` | Multi-stage Python image (gunicorn, non-root user, health check) |
| `templates/Dockerfile.node` | Multi-stage Node.js image (npm ci, non-root user, health check) |
| `templates/docker-compose.yml.tmpl` | Compose template with service-name-based defaults and ECR image fallback |
| `templates/.elasticbeanstalk/config.yml.tmpl` | Elastic Beanstalk CLI metadata (app/env/region defaults) |
| `templates/.github/workflows/elastic-beanstalk-deploy.yml` | CI + deploy: build, test, push to ECR, create app version, create/update EB environment |
| `templates/.dockerignore` | Standard ignore patterns for Docker builds |
| `templates/.env.example.*` | Stack-specific environment variable examples |
| `scaffold.sh` | Copies and customizes templates into a target project |

## How It Works

```
Push to main
    |
    v
GitHub Actions
    |-- checkout code
    |-- build Docker image
    |-- run tests against the built image
    |-- push image to ECR
    |-- create EB source bundle (docker-compose + IMAGE_URI)
    |-- create EB application version
    |-- create app/env if missing, else update existing env
    |
    v
Elastic Beanstalk
    |-- pulls prebuilt ECR image
    |-- starts container(s) from docker-compose.yml
    |-- health checks /health
    |-- serves traffic
```

## Naming and Idempotency

The deploy workflow derives the canonical name from the first service key in `docker-compose.yml`.

- Default app name: `<service-name>`
- Default environment name: `<service-name>-env`

For every deploy:

1. Resolve EB application by name and create it if missing.
2. Resolve EB environment (scoped to the app) and create it if missing.
3. Create a new application version and apply it to the resolved environment.

Optional overrides are supported through repository variables:

- `EB_APP_NAME`
- `EB_ENV_NAME`

## Quick Start

### Option A: Via agentic-dev.sh (recommended)

```bash
# Create a new project with deploy infrastructure
agentic-dev.sh repo create my-app --description "My app" --with-deploy --stack python

# Or scaffold into an existing repo
agentic-dev.sh deploy scaffold my-app --stack python
agentic-dev.sh deploy provision my-app
```

### Option B: Standalone

```bash
git clone git@github.com:dndodson/render-deploy-boilerplate.git /tmp/boilerplate

/tmp/boilerplate/scaffold.sh \
  --target /path/to/your/project \
  --name your-service-name \
  --ecr-repo 123456789012.dkr.ecr.us-east-1.amazonaws.com/your-repo \
  --region us-east-1 \
  --stack python
```

## One-Time AWS Setup

### 1. Create ECR Repository

Create (or let workflow create) an ECR repository matching your scaffolded `--ecr-repo` path.

### 2. Create S3 Bucket for EB Artifacts

Elastic Beanstalk application versions are uploaded to S3 before deployment.

### 3. Configure GitHub OIDC Role

Create an IAM role trusted by GitHub OIDC and grant least-privilege permissions for:

- ECR push/pull
- S3 upload/read for the artifact bucket
- Elastic Beanstalk app/env/version operations

### 4. Set GitHub Repository Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `AWS_REGION` | yes | AWS region for ECR and Elastic Beanstalk |
| `AWS_ROLE_ARN` | yes | IAM role ARN assumed via GitHub OIDC |
| `EB_ARTIFACTS_BUCKET` | yes | S3 bucket for EB application bundles |
| `EB_APP_NAME` | no | Override default app name derived from compose service |
| `EB_ENV_NAME` | no | Override default env name derived from compose service |

## Health Check Endpoint

Both Dockerfile templates include a health check to `/health`. Your app must return HTTP 200 on that endpoint.

**Python (Flask example)**:
```python
@app.route('/health')
def health():
    return {'status': 'ok'}
```

**Node (Express example)**:
```javascript
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});
```

## Customizing

### Dockerfile

- **Python**: change `gunicorn` command, worker count, or switch to `uvicorn`.
- **Node**: change entrypoint (`src/index.js`) or add build steps.
- **Both**: adjust system dependencies and health check path.

### docker-compose.yml

- Set additional environment variables.
- Add extra services (the first service key controls default EB naming).
- Keep the `image: ${IMAGE_URI:-...}` pattern so CI can inject immutable image tags.

### CI Workflow

- Customize tests with `TEST_CMD`.
- Add notifications after deploy.
- Add branch-specific logic for staging/production patterns.
