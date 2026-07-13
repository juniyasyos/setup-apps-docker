# =============================================================================
# Dockerfile — fe-smsp
# Type       : Frontend Static App
# Framework  : React / Vite
# Build      : Node.js
# Runtime    : Nginx Alpine
# =============================================================================

# ─────────────────────────────────────────
# Stage 1: Build frontend
# ─────────────────────────────────────────
FROM node:24-alpine AS builder

ARG APP_NAME="fe-smsp"
ARG VITE_APP_NAME="VITE_APP_NAME_PLACEHOLDER"
ARG VITE_API_URL="VITE_API_URL_PLACEHOLDER"
ARG VITE_USE_SSO="VITE_USE_SSO_PLACEHOLDER"
ARG VITE_SSO_URL="VITE_SSO_URL_PLACEHOLDER"
ARG NODE_ENV="production"

ENV VITE_APP_NAME=${VITE_APP_NAME}
ENV VITE_API_URL=${VITE_API_URL}
ENV VITE_USE_SSO=${VITE_USE_SSO}
ENV VITE_SSO_URL=${VITE_SSO_URL}
ENV NODE_ENV=${NODE_ENV}

WORKDIR /app

COPY package*.json ./

RUN npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    if [ -f package-lock.json ]; then npm ci --include=dev; else npm install --include=dev; fi

COPY . .

RUN rm -f .env .env.local .env.production && npm run build


# ─────────────────────────────────────────
# Stage 2: Runtime Nginx
# ─────────────────────────────────────────
FROM nginx:1.27-alpine AS runtime

ARG APP_NAME="fe-smsp"

LABEL app.name="${APP_NAME}"
LABEL app.type="frontend-static"
LABEL app.framework="react-vite"

COPY --from=nginx_infra frontend-spa.conf /etc/nginx/conf.d/default.conf

COPY --from=builder /app/dist /usr/share/nginx/html

# Inject environment variables at runtime
RUN echo '#!/bin/sh' > /docker-entrypoint.d/40-inject-env.sh && \
    echo 'find /usr/share/nginx/html -type f \( -name "*.js" -o -name "*.html" \) -exec sed -i "s|VITE_APP_NAME_PLACEHOLDER|${VITE_APP_NAME}|g" {} \;' >> /docker-entrypoint.d/40-inject-env.sh && \
    echo 'find /usr/share/nginx/html -type f \( -name "*.js" -o -name "*.html" \) -exec sed -i "s|VITE_API_URL_PLACEHOLDER|${VITE_API_URL}|g" {} \;' >> /docker-entrypoint.d/40-inject-env.sh && \
    echo 'find /usr/share/nginx/html -type f \( -name "*.js" -o -name "*.html" \) -exec sed -i "s|VITE_USE_SSO_PLACEHOLDER|${VITE_USE_SSO}|g" {} \;' >> /docker-entrypoint.d/40-inject-env.sh && \
    echo 'find /usr/share/nginx/html -type f \( -name "*.js" -o -name "*.html" \) -exec sed -i "s|VITE_SSO_URL_PLACEHOLDER|${VITE_SSO_URL}|g" {} \;' >> /docker-entrypoint.d/40-inject-env.sh && \
    chmod +x /docker-entrypoint.d/40-inject-env.sh

EXPOSE 7250

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
  CMD wget -qO- http://127.0.0.1/health >/dev/null 2>&1 || exit 1

CMD ["nginx", "-g", "daemon off;"]
