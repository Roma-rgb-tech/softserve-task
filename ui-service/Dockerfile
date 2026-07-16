FROM nginx:stable-alpine
EXPOSE 80
COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html
HEALTHCHECK --interval=30s --timeout=3s CMD wget -q --spider http://localhost:80/ || exit 1