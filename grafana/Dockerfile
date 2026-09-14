FROM grafana/grafana:13.2.1

USER root

RUN grafana cli plugins install grafana-googlesheets-datasource \
    && grafana cli plugins install briangann-gauge-panel

USER grafana
