# ============================================
# Multi-stage Dockerfile for Frontend (Optimized)
# ============================================

# Stage 1: Build assets (placeholder for future build tools)
FROM node:18-alpine AS builder
WORKDIR /app
COPY index.html .
# Future: COPY package.json and run build step here

# Stage 2: Production nginx (minimal image)
FROM nginx:alpine-slim AS production

# Remove default nginx config
RUN rm -rf /usr/share/nginx/html/*

# Copy built assets
COPY --from=builder /app/index.html /usr/share/nginx/html/index.html

# Custom nginx config for SPA routing and security headers
RUN echo 'server { \
    listen 80; \
    server_name _; \
    root /usr/share/nginx/html; \
    \
    # Security headers \
    add_header X-Frame-Options "SAMEORIGIN" always; \
    add_header X-Content-Type-Options "nosniff" always; \
    add_header X-XSS-Protection "1; mode=block" always; \
    \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
    \
    location /api/ { \
        proxy_pass http://backend-service:3000; \
    } \
}' > /etc/nginx/conf.d/default.conf

# Security: run as non-root
RUN chown -R nginx:nginx /usr/share/nginx/html
USER nginx

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:80/ || exit 1
