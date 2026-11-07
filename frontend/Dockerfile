# syntax=docker/dockerfile:1
FROM node:24.22.1-alpine@sha256:06d7adf3e0ef61a13f1d28682726366f97a15aa1888c934d3ecec86c33918b53 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
ARG VITE_VERSION=dev
ENV VITE_VERSION=${VITE_VERSION}
RUN npm run build

FROM nginxinc/nginx-unprivileged@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
# Paquetes de Alpine al día: la base 1.30.6 trae brotli 1.2.0 (CVE-2026-111497, crítica) y otras corregidas
# aguas arriba que aún no llegan a una imagen publicada de nginx (análisis SUP03).
USER root
RUN apk upgrade --no-cache
USER 101
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY seguridad.conf /etc/nginx/seguridad.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 8080
