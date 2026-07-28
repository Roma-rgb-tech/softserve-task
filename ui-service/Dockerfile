FROM nginx:stable-alpine
EXPOSE 80
ENV BACKEND_HOST=backend
COPY nginx.conf.template /etc/nginx/templates/nginx.conf.template
COPY index.html /usr/share/nginx/html/index.html
HEALTHCHECK --interval=30s --timeout=3s CMD wget -q --spider http://localhost:80/ || exit 1
CMD ["sh", "-c", "envsubst '$${BACKEND_HOST}' < /etc/nginx/templates/nginx.conf.template > /etc/nginx/nginx.conf && nginx -g 'daemon off;'"]