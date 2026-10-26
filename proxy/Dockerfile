FROM nginx:1.28-alpine

COPY default.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080 8443

CMD ["nginx", "-g", "daemon off;"]