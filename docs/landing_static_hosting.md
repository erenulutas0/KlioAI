# Landing Static Hosting

KlioAI landing, privacy, terms, and static assets live under:

`site/klioai-landing`

## Hosting Target

Current production hosting is the VPS Caddy service:

- host path: `/opt/vocabmaster/frontend/klioai-site`
- Caddy container path: `/srv/klioai-site`
- bind mount in `/opt/vocabmaster/deploy/docker-compose.proxy.yml`

The repository source of truth remains `site/klioai-landing`. Keep the VPS
copy in sync when privacy, terms, or account-deletion pages change for Google
Play review.

## Deploy Flow

Historical GitHub Pages workflow:

`.github/workflows/landing-pages.yml`

Trigger:

- Push to `main` when `site/klioai-landing/**` changes
- Manual `workflow_dispatch`

Required GitHub repo setting:

- Settings -> Pages -> Build and deployment -> Source: `GitHub Actions`

If the workflow fails with `Get Pages site failed` / `HttpError: Not Found`, GitHub Pages is not enabled for the repository from the API's point of view. Reopen Settings -> Pages and make sure the source is saved as `GitHub Actions`. If the repository is private, also confirm the account/organization plan supports Pages for private repositories.

## Domain

The landing domain currently points to the production VPS:

- `klioai.app`
- Optional `www.klioai.app`

The API stays on the same VPS behind a separate Caddy host rule:

- `api.klioai.app`

## Asset Rules

- Keep images compressed before committing.
- Keep app screenshots in `site/klioai-landing/assets`.
- Do not store generated build folders or raw design exports in the repo.
- Keep privacy and terms pages in the same static site so Google Play always has stable public URLs.

## Verification

After deployment:

```powershell
Invoke-WebRequest https://klioai.app -UseBasicParsing
Invoke-WebRequest https://klioai.app/privacy.html -UseBasicParsing
Invoke-WebRequest https://klioai.app/terms.html -UseBasicParsing
Invoke-WebRequest https://klioai.app/account-deletion -UseBasicParsing
Invoke-WebRequest https://klioai.app/account-deletion.html -UseBasicParsing
```

The landing page must include:

- Google Play link
- App name: KlioAI
- Privacy link
- Terms link
- Account deletion link
- App/entity reference matching Google Play listing
