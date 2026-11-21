#!/usr/bin/env python3
"""Builds the Grafana dashboards for k3s-apps/argocd/grafana/dashboards.

Usage: scripts/grafana-dashboards.py [dashboards-dir]  (default: argocd/grafana/dashboards, rewritten in place)
Generated from scratch: overview, node-resources (Resources), k8s-workloads, service-reachability (Services & certificates).
Kept and normalised (title, tags, links, refresh, collapsed rows): backups, blocky, blocky-postgres, github-runners;
edit those in Grafana's JSON as before, then rerun this script. Every query was run against Prometheus when it was written.
"""
import json
import pathlib
import sys

SRC = OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "argocd/grafana/dashboards")
DS = {"type": "prometheus", "uid": "prometheus"}
TAG = "homeserver"
LINKS = [{"title": "Dashboards", "type": "dashboards", "tags": [TAG], "asDropdown": False, "includeVars": False,
          "keepTime": True, "targetBlank": False, "icon": "external link"}]
PCT = {"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "#EAB839", "value": 70}, {"color": "red", "value": 90}]}
UPDOWN = [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red"}, "1": {"text": "UP", "color": "green"}}}]
REDGREEN = {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]}
ZERO_OK = {"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "red", "value": 1}]}


def load(name):
    return json.loads((SRC / name).read_text())


class Board:
    def __init__(self):
        self.panels, self.y, self.pid = [], 0, 0

    def add(self, p, x, w, h, newline=False):
        self.pid += 1
        p = dict(p)
        p["id"] = self.pid
        p.setdefault("datasource", DS)
        p["gridPos"] = {"x": x, "y": self.y, "w": w, "h": h}
        self.panels.append(p)
        if newline:
            self.y += h
        return p

    def row(self, title, collapsed=False, repeat=None, inner=None):
        self.pid += 1
        r = {"id": self.pid, "type": "row", "title": title, "collapsed": collapsed, "gridPos": {"x": 0, "y": self.y, "w": 24, "h": 1},
             "panels": []}
        if repeat:
            r["repeat"] = repeat
        self.panels.append(r)
        self.y += 1
        if collapsed and inner:
            # Panels of a collapsed row live inside it, positioned as if expanded.
            y0 = self.y
            for p, x, w, h, nl in inner:
                self.pid += 1
                q = dict(p)
                q["id"] = self.pid
                q.setdefault("datasource", DS)
                q["gridPos"] = {"x": x, "y": y0, "w": w, "h": h}
                r["panels"].append(q)
                if nl:
                    y0 += h
        return r


def tgt(expr, ref="A", legend="", instant=False, fmt="time_series"):
    t = {"datasource": DS, "expr": expr, "refId": ref, "legendFormat": legend}
    if instant:
        t.update({"instant": True, "range": False, "format": fmt})
    return t


def stat(title, targets, unit="none", desc="", thresholds=None, mappings=None, color_mode="none", text_mode="value_and_name",
         decimals=None, links=None, no_value="0", orientation="auto"):
    d = {"unit": unit, "noValue": no_value, "color": {"mode": "thresholds" if thresholds else "fixed", "fixedColor": "text"},
         "thresholds": thresholds or {"mode": "absolute", "steps": [{"color": "text", "value": None}]}, "mappings": mappings or []}
    if decimals is not None:
        d["decimals"] = decimals
    p = {"type": "stat", "title": title, "description": desc, "targets": targets, "fieldConfig": {"defaults": d, "overrides": []},
         "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}, "textMode": text_mode,
                     "colorMode": color_mode, "graphMode": "none", "justifyMode": "center", "orientation": orientation,
                     "wideLayout": True, "showPercentChange": False}}
    if links:
        p["links"] = links
    return p


def gauge(title, expr, desc=""):
    return {"type": "gauge", "title": title, "description": desc, "targets": [tgt(expr)],
            "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100, "decimals": 0, "thresholds": PCT,
                                         "color": {"mode": "thresholds"}}, "overrides": []},
            "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}, "showThresholdMarkers": True}}


def bargauge_pct(title, targets, desc="", links=None):
    p = {"type": "bargauge", "title": title, "description": desc, "targets": targets,
         "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100, "decimals": 0, "thresholds": PCT,
                                      "color": {"mode": "thresholds"}}, "overrides": []},
         "options": {"orientation": "horizontal", "displayMode": "basic", "showUnfilled": True, "valueMode": "color",
                     "namePlacement": "left", "sizing": "auto", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}}}
    if links:
        p["links"] = links
    return p


def ts(title, targets, unit, desc="", stack=False, total_ref=None, legend_right=True, thresholds_line=None, min0=True):
    overrides = []
    if total_ref:
        overrides.append({"matcher": {"id": "byFrameRefID", "options": total_ref}, "properties": [
            {"id": "custom.lineStyle", "value": {"dash": [6, 4], "fill": "dash"}}, {"id": "custom.fillOpacity", "value": 0},
            {"id": "color", "value": {"mode": "fixed", "fixedColor": "text"}}, {"id": "custom.stacking", "value": {"mode": "none"}}]})
    custom = {"lineWidth": 2, "fillOpacity": 25 if stack else 10, "showPoints": "never", "spanNulls": False,
              "stacking": {"mode": "normal" if stack else "none"}}
    defaults = {"unit": unit, "custom": custom, "color": {"mode": "palette-classic"}}
    if min0:
        defaults["min"] = 0
    if thresholds_line is not None:
        custom["thresholdsStyle"] = {"mode": "line+area"}
        defaults["thresholds"] = {"mode": "absolute", "steps": [{"color": "transparent", "value": None}, {"color": "red", "value": thresholds_line}]}
    legend = {"displayMode": "table", "placement": "right", "calcs": ["lastNotNull", "max"]} if legend_right else \
        {"displayMode": "list", "placement": "bottom", "calcs": []}
    return {"type": "timeseries", "title": title, "description": desc, "targets": targets,
            "fieldConfig": {"defaults": defaults, "overrides": overrides},
            "options": {"legend": legend, "tooltip": {"mode": "multi", "sort": "desc"}}}


def table(title, targets, desc="", rename=None, order=None, exclude=None, overrides=None, sort=None, transformations_extra=None):
    tr = []
    if len(targets) > 1:
        tr.append({"id": "merge", "options": {}})
    ex = {"Time": True}
    ex.update({k: True for k in (exclude or [])})
    tr.append({"id": "organize", "options": {"excludeByName": ex, "renameByName": rename or {},
                                             "indexByName": {k: i for i, k in enumerate(order or [])}}})
    if sort:
        tr.append({"id": "sortBy", "options": {"sort": [{"field": sort[0], "desc": sort[1]}]}})
    tr += transformations_extra or []
    return {"type": "table", "title": title, "description": desc, "targets": targets, "transformations": tr,
            "fieldConfig": {"defaults": {"noValue": "None", "custom": {"align": "auto"}}, "overrides": overrides or []},
            "options": {"showHeader": True, "cellHeight": "sm"}}


def ov(name, props):
    return {"matcher": {"id": "byName", "options": name}, "properties": [{"id": k, "value": v} for k, v in props.items()]}


def var(name, label, query, all_value=None, regex=""):
    v = {"name": name, "label": label, "type": "query", "datasource": DS, "refresh": 2, "multi": True, "includeAll": True,
         "query": {"query": query, "refId": "PrometheusVariableQueryEditor-VariableQuery"}, "definition": query, "regex": regex,
         "sort": 1, "current": {"selected": True, "text": ["All"], "value": ["$__all"]}, "options": []}
    if all_value:
        v["allValue"] = all_value
    return v


def dashboard(uid, title, desc, board, time_from="now-6h", templating=None):
    return {"uid": uid, "title": title, "description": desc, "tags": [TAG], "links": LINKS, "schemaVersion": 39, "version": 1,
            "editable": False, "graphTooltip": 1, "refresh": "1m", "time": {"from": time_from, "to": "now"}, "timezone": "browser",
            "templating": {"list": templating or []}, "annotations": {"list": []}, "panels": board.panels}


def link(title, uid, keep_vars=False):
    return [{"title": title, "url": f"/d/{uid}?${{__url_time_range}}" + ("&${__all_variables}" if keep_vars else "")}]


# --- shared expressions -------------------------------------------------------------------------------------------
H = 'job="node_exporter"'
N = 'job="k3s_node_exporter", node=~"$node"'
H_CORES = f'count(node_cpu_seconds_total{{{H}, mode="idle"}})'
H_CPU_USED = f'sum(1 - rate(node_cpu_seconds_total{{{H}, mode="idle"}}[$__rate_interval]))'
H_CPU_FREE = f'sum(rate(node_cpu_seconds_total{{{H}, mode="idle"}}[$__rate_interval]))'
H_CPU_PCT = f'100 * avg(1 - rate(node_cpu_seconds_total{{{H}, mode="idle"}}[$__rate_interval]))'
H_MEM_T = f'sum(node_memory_MemTotal_bytes{{{H}}})'
H_MEM_A = f'sum(node_memory_MemAvailable_bytes{{{H}}})'
H_MEM_U = f'{H_MEM_T} - {H_MEM_A}'
H_MEM_PCT = f'100 * (1 - {H_MEM_A} / {H_MEM_T})'
N_CORES = f'count by (node) (node_cpu_seconds_total{{{N}, mode="idle"}})'
N_CPU_USED = f'sum by (node) (1 - rate(node_cpu_seconds_total{{{N}, mode="idle"}}[$__rate_interval]))'
N_CPU_FREE = f'sum by (node) (rate(node_cpu_seconds_total{{{N}, mode="idle"}}[$__rate_interval]))'
N_CPU_PCT = f'100 * avg by (node) (1 - rate(node_cpu_seconds_total{{{N}, mode="idle"}}[$__rate_interval]))'
N_MEM_T = f'node_memory_MemTotal_bytes{{{N}}}'
N_MEM_A = f'node_memory_MemAvailable_bytes{{{N}}}'
N_MEM_U = f'{N_MEM_T} - {N_MEM_A}'
N_MEM_PCT = f'100 * (1 - {N_MEM_A} / {N_MEM_T})'
MOUNTS = 'mountpoint=~"/|/mnt/black-hdd|/mnt/red-hdd"'
H_DISK_PCT = f'100 * (1 - node_filesystem_avail_bytes{{{H}, {MOUNTS}}} / node_filesystem_size_bytes{{{H}, {MOUNTS}}})'
H_DISK_USED = f'node_filesystem_size_bytes{{{H}, {MOUNTS}}} - node_filesystem_avail_bytes{{{H}, {MOUNTS}}}'
H_DISK_SIZE = f'node_filesystem_size_bytes{{{H}, {MOUNTS}}}'
H_HDD_BUSY = ('rate(node_disk_io_time_seconds_total{job="node_exporter"}[$__rate_interval]) * on (device) group_left (mountpoint) '
              'label_replace(node_filesystem_size_bytes{job="node_exporter", mountpoint=~"/|/mnt/(black|red)-hdd"} * 0 + 1, '
              '"device", "$1", "device", "/dev/(sd[a-z]+)[0-9]+") * 100')
N_DISK_PCT = f'100 * (1 - node_filesystem_avail_bytes{{{N}, mountpoint="/"}} / node_filesystem_size_bytes{{{N}, mountpoint="/"}})'
KC = 'job="k3s_kubelet_cadvisor", container!="", pod!="", node=~"$node", namespace=~"$namespace"'
PODRE = '(${workload:regex})-[a-z0-9]{8,10}-[a-z0-9]{5}|(${workload:regex})-[a-z0-9]{5}|(${workload:regex})'


def W(e):
    return ('label_replace(label_replace(%s, "workload", "$1", "pod", "(.+)"), '
            '"workload", "$1", "pod", "^(.+?)(-[a-z0-9]{8,10})?-[a-z0-9]{5}$")' % e)


CPU_WL = f'sum by (namespace, workload) ({W(f"rate(container_cpu_usage_seconds_total{{{KC}}}[$__rate_interval])")})'
MEM_WL = f'sum by (namespace, workload) ({W(f"container_memory_working_set_bytes{{{KC}}}")})'
SEL_CORES = f'scalar(sum({N_CORES}))'
SEL_MEM = f'scalar(sum({N_MEM_T}))'
KCP = KC + ', pod=~"' + PODRE + '"'
CPU_POD = f'sum by (namespace, pod, node) (rate(container_cpu_usage_seconds_total{{{KCP}}}[$__rate_interval]))'
MEM_POD = f'sum by (namespace, pod, node) (container_memory_working_set_bytes{{{KCP}}})'
NS = 'namespace=~"$namespace"'
NOT_READY = (f'kube_pod_status_ready{{condition="false", {NS}}} * on (namespace, pod) group_left () '
             f'(kube_pod_status_phase{{phase=~"Running|Pending", {NS}}} == 1)')
RESTARTS_24H = f'round(sum(increase(kube_pod_container_status_restarts_total{{{NS}}}[24h]))) or vector(0)'
OOM_24H = f'round(sum(increase(container_oom_events_total{{job="k3s_kubelet_cadvisor", {NS}}}[24h]))) or vector(0)'
JOBS_FAILED_24H = (f'count((kube_job_status_failed{{{NS}}} > 0) and on (namespace, job_name) '
                   f'(time() - kube_job_created{{{NS}}} < 86400)) or vector(0)')
DEPLOY_UNAVAIL = (f'count(kube_deployment_status_replicas_available{{{NS}}} < kube_deployment_spec_replicas{{{NS}}}) or vector(0)')
SERVICE = 'label_replace(%s, "service", "$1", "instance", "(?:https?://)?([^/]+).*")'

RES_UID, WL_UID, SVC_UID, BK_UID = "monitoring-node-resources", "monitoring-k8s-workloads", "monitoring-service-reachability", "monitoring-backups"
outputs = {}

# --- 1. Resources ---------------------------------------------------------------------------------------------------
b = Board()
b.row("Homeserver (host)")
b.add(stat("CPU (cores)", [tgt(H_CPU_USED, "A", "used"), tgt(H_CPU_FREE, "B", "free"), tgt(H_CORES, "C", "total")], "short",
           "CPU cores of the homeserver, including everything on it (k3s VMs, Docker, services).", decimals=1), 0, 7, 4)
b.add(gauge("CPU used", H_CPU_PCT, "Share of CPU time used across all cores."), 7, 5, 4)
b.add(stat("Memory", [tgt(H_MEM_U, "A", "used"), tgt(H_MEM_A, "B", "available"), tgt(H_MEM_T, "C", "total")], "bytes",
           "Used = total - MemAvailable; available includes reclaimable cache.", decimals=1), 12, 7, 4)
b.add(gauge("Memory used", H_MEM_PCT, "1 - MemAvailable / MemTotal."), 19, 5, 4, newline=True)
b.add(ts("CPU over time (cores)", [tgt(H_CPU_USED, "A", "used"), tgt(H_CORES, "B", "total")], "short",
         "Cores in use; dashed: all cores.", total_ref="B"), 0, 12, 7)
b.add(ts("Memory over time", [tgt(H_MEM_U, "A", "used"), tgt(H_MEM_T, "B", "total")], "bytes",
         "Memory in use; dashed: all memory.", total_ref="B"), 12, 12, 7, newline=True)
b.add(bargauge_pct("Disk used", [tgt(H_DISK_PCT, "A", "{{mountpoint}}")], "System SSD (/), live data (black HDD) and backups (red HDD)."),
      0, 8, 6)
b.add(ts("Disk used over time", [tgt(H_DISK_USED, "A", "{{mountpoint}}")], "bytes", "Used bytes per filesystem; growth shows here first."),
      8, 8, 6)
b.add(ts("Disk busy", [tgt(H_HDD_BUSY, "A", "{{mountpoint}}")], "percent", "Time the disk was busy (I/O time). Near 100 % means "
         "the disk is the bottleneck (saturation, USE).", legend_right=False), 16, 8, 6, newline=True)
b.add(stat("Uptime", [tgt(f'time() - node_boot_time_seconds{{{H}}}', "A", "homeserver")], "s", "Since the last boot.", decimals=1,
           text_mode="value"), 0, 6, 3)
b.add(stat("Load (1 / 5 / 15 min)", [tgt(f'node_load1{{{H}}}', "A", "1m"), tgt(f'node_load5{{{H}}}', "B", "5m"),
                                     tgt(f'node_load15{{{H}}}', "C", "15m")], "short", "Run-queue length; compare with 8 cores.",
           decimals=2), 6, 18, 3, newline=True)

b.row("k3s node: $node", repeat="node")
b.add(stat("CPU (cores)", [tgt(N_CPU_USED, "A", "used"), tgt(N_CPU_FREE, "B", "free"), tgt(N_CORES, "C", "total")], "short",
           "CPU cores of the node VM.", decimals=1), 0, 7, 4)
b.add(gauge("CPU used", N_CPU_PCT), 7, 5, 4)
b.add(stat("Memory", [tgt(N_MEM_U, "A", "used"), tgt(N_MEM_A, "B", "available"), tgt(N_MEM_T, "C", "total")], "bytes",
           "Memory of the node VM.", decimals=1), 12, 7, 4)
b.add(gauge("Memory used", N_MEM_PCT), 19, 5, 4, newline=True)
b.add(ts("CPU over time (cores)", [tgt(N_CPU_USED, "A", "used"), tgt(N_CORES, "B", "total")], "short", total_ref="B"), 0, 12, 7)
b.add(ts("Memory over time", [tgt(N_MEM_U, "A", "used"), tgt(N_MEM_T, "B", "total")], "bytes", total_ref="B"), 12, 12, 7, newline=True)
b.add(gauge("Root disk used", N_DISK_PCT, "The VM's disk (on the homeserver's SSD)."), 0, 6, 4)
b.add(stat("Pods running", [tgt(f'sum(kube_pod_status_phase{{phase="Running"}} * on (namespace, pod) group_left (node) '
                                f'kube_pod_info{{node=~"$node"}})', "A")], "none", text_mode="value"), 6, 6, 4)
b.add(stat("Load (1 / 15 min)", [tgt(f'node_load1{{{N}}}', "A", "1m"), tgt(f'node_load15{{{N}}}', "B", "15m")], "short", decimals=2),
      12, 6, 4)
b.add(stat("Uptime", [tgt(f'time() - node_boot_time_seconds{{{N}}}', "A")], "s", decimals=1, text_mode="value"), 18, 6, 4,
      newline=True)

b.row("Usage by app (nodes: $node)")
for i, (title, expr, unit, desc) in enumerate([
        ("CPU by app (top 12, cores)", CPU_WL, "short", "Container CPU per namespace and app (derived from the Pod name)."),
        ("Memory by app (top 12)", MEM_WL, "bytes", "Working set per namespace and app.")]):
    b.add({"type": "bargauge", "title": title, "description": desc,
           "targets": [tgt(f'sort_desc(topk(12, {expr}))', "A", "{{namespace}} / {{workload}}", instant=True)],
           "fieldConfig": {"defaults": {"unit": unit, "decimals": 2, "min": 0, "color": {"mode": "fixed", "fixedColor": "blue"}},
                           "overrides": []},
           "options": {"orientation": "horizontal", "displayMode": "basic", "showUnfilled": True, "valueMode": "text",
                       "namePlacement": "left", "sizing": "auto", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}}},
          12 * i, 12, 9, newline=(i == 1))
drill = (f"/d/{RES_UID}?${{node:queryparam}}&var-namespace=${{__data.fields.namespace}}&var-workload=${{__data.fields.workload}}"
         "&${__url_time_range}")
pct_cell = {"unit": "percent", "decimals": 1, "max": 100, "custom.cellOptions": {"type": "gauge", "mode": "basic", "valueDisplayMode": "text"},
            "color": {"mode": "fixed", "fixedColor": "blue"}}
b.add(table("Apps (click an app to see its Pods)",
            [tgt(CPU_WL, "A", instant=True, fmt="table"), tgt(f'100 * {CPU_WL} / {SEL_CORES}', "B", instant=True, fmt="table"),
             tgt(MEM_WL, "C", instant=True, fmt="table"), tgt(f'100 * {MEM_WL} / {SEL_MEM}', "D", instant=True, fmt="table")],
            "Shares are of the selected nodes together.",
            rename={"namespace": "namespace", "workload": "app", "Value #A": "CPU (cores)", "Value #B": "CPU %", "Value #C": "memory",
                    "Value #D": "memory %"},
            order=["namespace", "workload", "Value #A", "Value #B", "Value #C", "Value #D"], sort=("memory", True),
            overrides=[ov("CPU (cores)", {"unit": "short", "decimals": 2}), ov("memory", {"unit": "bytes", "decimals": 1}),
                       ov("CPU %", pct_cell), ov("memory %", pct_cell),
                       ov("app", {"links": [{"title": "Pods of this app", "url": drill}]})]), 0, 24, 10, newline=True)
b.row("Pods: $namespace / $workload")
b.add(table("Pods", [tgt(CPU_POD, "A", instant=True, fmt="table"), tgt(MEM_POD, "B", instant=True, fmt="table")],
            rename={"Value #A": "CPU (cores)", "Value #B": "memory"}, order=["namespace", "pod", "node", "Value #A", "Value #B"],
            sort=("memory", True), overrides=[ov("CPU (cores)", {"unit": "short", "decimals": 3}),
                                              ov("memory", {"unit": "bytes", "decimals": 1})]), 0, 24, 8, newline=True)
b.add(ts("CPU per Pod (cores)", [tgt(CPU_POD, "A", "{{pod}}")], "short", "Pick a namespace and app above to narrow down."), 0, 12, 8)
b.add(ts("Memory per Pod", [tgt(MEM_POD, "A", "{{pod}}")], "bytes", "Working set per Pod."), 12, 12, 8, newline=True)
b.row("Docker on the host", collapsed=True, inner=[
    (ts("CPU per container", [tgt('sum by (name) (rate(container_cpu_usage_seconds_total{job="cadvisor", name!=""}[$__rate_interval]))',
                                  "A", "{{name}}")], "short", "Docker containers on the homeserver (cAdvisor), in cores."), 0, 12, 8, False),
    (ts("Memory per container", [tgt('sum by (name) (container_memory_working_set_bytes{job="cadvisor", name!=""})', "A", "{{name}}")],
        "bytes", "Working set per Docker container on the homeserver."), 12, 12, 8, True)])
WL_QUERY = 'query_result(' + MEM_WL + ')'
outputs["node-resources.json"] = dashboard(
    RES_UID, "Resources", "CPU, memory, disks and load of the homeserver and each k3s node; usage by app with drill-down to Pods.", b,
    templating=[var("node", "Node", 'label_values(node_memory_MemTotal_bytes{job="k3s_node_exporter"}, node)'),
                var("namespace", "Namespace", 'label_values(container_memory_working_set_bytes{job="k3s_kubelet_cadvisor", container!="", '
                                              'node=~"$node"}, namespace)'),
                var("workload", "App", WL_QUERY, all_value=".*", regex='/workload="([^"]+)"/')])

# --- 2. Kubernetes workloads ----------------------------------------------------------------------------------------
b = Board()
b.row("Now")
for i, (title, expr, desc, thr) in enumerate([
        ("Pods running", f'sum(kube_pod_status_phase{{phase="Running", {NS}}})', "Pods in phase Running.", None),
        ("Pods not ready", f'sum({NOT_READY}) or vector(0)', "Running or Pending Pods whose readiness is false.", ZERO_OK),
        ("Container restarts (24 h)", RESTARTS_24H, "Restarts across all containers in the last 24 hours; a reboot of the "
         "homeserver restarts many at once.", None),
        ("OOM kills (24 h)", OOM_24H, "Containers killed for exceeding their memory limit.", ZERO_OK),
        ("Deployments short of replicas", DEPLOY_UNAVAIL, "Deployments with fewer available than desired replicas.", ZERO_OK),
        ("Jobs failed (24 h)", JOBS_FAILED_24H, "Jobs created in the last 24 hours with at least one failed Pod.", ZERO_OK)]):
    b.add(stat(title, [tgt(expr)], "none", desc, thresholds=thr, color_mode="background" if thr else "none", text_mode="value",
               decimals=0), 4 * i, 4, 4, newline=(i == 5))
b.row("Needs attention")
b.add(table("Pods not ready", [tgt(f'{NOT_READY} == 1', "A", instant=True, fmt="table")],
            "Running or Pending Pods that aren't ready.", exclude=["Value", "__name__", "condition", "job", "instance", "uid"],
            order=["namespace", "pod"]), 0, 8, 8)
b.add(table("Restarts in the last 24 h", [tgt(f'round(increase(kube_pod_container_status_restarts_total{{{NS}}}[24h])) > 0', "A",
                                              instant=True, fmt="table")],
            "Per container, highest first.", exclude=["__name__", "job", "instance", "uid"], rename={"Value": "restarts"},
            order=["namespace", "pod", "container", "Value"], sort=("restarts", True)), 8, 8, 8)
b.add(table("Waiting containers", [tgt(f'kube_pod_container_status_waiting_reason{{{NS}}} == 1', "A", instant=True, fmt="table")],
            "Containers that can't start, with the reason (e.g. CrashLoopBackOff, ImagePullBackOff).",
            exclude=["Value", "__name__", "job", "instance", "uid"], order=["namespace", "pod", "container", "reason"]), 16, 8, 8,
      newline=True)
b.row("Trends")
b.add(ts("Restarts per hour by namespace", [tgt(f'sum by (namespace) (round(increase(kube_pod_container_status_restarts_total{{{NS}}}[1h])))',
                                                "A", "{{namespace}}")], "none", stack=True), 0, 12, 8)
b.add(ts("OOM kills per hour by namespace", [tgt(f'sum by (namespace) (round(increase(container_oom_events_total{{job="k3s_kubelet_cadvisor", '
                                                 f'{NS}}}[1h])))', "A", "{{namespace}}")], "none", stack=True), 12, 12, 8, newline=True)
b.row("Deployments and CronJobs")
b.add(table("Deployments", [tgt(f'kube_deployment_status_replicas_available{{{NS}}}', "A", instant=True, fmt="table"),
                            tgt(f'kube_deployment_spec_replicas{{{NS}}}', "B", instant=True, fmt="table")],
            "Available vs. desired replicas.", exclude=["__name__", "job", "instance"],
            rename={"Value #A": "available", "Value #B": "desired"}, order=["namespace", "deployment", "Value #A", "Value #B"],
            sort=("namespace", False)), 0, 12, 10)
b.add(table("CronJobs", [tgt(f'time() - kube_cronjob_status_last_successful_time{{{NS}}}', "A", instant=True, fmt="table"),
                         tgt(f'time() - kube_cronjob_status_last_schedule_time{{{NS}}}', "B", instant=True, fmt="table"),
                         tgt(f'kube_cronjob_spec_suspend{{{NS}}}', "C", instant=True, fmt="table")],
            "Time since the last successful and the last scheduled run.", exclude=["__name__", "job", "instance"],
            rename={"Value #A": "last success", "Value #B": "last run", "Value #C": "suspended"},
            order=["namespace", "cronjob", "Value #A", "Value #B", "Value #C"], sort=("last success", True),
            overrides=[ov("last success", {"unit": "s", "decimals": 1}), ov("last run", {"unit": "s", "decimals": 1}),
                       ov("suspended", {"mappings": [{"type": "value", "options": {"0": {"text": "no"}, "1": {"text": "yes", "color": "orange"}}}]})]),
      12, 12, 10, newline=True)
outputs["k8s-workloads.json"] = dashboard(
    WL_UID, "Kubernetes workloads", "Pod health across the cluster: not-ready Pods, restarts, OOM kills, failed jobs, deployments, CronJobs.",
    b, time_from="now-24h", templating=[var("namespace", "Namespace", 'label_values(kube_pod_info, namespace)')])

# --- 3. Services & certificates -------------------------------------------------------------------------------------
b = Board()
b.add(stat("Status now", [tgt(SERVICE % "probe_success", "A", "{{service}}")], "none", "blackbox_exporter probes from the homeserver.",
           thresholds=REDGREEN, mappings=UPDOWN, color_mode="background", text_mode="name", no_value="NO DATA"), 0, 24, 4, newline=True)
b.add({"type": "state-timeline", "title": "Availability", "description": "Green: probe succeeded; red: failed.",
       "targets": [tgt(SERVICE % "probe_success", "A", "{{service}}")],
       "fieldConfig": {"defaults": {"mappings": UPDOWN, "thresholds": REDGREEN, "color": {"mode": "thresholds"},
                                    "custom": {"fillOpacity": 80, "lineWidth": 0}}, "overrides": []},
       "options": {"showValue": "never", "rowHeight": 0.8, "mergeValues": True, "alignValue": "left", "legend": {"showLegend": False}}},
      0, 24, 9, newline=True)
b.add(ts("Response time", [tgt(SERVICE % "probe_duration_seconds", "A", "{{service}}")], "s", "Whole probe incl. DNS, TCP, TLS."),
      0, 14, 9)
b.add(table("TLS certificates", [tgt(SERVICE % "(probe_ssl_earliest_cert_expiry - time()) / 86400", "A", instant=True, fmt="table"),
                                 tgt(SERVICE % "probe_ssl_earliest_cert_expiry * 1000", "B", instant=True, fmt="table")],
            "Days until the earliest certificate in the chain expires; red under 14, yellow under 30.",
            exclude=["instance", "job", "__name__", "module"], rename={"Value #A": "days left", "Value #B": "expires"},
            order=["service", "Value #A", "Value #B"], sort=("days left", False),
            overrides=[ov("days left", {"unit": "none", "decimals": 0, "custom.cellOptions": {"type": "color-background"},
                                        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None},
                                                                                      {"color": "#EAB839", "value": 14},
                                                                                      {"color": "green", "value": 30}]}}),
                       ov("expires", {"unit": "dateTimeAsIsoNoDateIfToday"})]), 14, 10, 9, newline=True)
outputs["service-reachability.json"] = dashboard(
    SVC_UID, "Services & certificates", "Reachability, response time and TLS certificate expiry of the public endpoints.", b,
    time_from="now-24h")

# --- 0. Overview (home) ---------------------------------------------------------------------------------------------
b = Board()
ALL_NS = 'namespace=~".*"'
NOT_READY_ALL = NOT_READY.replace(NS, ALL_NS)
ALL_NODES = 'node=~".+"'


def updown(title, targets, desc, links, text_mode="name"):
    return stat(title, targets, "none", desc, thresholds=REDGREEN, mappings=UPDOWN, color_mode="background", text_mode=text_mode,
                links=links, no_value="NO DATA")


b.row("Status")
b.add(stat("Firing alerts", [tgt('count(ALERTS{alertstate="firing"}) or vector(0)', "A", "alerts")], "none",
           "Alerts firing right now; the list is at the bottom.", thresholds=ZERO_OK, color_mode="background", text_mode="value",
           decimals=0), 0, 4, 4)
b.add(stat("Pods not ready", [tgt(f'sum({NOT_READY_ALL}) or vector(0)')], "none", "Running or Pending Pods that aren't ready.",
           thresholds=ZERO_OK, color_mode="background", text_mode="value", decimals=0, links=link("Kubernetes workloads", WL_UID)), 4, 4, 4)
b.add(stat("Restarts (24 h)", [tgt(RESTARTS_24H.replace(NS, ALL_NS))], "none", "Container restarts in the last 24 hours.",
           text_mode="value", decimals=0, links=link("Kubernetes workloads", WL_UID)), 8, 4, 4)
b.add(stat("Up since", [tgt('time() - node_boot_time_seconds{job="node_exporter"}', "A", "homeserver"),
                        tgt('time() - node_boot_time_seconds{job="k3s_node_exporter"}', "B", "{{node}}")], "s",
           "Time since the last boot.", decimals=1, no_value="NO DATA"), 12, 12, 4, newline=True)
b.add(updown("Infrastructure", [
    tgt('up{job="node_exporter"}', "A", "homeserver"),
    tgt('kube_node_status_condition{condition="Ready", status="true"}', "B", "{{node}}"),
    tgt('min(time() - max by (name) (container_last_seen{job="cadvisor", name!="", '
        'name!~"nextcloud-aio-(borgbackup|watchtower)"}) < bool 120)', "C", "host containers"),
    tgt('min(up)', "D", "monitoring targets"),
    tgt('sum(github_runners{state="offline"}) == bool 0', "E", "CI runners")],
    "Homeserver and nodes up, host containers seen, every scrape target up, no offline runner.", link("Resources", RES_UID)), 0, 24, 4,
    newline=True)
b.add(updown("Public services", [tgt(SERVICE % "probe_success", "A", "{{service}}")], "blackbox probes.",
             link("Services & certificates", SVC_UID)), 0, 24, 4, newline=True)
b.add(updown("Apps", [tgt('kube_deployment_status_replicas_available{namespace=~"apps|auth"} >= bool '
                          'kube_deployment_spec_replicas{namespace=~"apps|auth"}', "A", "{{deployment}}")],
             "Deployments in apps and auth with all replicas available.", link("Kubernetes workloads", WL_UID)), 0, 24, 5, newline=True)
b.add(updown("Cluster services", [
    tgt('kube_deployment_status_replicas_available{namespace=~"kube-system|monitoring"} >= bool '
        'kube_deployment_spec_replicas{namespace=~"kube-system|monitoring"}', "A", "{{deployment}}"),
    tgt('label_replace(kube_daemonset_status_number_ready >= bool kube_daemonset_status_desired_number_scheduled, '
        '"daemonset", "lb $1", "daemonset", "svclb-(.+)-[0-9a-f]{8}")', "B", "{{daemonset}}")],
    "Cluster deployments and DaemonSets fully available.", link("Kubernetes workloads", WL_UID)), 0, 24, 5, newline=True)
b.add(stat("Backups (time since last success)", [tgt("time() - backup:last_success_timestamp_seconds", "A", "{{backup}}")], "s",
           "Red past the 26 h alert threshold.", decimals=1, color_mode="background", no_value="NO DATA",
           thresholds={"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "red", "value": 93600}]},
           links=link("Backups", BK_UID)), 0, 24, 4, newline=True)
b.row("Resources at a glance")
b.add(bargauge_pct("CPU used", [tgt(H_CPU_PCT, "A", "homeserver"), tgt(N_CPU_PCT.replace('node=~"$node"', ALL_NODES), "B", "{{node}}")],
                   links=link("Resources", RES_UID)), 0, 8, 6)
b.add(bargauge_pct("Memory used", [tgt(H_MEM_PCT, "A", "homeserver"), tgt(N_MEM_PCT.replace('node=~"$node"', ALL_NODES), "B", "{{node}}")],
                   links=link("Resources", RES_UID)), 8, 8, 6)
b.add(bargauge_pct("Disk used", [tgt(H_DISK_PCT, "A", "homeserver {{mountpoint}}"),
                                 tgt(N_DISK_PCT.replace('node=~"$node"', ALL_NODES), "B", "{{node}} /")],
                   links=link("Resources", RES_UID)), 16, 8, 6, newline=True)
b.row("Firing alerts")
b.add(table("Firing alerts", [tgt('ALERTS{alertstate="firing"}', "A", instant=True, fmt="table")], "Empty when all is well.",
            exclude=["Value", "__name__", "alertstate", "job"], order=["alertname", "severity"]), 0, 24, 6, newline=True)
outputs["overview.json"] = dashboard("monitoring-overview", "Overview", "Is everything fine? Status of hosts, services, apps and backups; "
                                     "links lead to the detail dashboards.", b, time_from="now-1h")

# --- polished existing dashboards -----------------------------------------------------------------------------------


def polish(name, title, desc, collapse=()):
    d = load(name)
    d.update({"title": title, "description": desc, "tags": [TAG], "links": LINKS, "refresh": "1m", "editable": False, "graphTooltip": 1})
    if collapse:
        panels, out, current = d["panels"], [], None
        for p in sorted(panels, key=lambda p: (p["gridPos"]["y"], p["gridPos"]["x"])):
            if p["type"] == "row":
                current = p
                if p["title"] in collapse:
                    p["collapsed"] = True
                    p["panels"] = p.get("panels", [])
                out.append(p)
            elif current is not None and current.get("collapsed"):
                current["panels"].append(p)
            else:
                out.append(p)
        d["panels"] = out
    return d


bk = polish("backups.json", "Backups", "Age of every backup (host marker files and k3s CronJobs); the alert fires past 26 h.")
for p in bk["panels"]:
    p.setdefault("description", "")
outputs["backups.json"] = bk
outputs["blocky.json"] = polish("blocky.json", "DNS – Blocky", "LAN DNS with ad blocking: queries, blocking, latency, cache.",
                                collapse=("Cache & prefetching", "DNSSEC", "Rate limiting", "Go runtime"))
bp = polish("blocky-postgres.json", "DNS – Query log", "Blocky's query log in PostgreSQL: top domains and clients, recent queries.")
for p in bp["panels"]:
    if p.get("title") == "Client Actvity":
        p["title"] = "Client activity"
outputs["blocky-postgres.json"] = bp
outputs["github-runners.json"] = polish("github-runners.json", "CI – GitHub runners",
                                        "Self-hosted GitHub Actions runners (ARC) on k3s-node-2: Pods, GitHub's view, activity, node load.")

OUT.mkdir(parents=True, exist_ok=True)
for name, d in outputs.items():
    (OUT / name).write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
print(" ".join(sorted(outputs)))
