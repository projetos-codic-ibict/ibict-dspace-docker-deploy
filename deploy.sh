#!/bin/bash

set -e

# -----------------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------------

load_env() {
    if [ ! -f .env ]; then
        echo "Error: .env file not found."
        exit 1
    fi

    set -o allexport
    source .env
    set +o allexport
}

clone_repositories() {
    echo "======= Cloning Repositories ======="

    local backend_target="${DSPACE_BACKEND_TAG:-main}"
    local frontend_target="${DSPACE_FRONTEND_TAG:-main}"

    if [ ! -d "DSpace" ]; then
        echo "Cloning backend from: $DSPACE_BACKEND_REPO (Target: $backend_target)"
        git clone -b "$backend_target" "$DSPACE_BACKEND_REPO" DSpace
    else
        echo "DSpace directory already exists. Skipping clone."
    fi

    if [ ! -d "dspace-angular" ]; then
        echo "Cloning frontend from: $DSPACE_FRONTEND_REPO (Target: $frontend_target)"
        git clone -b "$frontend_target" "$DSPACE_FRONTEND_REPO" dspace-angular
    else
        echo "dspace-angular directory already exists. Skipping clone."
    fi
}

update_repositories() {
    echo "======= Updating Repositories (Git Fetch & Checkout) ======="

    local backend_target="${DSPACE_BACKEND_TAG:-main}"
    local frontend_target="${DSPACE_FRONTEND_TAG:-main}"

    # Backend
    if [ -d "DSpace" ]; then
        echo "Updating backend to target: $backend_target"

        cd DSpace
        git fetch --all --tags --prune
        git checkout "$backend_target"
        git pull origin "$backend_target" 2>/dev/null || \
            echo "Notice: Backend is using a fixed tag."
        cd ..
    else
        echo "Error: DSpace directory not found."
        exit 1
    fi

    # Frontend
    if [ -d "dspace-angular" ]; then
        echo "Updating frontend to target: $frontend_target"

        cd dspace-angular
        git fetch --all --tags --prune
        git checkout "$frontend_target"
        git pull origin "$frontend_target" 2>/dev/null || \
            echo "Notice: Frontend is using a fixed tag."
        cd ..
    else
        echo "Error: dspace-angular directory not found."
        exit 1
    fi
}

patch_dockerfiles() {
    echo "======= Applying Dockerfile Production Patches ======="

    # -------------------------------------------------------------------------
    # Backend (DSpace)
    # -------------------------------------------------------------------------

    if [ -f DSpace/Dockerfile ] && ! grep -q "^USER root$" DSpace/Dockerfile; then
        sed -i '/RUN mkdir \/install/i USER root' DSpace/Dockerfile
        echo "Backend production Dockerfile patched."
    fi

    if [ -f DSpace/Dockerfile.test ] && ! grep -q "^USER root$" DSpace/Dockerfile.test; then
        sed -i '/RUN mkdir \/install/i USER root' DSpace/Dockerfile.test
        echo "Backend development Dockerfile patched."
    fi

    # -------------------------------------------------------------------------
    # Frontend (Angular SSR)
    # -------------------------------------------------------------------------

    if [ -f dspace-angular/Dockerfile ]; then

        # Remove default development configuration
        sed -i '/ENV NODE_ENV=development/d' dspace-angular/Dockerfile
        sed -i '/CMD npm run serve -- --host 0.0.0.0/d' dspace-angular/Dockerfile

        # Remove previously injected production block
        sed -i '/# --- Native SSR Production Configuration (dspace-docker-deploy) ---/,$d' \
            dspace-angular/Dockerfile

        # Append production configuration
        cat <<'EOF' >> dspace-angular/Dockerfile

# --- Native SSR Production Configuration (dspace-docker-deploy) ---
ENV NODE_ENV=production

# Build the Angular application during image build
RUN npm run build:prod

# Start the SSR server at runtime
CMD ["npm", "run", "serve:ssr"]

EOF

        echo "Frontend Dockerfile optimized for SSR production."
    fi
}

build_environment() {
    echo "======= Building Production Environment ======="

    export MAVEN_OPTS="-Dhttp.keepAlive=false -Dmaven.wagon.http.retryHandler.count=5 -Dmaven.wagon.http.pool=false"

    docker compose -f docker-compose.prod.yml build --no-cache
}

start_containers() {
    echo "======= Starting Containers ======="

    docker compose -f docker-compose.prod.yml up -d

    echo "======= DSpace Production Environment Online ======="
}

remove_containers() {
    echo "======= Removing Existing Containers ======="

    docker compose -f docker-compose.prod.yml down --remove-orphans
}

stop_containers() {
    echo "======= Stopping Containers ======="

    docker compose -f docker-compose.prod.yml stop
}

show_help() {
    echo "Usage: $0 {install|update|rebuild|restart|stop}"
    echo
    echo "Commands:"
    echo "  install  Clone repositories and install the entire environment"
    echo "  update   Update source code (git pull), rebuild images, and restart"
    echo "  rebuild  Rebuild local images without updating source code and restart"
    echo "  restart  Restart the current containers"
    echo "  stop     Stop all running containers"
    exit 1
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION FLOW
# -----------------------------------------------------------------------------

load_env

case "$1" in
    install)
        clone_repositories
        patch_dockerfiles
        remove_containers
        build_environment
        start_containers
        ;;
    update)
        update_repositories
        patch_dockerfiles
        remove_containers
        build_environment
        start_containers
        ;;
    rebuild)
        patch_dockerfiles
        remove_containers
        build_environment
        start_containers
        ;;
    restart)
        remove_containers
        start_containers
        ;;
    stop)
        stop_containers
        ;;
    *)
        show_help
        ;;
esac
