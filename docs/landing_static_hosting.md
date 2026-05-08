# Landing Static Hosting

KlioAI landing, privacy, terms, and static assets live under:

`site/klioai-landing`

## Hosting Target

Use GitHub Pages for the public static landing site. Static pages should not be served by the production VPS unless there is a temporary incident or migration.

## Deploy Flow

Workflow:

`.github/workflows/landing-pages.yml`

Trigger:

- Push to `main` when `site/klioai-landing/**` changes
- Manual `workflow_dispatch`

Required GitHub repo setting:

- Settings -> Pages -> Build and deployment -> Source: `GitHub Actions`

If the workflow fails with `Get Pages site failed` / `HttpError: Not Found`, GitHub Pages is not enabled for the repository from the API's point of view. Reopen Settings -> Pages and make sure the source is saved as `GitHub Actions`. If the repository is private, also confirm the account/organization plan supports Pages for private repositories.

## Domain

Point the landing domain to GitHub Pages:

- `klioai.app`
- Optional `www.klioai.app`

Keep the API on the VPS:

- `api.klioai.app`

This keeps marketing/static traffic away from the backend host and reduces the chance that a landing spike affects API availability.

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
```

The landing page must include:

- Google Play link
- App name: KlioAI
- Privacy link
- Terms link
- App/entity reference matching Google Play listing
