# Production deployment

The storefront runs at https://rentalmoney.in. The Laravel API runs at
https://api.rentalmoney.in/api/v1 on Hostinger web hosting.

## Routine updates

Merge reviewed web/backend changes into the `main` branch of
`creator-alpha001/Marketplace`. Hostinger builds the frontend from that branch.
The `Deploy production backend` GitHub workflow tests backend changes, installs
production dependencies in a fresh private release, applies pending migrations,
switches the active release, and checks the public API. A failed health check
restores the previous code. Database migrations are not automatically reversed;
use backward-compatible, additive migrations and back up data before destructive
schema changes. Application updates preserve the production database, uploaded
files, administrator accounts, and private environment configuration.

The website is built by Hostinger's own builder (`~/domains/rentalmoney.in/hbuilds`,
one folder per build, with a log of each under `hbuilds/logs`). Builds start only
when Hostinger is told to: a push to GitHub does not start one unless the site's
auto-deploy is connected in the Hostinger panel. Backend workflow runs do not
rebuild the website either. To check which commit the live site was built from,
read the first lines of the newest log in `hbuilds/logs/<build id>/`.

Frontend settings: Next.js, Node 22, root `.`, npm, build `npm run build`, output
`.next`. Set `NEXT_PUBLIC_API_URL=https://api.rentalmoney.in/api/v1` for both build
and runtime. The build uses webpack for compatibility with Hostinger.

Backend automation uses an SSH key restricted to the deployment command. Its
private half is stored in the repository's encrypted GitHub Actions secret
`HOSTINGER_BACKEND_SSH_KEY`; the public host identity is pinned in the repository
variable `HOSTINGER_KNOWN_HOSTS`. The server deployment wrapper is installed
outside the web root under `deployment/deploy-backend.sh`. Update that wrapper
deliberately over the administrator's SSH connection when changing deployment
mechanics. Repository pushes cannot replace it.

Production `.env` and storage live under the API domain's `deployment/shared`.
Release code lives in `deployment/releases/<commit>`. The existing
`repository/laravel-backend` path points to the active release, so public PHP
entrypoints and the minute-based scheduler keep working through updates.

## Mobile app

The independent repository is `Chota-Thanos/Marketplace-mobile`. The app defaults
to the live HTTPS API. Release builds require the private signing key and
`android/key.properties`; neither belongs in Git. Preserve the signing key and
its password to sign future installable updates. Increase the build number in
`pubspec.yaml` for each distributed version. An APK does not update already
installed phones merely because the backend or website is deployed.

There are two apps, built from the same project: the shopping app (flavor `shop`,
`in.bazaarx.marketplace_app`) and the seller app (flavor `vendor`, `in.bazaarx.seller`).
Each is released separately; see the app's README for the build commands.

## Initial catalog and integrations

`StarterCatalogSeeder` is an explicit, repeat-safe starter catalog. It creates
clearly named sample products with zero stock and does not run automatically on
deployments. Replace sample listings and stock before taking real orders.

Live payment, delivery, email, SMS, and Google sign-in provider credentials must
be configured separately before advertising those features as operational.
