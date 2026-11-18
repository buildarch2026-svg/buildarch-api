# BUILD ARCH

## AWS EC2 Deployment & Server Configuration Documentation

**Project:** Build Arch\
**Document type:** Technical deployment and server administration guide\
**Documentation date:** 12 November 2026\
**Application:** Laravel REST API\
**GitHub repository:**
`https://github.com/buildarch2026-svg/buildarch-api.git`\
**Branch:** `develop`

> **Note:** This document records the configuration and commands shown
> during the deployment session. Items marked pending require
> verification on the live server. Do not assume every value remains
> current.

## 1. AWS EC2 server information

  Configuration                     Recorded value
  --------------------------------- ------------------------
  Cloud provider                    Amazon Web Services
  Service                           EC2
  Instance name                     `buildarch-api-server`
  Operating system                  Ubuntu
  Public IPv4 address (recorded)    `3.25.85.44`
  Private IPv4 address (recorded)   `172.31.5.15`
  Web server                        Nginx
  PHP version                       PHP 8.3
  PHP process manager               PHP-FPM
  Database                          MySQL
  Application framework             Laravel 12

The public IP is the address recorded during this deployment session.
Confirm it in the AWS EC2 console; it can change after stop/start unless
an Elastic IP is assigned.

### 1.1 Request flow

``` text
Flutter mobile application
          |
       HTTP/HTTPS
          v
        AWS EC2
         Nginx
          |
          v
       PHP-FPM
        PHP 8.3
          |
          v
       Laravel API
          |
          v
         MySQL
```

## 2. Application directory structure

Main repository:

``` bash
/var/www/buildarch
```

Laravel API directory:

``` bash
/var/www/buildarch/buid_arch_api
```

**Directory-name note:** The backend folder is spelled `buid_arch_api`
in the recorded server path. Use this exact spelling unless the
directory is deliberately renamed and all configuration paths are
updated.

Navigate to the API:

``` bash
cd /var/www/buildarch/buid_arch_api
```

Important Laravel directories/files include `app/`, `bootstrap/`,
`config/`, `database/`, `public/`, `resources/`, `routes/`, `storage/`,
`vendor/`, `artisan`, `composer.json`, and `.env`.

## 3. Software and Laravel checks

Update Ubuntu packages:

``` bash
sudo apt update
sudo apt upgrade -y
```

Check PHP and Composer:

``` bash
php -v
composer --version
```

The recorded server configuration uses PHP 8.3.

Check Laravel:

``` bash
cd /var/www/buildarch/buid_arch_api
php artisan --version
```

Install production dependencies when deploying dependency changes:

``` bash
composer install --no-dev --optimize-autoloader
```

## 4. Laravel environment configuration

Environment file:

``` text
/var/www/buildarch/buid_arch_api/.env
```

Edit:

``` bash
nano .env
```

Example application settings:

``` dotenv
APP_ENV=production
APP_DEBUG=false
APP_URL=http://3.25.85.44
```

Database settings must match the actual server configuration:

``` dotenv
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=YOUR_DATABASE_NAME
DB_USERNAME=YOUR_DATABASE_USERNAME
DB_PASSWORD=YOUR_DATABASE_PASSWORD
```

The database values above are placeholders, not confirmed live
credentials.

**Security:** Never commit `.env` or put passwords, API keys, or tokens
in this document. Keep `APP_DEBUG=false` in production.

The following command was run and returned
`Application key set successfully`:

``` bash
php artisan key:generate
```

Do not regenerate the key on an existing production installation without
a planned key-rotation procedure. Doing so can make existing encrypted
data or sessions unreadable.

## 5. Database and migrations

Check migration status:

``` bash
cd /var/www/buildarch/buid_arch_api
php artisan migrate:status
```

Before applying migrations, review the migration files, confirm
application compatibility, and take and verify a database backup. Then
run:

``` bash
php artisan migrate --force
```

**Never run `php artisan migrate:fresh` on the production database.** It
drops existing tables and can destroy production data.

## 6. Nginx configuration

Check Nginx:

``` bash
sudo systemctl status nginx
```

The captured server status showed Nginx as `active (running)`.

Available site configuration:

``` text
/etc/nginx/sites-available/buildarch
```

Enabled site configuration:

``` text
/etc/nginx/sites-enabled/buildarch
```

Edit the configuration:

``` bash
sudo nano /etc/nginx/sites-available/buildarch
```

Recorded server block:

``` nginx
server {
    listen 80;
    listen [::]:80;

    server_name 3.25.85.44;

    root /var/www/buildarch/buid_arch_api/public;
    index index.php index.html;

    client_max_body_size 50M;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
```

Enable the site if the link does not already exist:

``` bash
sudo ln -s /etc/nginx/sites-available/buildarch /etc/nginx/sites-enabled/
```

Inspect the link:

``` bash
ls -l /etc/nginx/sites-enabled/buildarch
```

Test and reload:

``` bash
sudo nginx -t
sudo systemctl reload nginx
```

Expected successful test output:

``` text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Only reload after the configuration test succeeds.

## 7. PHP-FPM configuration

Configured socket:

``` text
/run/php/php8.3-fpm.sock
```

Check service and socket:

``` bash
sudo systemctl status php8.3-fpm
ls -l /run/php/php8.3-fpm.sock
```

Restart when required:

``` bash
sudo systemctl restart php8.3-fpm
```

## 8. GitHub repository integration

Recorded Git remote:

``` text
https://github.com/buildarch2026-svg/buildarch-api.git
```

Deployment branch:

``` text
develop
```

Check repository, remote, branch, and working tree:

``` bash
cd /var/www/buildarch
git remote -v
git branch --show-current
git status
```

GitHub does not accept normal account passwords for HTTPS Git
operations. Use a Personal Access Token (PAT) with only the required
permissions, or configure SSH authentication/deploy keys. Do not put
tokens in source code, documentation, shell history, or a remote URL.

Fetch and inspect updates:

``` bash
git fetch origin
git status
git log --oneline --decorate --graph --all -10
```

If the branch can be safely fast-forwarded:

``` bash
git pull --ff-only origin develop
```

If there are local changes or divergent histories, stop and inspect
them. Do not use `git reset --hard` or force-push without understanding
the impact and making any required backup.

## 9. Standard deployment procedure for future updates

### Step 1: Develop and test locally

Complete code changes and run relevant local tests. Identify whether the
release includes PHP code, Composer dependencies, database migrations,
environment changes, uploaded files, or separate Flutter changes.

### Step 2: Commit and push from the local machine

From the local repository root:

``` bash
git status
git add .
git commit -m "Describe the update"
git push origin develop
```

Review files before staging to avoid committing secrets, local
configuration, generated files, or unrelated changes.

### Step 3: Connect to AWS EC2 and inspect the repository

``` bash
cd /var/www/buildarch
git status
git branch --show-current
git fetch origin
```

Confirm the intended branch and inspect local modifications before
pulling.

### Step 4: Back up production data when required

For releases involving database schema or data changes, take and verify
a MySQL backup before proceeding. Consider a rollback plan for
application code and uploaded files as well.

### Step 5: Pull the intended code

``` bash
git pull --ff-only origin develop
git log -1 --oneline
git status
```

### Step 6: Install dependencies when required

``` bash
cd /var/www/buildarch/buid_arch_api
composer install --no-dev --optimize-autoloader
```

### Step 7: Run migrations when required

Review migration status and the release's migration files, take a
backup, then:

``` bash
php artisan migrate --force
```

### Step 8: Clear and rebuild Laravel caches

``` bash
php artisan optimize:clear
php artisan config:cache
php artisan route:cache
php artisan view:cache
```

Investigate any cache command failure rather than ignoring it.

### Step 9: Restart/reload services

``` bash
sudo systemctl restart php8.3-fpm
sudo nginx -t
sudo systemctl reload nginx
```

### Step 10: Verify the deployment

``` bash
php artisan --version
php artisan route:list
sudo systemctl status nginx
sudo systemctl status php8.3-fpm
git status
```

Test public and protected API workflows and inspect application/server
logs.

## 10. API endpoint testing

### 10.1 Public ping endpoint

Endpoint:

``` text
/api/public/ping
```

Recorded public URL:

``` text
http://3.25.85.44/api/public/ping
```

### 10.2 Localhost test with the correct Host header

The Nginx virtual host uses `server_name 3.25.85.44`. A localhost
request without the matching Host header returned an Nginx 404. The
following request, with the Host header, returned HTTP 200:

``` bash
curl -i \
  -H "Host: 3.25.85.44" \
  -H "Accept: application/json" \
  http://127.0.0.1/api/public/ping
```

**Recorded result:** `HTTP/1.1 200 OK`.

This confirms the ping route worked through the selected Nginx virtual
host on localhost at the time of testing.

### 10.3 Protected user endpoint

Endpoint:

``` text
/api/user
```

Test without a bearer token:

``` bash
curl -i \
  -H "Host: 3.25.85.44" \
  -H "Accept: application/json" \
  http://127.0.0.1/api/user
```

**Recorded result:** HTTP 401 with JSON message `Unauthenticated.` This
is expected for a protected endpoint when no valid authentication token
is supplied.

### 10.4 External test

Test from an external browser or API client:

``` text
http://3.25.85.44/api/public/ping
```

External access must be verified separately. A successful localhost test
does not prove that the AWS Security Group, public IP, routing, or
external firewall permits access.

## 11. Laravel API authentication redirect configuration

An API authentication redirect issue was investigated during deployment.

File:

``` text
buid_arch_api/bootstrap/app.php
```

Required import:

``` php
use Illuminate\Http\Request;
```

Middleware configuration recorded in the change:

``` php
->withMiddleware(function (Middleware $middleware): void {
    $middleware->alias([
        'project.active' => EnsureProjectIsActive::class,
        'main-app' => \App\Http\Middleware\EnsureMainAppAccess::class,
    ]);

    $middleware->redirectGuestsTo(
        fn (Request $request) => $request->is('api/*')
            ? null
            : route('login')
    );
})
```

The intent is to avoid redirecting API requests to a web login page
while retaining the web login redirect for browser routes. The change
was committed and pushed to `develop` during the deployment work. Verify
the current source and test both API and web authentication behavior
after future changes.

## 12. Troubleshooting record

### 12.1 Nginx 404 on localhost

**Observed:** `http://127.0.0.1/api/user` returned an Nginx 404 HTML
response.

**Investigation:** The Nginx site configuration had
`server_name 3.25.85.44`.

**Successful ping test:**

``` bash
curl -i \
  -H "Host: 3.25.85.44" \
  -H "Accept: application/json" \
  http://127.0.0.1/api/public/ping
```

**Result:** HTTP 200 OK.

### 12.2 API authentication response

The protected `/api/user` endpoint returned HTTP 401 and
`Unauthenticated.` when requested without a token. This is expected for
a protected route without valid authentication credentials; it is not by
itself evidence of a server failure.

### 12.3 GitHub password authentication

**Observed:**

``` text
Password authentication is not supported for Git operations.
```

**Resolution:** Use a PAT or SSH authentication instead of the normal
GitHub account password.

### 12.4 Git push rejected because remote had new commits

**Observed:**

``` text
[rejected] develop -> develop (fetch first)
```

**Investigation commands:**

``` bash
git fetch origin
git log --oneline --graph --decorate --all -10
git status
```

The remote was fetched and branch history inspected. The branch was
synchronized and a later push reported `Everything up-to-date`. Prefer
`git pull --ff-only origin develop` when a fast-forward is possible. If
histories diverge, inspect and reconcile them instead of force-pushing.

### 12.5 Laravel cache or migration errors

If Laravel reports missing cache or migration tables, inspect the actual
cache/session/database configuration and migration status. Clearing a
cache does not create a missing database table.

``` bash
php artisan optimize:clear
php artisan migrate:status
```

Take a database backup before schema changes.

## 13. Security and production-readiness requirements

Verify these items before considering the server fully production-ready:

1.  **HTTPS:** Install and configure an SSL certificate, then redirect
    HTTP traffic to HTTPS. The captured Nginx configuration listens on
    port 80; HTTPS was not verified in the session.
2.  **Application debug:** Confirm `APP_ENV=production` and
    `APP_DEBUG=false`.
3.  **Secrets:** Keep `.env`, database passwords, API credentials, and
    tokens out of Git and documentation.
4.  **Credential rotation:** Rotate any credential that may have been
    exposed and update the server configuration securely.
5.  **AWS Security Group:** Allow only required inbound ports. Restrict
    SSH access to trusted IP ranges where practical.
6.  **Database access:** Do not expose MySQL port 3306 publicly unless
    there is a specific secured requirement.
7.  **File permissions:** Ensure the web-server user can write to
    Laravel `storage` and `bootstrap/cache` without making the whole
    project world-writable.
8.  **Backups:** Schedule database and required file backups, and test
    restoration.
9.  **Logs:** Monitor Laravel and Nginx logs.
10. **Deployment safety:** Avoid destructive migration commands and
    force-pushes on production.
11. **CORS and authentication:** Verify allowed app origins, token
    expiry, authorization rules, and protected endpoints.
12. **Public IP stability:** Consider an Elastic IP or domain name for a
    stable production endpoint.

## 14. Useful server administration commands

  Purpose                    Command
  -------------------------- -------------------------------------
  Check Nginx                `sudo systemctl status nginx`
  Restart Nginx              `sudo systemctl restart nginx`
  Reload Nginx               `sudo systemctl reload nginx`
  Test Nginx configuration   `sudo nginx -t`
  Check PHP-FPM              `sudo systemctl status php8.3-fpm`
  Restart PHP-FPM            `sudo systemctl restart php8.3-fpm`
  Check PHP version          `php -v`
  Check Laravel version      `php artisan --version`
  Clear Laravel caches       `php artisan optimize:clear`
  List routes                `php artisan route:list`
  Check migrations           `php artisan migrate:status`
  Check Git status           `git status`
  Fetch GitHub updates       `git fetch origin`
  Pull branch safely         `git pull --ff-only origin develop`

### 14.1 Log locations

Laravel:

``` text
/var/www/buildarch/buid_arch_api/storage/logs/laravel.log
```

Nginx access log:

``` text
/var/log/nginx/access.log
```

Nginx error log:

``` text
/var/log/nginx/error.log
```

PHP-FPM logs:

``` bash
sudo journalctl -u php8.3-fpm -n 100
```

Follow Laravel log output:

``` bash
tail -f /var/www/buildarch/buid_arch_api/storage/logs/laravel.log
```

## 15. Deployment status as of 12 November 2026

  Activity                                     Recorded status
  -------------------------------------------- ----------------------
  AWS EC2 connection                           Completed
  Ubuntu server access                         Completed
  Nginx installation/configuration             Completed
  PHP 8.3-FPM configuration                    Configured
  Composer/Laravel dependencies                Installed
  Laravel application key generation           Completed
  GitHub repository integration                Configured
  `develop` branch synchronization             Completed
  API authentication redirect change           Committed and pushed
  Laravel cache clearing                       Completed
  Nginx configuration validation               Successful
  Public ping via localhost with Host header   HTTP 200 recorded
  Protected user endpoint without token        HTTP 401 recorded
  External public IP API test                  Pending verification
  HTTPS/SSL                                    Pending verification
  Production migration review                  Pending verification
  Database backup and restore test             Pending verification
  Flutter application integration test         Pending verification

Statuses reflect evidence captured during the deployment session and are
not a live health check.

## 16. Future deployment checklist

-   [ ] Complete and test changes locally.
-   [ ] Review files before staging.
-   [ ] Commit changes to Git.
-   [ ] Push to GitHub `develop`.
-   [ ] Connect to AWS EC2.
-   [ ] Check server repository status and current branch.
-   [ ] Fetch the latest remote commits.
-   [ ] Back up production database when appropriate.
-   [ ] Pull the intended commit using fast-forward-only mode.
-   [ ] Install Composer dependencies if required.
-   [ ] Review and run pending migrations if required.
-   [ ] Clear Laravel caches.
-   [ ] Rebuild required Laravel caches.
-   [ ] Restart PHP-FPM.
-   [ ] Test Nginx configuration.
-   [ ] Reload Nginx.
-   [ ] Test the public ping endpoint.
-   [ ] Test login and authenticated API requests.
-   [ ] Test relevant Flutter application workflows.
-   [ ] Review Laravel and Nginx logs.
-   [ ] Record the deployed commit and release date.

## 17. Conclusion

The Build Arch Laravel API was configured on an AWS EC2 Ubuntu server
using Nginx, PHP 8.3-FPM, Composer, Laravel 12, and MySQL.

The GitHub repository is connected to the server through the `develop`
branch. The public ping endpoint returned HTTP 200 during localhost
testing when the request included the correct Nginx Host header. The
protected user endpoint returned HTTP 401 when tested without
authentication, as expected.

This document is the working technical reference for Build Arch backend
deployment, server configuration, maintenance, and troubleshooting.
Update the server details, deployment status, and procedures whenever
the infrastructure or release process changes.
