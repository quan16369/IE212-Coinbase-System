FROM grafana/grafana:latest

COPY config/datasource.yaml /etc/grafana/provisioning/datasources/
COPY dashboards/dashboard.yaml /etc/grafana/provisioning/dashboards/
COPY grafana.ini /etc/grafana/grafana.ini

ENV GF_SECURITY_ADMIN_USER=admin
ENV GF_SECURITY_ADMIN_PASSWORD=admin
ENV GF_AUTH_ANONYMOUS_ENABLED=true

USER grafana
