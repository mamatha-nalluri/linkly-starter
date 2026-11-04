FROM nginxinc/nginx-unprivileged:1.27-alpine
USER root
RUN mkdir -p /etc/nginx/certs && chown -R 101:101 /etc/nginx/certs
COPY --chown=101:101 default.conf /etc/nginx/conf.d/default.conf
COPY --chown=101:101 index.html /usr/share/nginx/html/index.html
USER 101:101
EXPOSE 8080 8443
HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD ["wget","-q","-O","/dev/null","http://127.0.0.1:8080/healthz"]
