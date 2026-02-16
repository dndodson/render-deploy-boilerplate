# render-deploy-boilerplate

Production-grade deployment boilerplate for [Render](https://render.com). Provides Dockerfile templates, a `render.yaml` Blueprint, and a GitHub Actions workflow that triggers deploys on push to `main`.

## What's Included

| File | Purpose |
|------|---------|
| `templates/Dockerfile.python` | Multi-stage Python image (gunicorn, non-root user, health check) |
| `templates/Dockerfile.node` | Multi-stage Node.js image (npm ci, non-root user, health check) |
| `templates/render.yaml.tmpl` | Render Blueprint with `__SERVICE_NAME__` and `__PORT__` placeholders |
| `templates/.github/workflows/render-deploy.yml` | GitHub Actions workflow — triggers Render deploy via API |
| `templates/.dockerignore` | Standard ignore patterns for Docker builds |
| `templates/.env.example` | Template environment variables |
| `scaffold.sh` | Copies and customizes templates into a target project |

## Quick Start

### Option A: Via agentic-dev.sh (recommended)

If you're using the OpenClaw agentic-dev workflow, deploy scaffolding is built in:

```bash
# Scaffold deploy files into an existing repo
agentic-dev.sh deploy scaffold <repo> --stack python

# Provision the Render service and set GitHub secrets automatically
agentic-dev.sh deploy provision <repo>

# Or do everything at once when creating a new project
agentic-dev.sh repo create my-app --description "My app" --with-deploy --stack python
```

### Option B: Standalone

```bash
# Clone this repo
git clone git@github.com:dndodson/render-deploy-boilerplate.git /tmp/boilerplate

# Scaffold into your project
/tmp/boilerplate/scaffold.sh \
  --target /path/to/your/project \
  --name your-service-name \
  --stack python  # or node
```

## One-Time Setup

You only need to do this once, not per project.

### 1. Render API Key

1. Go to [Render Dashboard](https://dashboard.render.com/) > Account Settings > API Keys
2. Click "Create API Key" and copy the key (`rnd_...`)
3. Add it to your OpenClaw `.env` file:
   ```
   RENDER_API_KEY=rnd_xxxxx
   ```

### 2. GitHub Organization Secret

`RENDER_API_KEY` is set as an **organization-level secret** on the `climatecentral-ai` GitHub org. This makes it available to all repos in the org without setting it per-repo.

```bash
gh secret set RENDER_API_KEY --org climatecentral-ai --visibility all --body "$RENDER_API_KEY"
```

Only `RENDER_SERVICE_ID` needs to be set per-repo (automated by `deploy provision`).

Repos must live under the `climatecentral-ai` org for the org secret to work. Using `--with-deploy` on `repo create` defaults to this org automatically.

## How It Works

```
Push to main
    │
    ▼
GitHub Actions (.github/workflows/render-deploy.yml)
    │
    ▼
POST https://api.render.com/v1/services/{SERVICE_ID}/deploys
    │
    ▼
Render builds Dockerfile and deploys
```

1. **On push to `main`**, the GitHub Actions workflow fires
2. It calls the Render API to trigger a deploy using two secrets:
   - `RENDER_API_KEY` — org-level secret on `climatecentral-ai`, authenticates the API request
   - `RENDER_SERVICE_ID` — per-repo secret, identifies which Render service to deploy
3. Render pulls the latest code, builds the Docker image, and deploys it

## Customizing

### Dockerfile

The scaffolded `Dockerfile` is a starting point. Common customizations:

- **Python**: Change `gunicorn` to `uvicorn` for async apps, adjust worker count
- **Node**: Change `src/index.js` entry point, add build steps for TypeScript
- **Both**: Add system dependencies in the builder stage, adjust health check paths

### render.yaml

The `render.yaml` file is a Render Blueprint. After scaffolding, you can:

- Change the `plan` (free, starter, standard, pro)
- Change the `region` (oregon, ohio, virginia, frankfurt, singapore)
- Add environment variables
- Add persistent disks
- Add additional services (workers, cron jobs, databases)

See the [Render Blueprint docs](https://render.com/docs/blueprint-spec) for the full specification.

### GitHub Actions Workflow

The workflow is minimal by design. You can extend it with:

- Build/test steps before the deploy trigger
- Deployment status notifications (Slack, email)
- Environment-specific deploys (staging vs production)

## Health Check Endpoint

Both Dockerfile templates include a health check that hits `/health`. Your application must expose this endpoint:

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

Render also uses `healthCheckPath` in `render.yaml` for zero-downtime deploys.
