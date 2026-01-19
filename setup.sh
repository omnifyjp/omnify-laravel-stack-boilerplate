#!/bin/bash

# Laravel Stack Boilerplate Setup (Laravel Only)

set -e

cd "$(dirname "$0")"

# Load .env if exists
if [ -f ".env" ]; then
    source .env
fi

# Set defaults
BASE_DOMAIN=${BASE_DOMAIN:-$(basename "$(dirname "$(pwd)")")}

# DB prefix (replace - with _)
DB_PREFIX=$(echo "$BASE_DOMAIN" | tr '-' '_')

echo "Stack: Laravel (Blade + Inertia)"
echo "Domain: $BASE_DOMAIN"
echo ""

# Step 1: Install dependencies
echo "Step 1: Install dependencies"
npm install
echo "✓ npm dependencies"

# Step 2: Create Laravel application
echo "Step 2: Create Laravel application"
if [ ! -d "app" ]; then
    laravel new app --no-interaction
    cd app
    
    # Install API with Sanctum
    php artisan install:api --no-interaction
    
    # Install SSO Client package (from local)
    echo "Installing SSO Client (local)..."
    composer config repositories.omnify-client-laravel-sso path ../../packages/omnify-client-laravel-sso
    composer config --no-plugins allow-plugins.omnifyjp/omnify-client-laravel-sso true
    composer require omnifyjp/omnify-client-laravel-sso:@dev lcobucci/jwt --no-interaction
    
    # Configure CORS
    cat > config/cors.php << EOF
<?php

return [
    'paths' => ['api/*', 'sanctum/csrf-cookie', 'sso/*'],
    'allowed_methods' => ['*'],
    'allowed_origins' => [],
    'allowed_origins_patterns' => [
        '#^https?://[a-z0-9-]+\\.test\$#i',
        '#^https?://[a-z0-9-]+\\.[a-z0-9-]+\\.test\$#i',
        '#^https?://localhost(:\d+)?\$#',
    ],
    'allowed_headers' => ['*'],
    'exposed_headers' => [],
    'max_age' => 0,
    'supports_credentials' => true,
];
EOF
    echo "✓ CORS configured"
    
    # Configure middleware (CSRF exclusion + statefulApi)
    cat > bootstrap/app.php << 'EOF'
<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->validateCsrfTokens(except: [
            'api/sso/callback',
            'api/sso/*',
        ]);
        $middleware->statefulApi();
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
EOF
    echo "✓ Middleware configured"
    
    # Configure User model with SSO trait
    cat > app/Models/User.php << 'EOF'
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Omnify\SsoClient\Models\Traits\HasConsoleSso;

class User extends Authenticatable
{
    use HasFactory, Notifiable, HasConsoleSso;

    protected $fillable = [
        'name',
        'email',
        'password',
        'console_user_id',
        'console_access_token',
        'console_refresh_token',
        'console_token_expires_at',
    ];

    protected $hidden = [
        'password',
        'remember_token',
        'console_access_token',
        'console_refresh_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'console_token_expires_at' => 'datetime',
        ];
    }
}
EOF
    echo "✓ User model configured"
else
    cd app
fi

# Step 3: Setup environment
echo ""
echo "Step 3: Setup environment"

cat > .env << EOF
APP_NAME=Service
APP_KEY=
APP_ENV=local
APP_DEBUG=true
APP_URL=https://$BASE_DOMAIN.test

# Database (MySQL)
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_PREFIX}_db
DB_USERNAME=root
DB_PASSWORD=

# Cache & Queue (Redis)
CACHE_STORE=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379
REDIS_PREFIX=${DB_PREFIX}_

# Session
SESSION_DOMAIN=.$BASE_DOMAIN.test
SESSION_SAME_SITE=lax
SESSION_SECURE_COOKIE=true

SANCTUM_STATEFUL_DOMAINS=$BASE_DOMAIN.test

# Mail (Mailpit)
MAIL_MAILER=smtp
MAIL_HOST=127.0.0.1
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="no-reply@$BASE_DOMAIN.test"
MAIL_FROM_NAME="\${APP_NAME}"

# Storage (Minio S3)
FILESYSTEM_DISK=s3
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=${DB_PREFIX}
AWS_ENDPOINT=http://127.0.0.1:9000
AWS_USE_PATH_STYLE_ENDPOINT=true

# SSO Configuration
SSO_CONSOLE_URL=https://auth-omnify.test
SSO_SERVICE_SLUG=$BASE_DOMAIN
SSO_SERVICE_SECRET=local_dev_secret
EOF

php artisan key:generate --force

# Publish SSO config
php artisan vendor:publish --tag=sso-client-config --force 2>/dev/null || true

# Create MySQL database
mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_PREFIX}_db;" 2>/dev/null || true
echo "✓ MySQL database: ${DB_PREFIX}_db"

# Create Minio bucket
if command -v mc &> /dev/null; then
    mc alias set local http://127.0.0.1:9000 minioadmin minioadmin 2>/dev/null || true
    mc mb local/${DB_PREFIX} 2>/dev/null || true
    echo "✓ Minio bucket: ${DB_PREFIX}"
fi

echo "✓ Environment configured"

# Step 4: Initialize database
echo ""
echo "Step 4: Initialize database"
php artisan migrate --force
echo "✓ Database ready"

# Step 5: Initialize Subversion repository
echo ""
echo "Step 5: Initialize Subversion"
cd ..
if [ ! -d ".svn" ]; then
    # Create svn ignore file
    cat > svn-ignore.txt << 'EOF'
.env
.phpunit.result.cache
Homestead.json
Homestead.yaml
auth.json
npm-debug.log
yarn-error.log
/.fleet
/.idea
/.vscode
/node_modules
/public/build
/public/hot
/public/storage
/storage/*.key
/vendor
EOF
    
    # Initialize SVN working copy (assumes SVN repo exists)
    # For local development, we'll just set up the ignore patterns
    echo "SVN ignore patterns created in svn-ignore.txt"
    echo "To use with existing SVN repo:"
    echo "  svn checkout <repo-url> ."
    echo "  svn propset svn:ignore -F svn-ignore.txt app"
    echo "✓ Subversion setup ready"
else
    echo "✓ Subversion already initialized"
fi

# Step 6: Link to Herd
echo ""
echo "Step 6: Link to Herd"
cd app
herd link $BASE_DOMAIN
herd secure $BASE_DOMAIN
echo "✓ https://$BASE_DOMAIN.test"

echo ""
echo "Done!"
echo "  App: https://$BASE_DOMAIN.test"
echo ""
echo "SVN Commands:"
echo "  svn checkout <repo-url> .   # Checkout existing repo"
echo "  svn add --force .           # Add all files"
echo "  svn commit -m 'message'     # Commit changes"
