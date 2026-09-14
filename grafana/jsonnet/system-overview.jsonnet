local grafana = import 'grafonnet-latest/main.libsonnet';

local dashboard = grafana.dashboard;
local stat = grafana.panel.stat;
local timeseries = grafana.panel.timeSeries;
local prometheus = grafana.query.prometheus;

dashboard.new('Jsonnet System Overview')
+ dashboard.withUid('jsonnet_system_overview')
+ dashboard.withTags([
  'jsonnet',
  'grafonnet',
  'prometheus',
])
+ dashboard.withPanels([
  (
    stat.new('Uptime')
    + stat.queryOptions.withTargets([
        prometheus.new(
          'prometheus',
          'node_time_seconds - node_boot_time_seconds',
        ),
      ])
    + stat.standardOptions.withUnit('s')
  )
  {
    gridPos+: {
      h: 8,
      w: 8,
      x: 0,
      y: 0,
    },
  },

  (
    timeseries.new('CPU Usage')
    + timeseries.queryOptions.withTargets([
        prometheus.new(
          'prometheus',
          '100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)',
        ),
      ])
    + timeseries.standardOptions.withUnit('percent')
  )
  {
    gridPos+: {
      h: 8,
      w: 16,
      x: 8,
      y: 0,
    },
  },
])