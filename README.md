# render-deploy-boilerplate

Production-grade deployment boilerplate for [Render](https://render.com). CI builds and pushes Docker images to GitHub Container Registry (ghcr.io), then Render pulls the prebuilt image -- no double builds, no Render GitHub App needed.

## What's Included

| File | Purpose |
|------|---------|
| `templates/Dockerfile.python` | Multi-stage Python image (gunicorn, non-root user, health check) |
| `templates/Dockerfile.node` | Multi-stage Node.js image (npm ci, non-root user, health check) |
| `templates/render.yaml.tmpl` | Render Blueprint for image-backed service |
| `templates/.github/workflows/render-deploy.yml` | CI + deploy: build, test, push to ghcr.io, trigger Render |
| `templates/.dockerignore` | Standard ignore patterns for Docker builds |
| `templates/.env.example` | Template environment variables |
| `scaffold.sh` | Copies and customizes templates into a target project |

## How It Works

```
Push to main
    |
    v
GitHub Actions
    |-- checkout code
    |-- build Docker image (linux/amd64)
    |-- run tests against the image
    |-- push image to ghcr.io/<org>/<repo>:<sha>
    |-- trigger Render deploy with image ref
    |
    v
Render
    |-- pull prebuilt image from ghcr.io
    |-- start container
    |-- health check /health
    |-- route traffic
```

The image is built exactly **once** in GitHub Actions. Render never clones your repo or builds anything -- it only pulls and runs the prebuilt image. This means:

- No Render GitHub App installation needed (even for private repos)
- CI tests run against the exact image that gets deployed
- Build only happens once
- Full control over the build pipeline in GitHub Actions

## Quick Start

### Option A: Via agentic-dev.sh (recommended)

```bash
# Create a new project with full deploy infrastructure
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
  --gh-repo climatecentral-ai/your-repo \
  --stack python
```

## One-Time Setup

### 1. Render API Key

1. Go to [Render Dashboard](https://dashboard.render.com/) > Account Settings > API Keys
2. Create a key and add to `$OPENCLAW/.env`:
   ```
   RENDER_API_KEY=rnd_xxxxx
   ```

### 2. GitHub Organization Secret

Set `RENDER_API_KEY` as an org secret on `climatecentral-ai`:

```bash
gh secret set RENDER_API_KEY --org climatecentral-ai --visibility all --body "$RENDER_API_KEY"
```

### 3. GHCR Registry Credential in Render

Render needs credentials to pull private images from ghcr.io:

1. Create a GitHub Personal Access Token with `read:packages` scope at [github.com/settings/tokens/new](https://github.com/settings/tokens/new?description=render-ghcr&scopes=read:packages)
2. In Render Dashboard > Workspace Settings > Container Registry Credentials, click "Add credential":
   - **Name**: `ghcr-climatecentral-ai`
   - **Registry**: GitHub Container Registry
   - **Username**: your GitHub username
   - **Personal Access Token**: the token from step 1

This credential is reused across all services.

## Secrets Architecture

| Secret | Scope | Set by |
|--------|-------|--------|
| `RENDER_API_KEY` | GitHub org secret (`climatecentral-ai`) | One-time: `gh secret set --org` |
| `RENDER_SERVICE_ID` | Per-repo GitHub secret | Automated by `deploy provision` |
| `GITHUB_TOKEN` | Automatic (GitHub Actions) | GitHub provides this automatically |
| `ghcr-climatecentral-ai` | Render registry credential | One-time: Render Dashboard |

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

## Customizing

### Dockerfile

- **Python**: Change `gunicorn` to `uvicorn` for async apps, adjust worker count
- **Node**: Change `src/index.js` entry point, add TypeScript build steps
- **Both**: Add system deps in builder stage, adjust health check path

### render.yaml

Change plan, region, add env vars, databases, workers. See [Render Blueprint docs](https://render.com/docs/blueprint-spec).

### CI Workflow

- Add more test steps in the `build` job
- Set `TEST_CMD` env var to customize what runs in the test step
- Add notifications (Slack, email) to the `deploy` job
- Add environment-specific deploys (staging vs production)
