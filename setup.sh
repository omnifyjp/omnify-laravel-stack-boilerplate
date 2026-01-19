#!/bin/bash

# Laravel Stack Boilerplate Setup (Laravel Only)

set -e

cd "$(dirname "$0")"

# Get project name from parent folder
PROJECT_NAME=$(basename "$(dirname "$(pwd)")")

echo "Stack: Laravel (Blade + Inertia)"
echo "Project: $PROJECT_NAME"
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
APP_URL=https://$PROJECT_NAME.test

DB_CONNECTION=sqlite

SESSION_DRIVER=cookie
SESSION_DOMAIN=.$PROJECT_NAME.test
SESSION_SAME_SITE=lax
SESSION_SECURE_COOKIE=true

SANCTUM_STATEFUL_DOMAINS=$PROJECT_NAME.test

# SSO Configuration
SSO_CONSOLE_URL=https://auth-$PROJECT_NAME.test
SSO_SERVICE_SLUG=service
SSO_SERVICE_SECRET=local_dev_secret
EOF

php artisan key:generate --force

# Publish SSO config
php artisan vendor:publish --tag=sso-client-config --force 2>/dev/null || true
echo "✓ Environment configured"

# Step 4: Initialize database
echo ""
echo "Step 4: Initialize database"
touch database/database.sqlite
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
herd link $PROJECT_NAME
herd secure $PROJECT_NAME
echo "✓ https://$PROJECT_NAME.test"

echo ""
echo "Done!"
echo "  App: https://$PROJECT_NAME.test"
echo ""
echo "SVN Commands:"
echo "  svn checkout <repo-url> .   # Checkout existing repo"
echo "  svn add --force .           # Add all files"
echo "  svn commit -m 'message'     # Commit changes"
