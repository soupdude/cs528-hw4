#!/usr/bin/env python3
"""Download the web server VM's per-minute metrics from Cloud Monitoring as a CSV.

Run on your laptop (uses your gcloud login; standard library only):
    python3 scripts/fetch_metrics.py
    python3 scripts/fetch_metrics.py --start 2026-10-13T20:10:00Z --end 2026-10-13T20:35:00Z

Writes metrics.csv with columns: time_et, metric, value
  cpu_percent        VM CPU utilization (%)                  compute.googleapis.com
  mem_used_mb        VM memory in use (MB)                   Ops Agent
  mem_used_percent   VM memory in use (%)                    Ops Agent
  server_rss_mb      server.py process resident memory (MB)  Ops Agent
  net_sent_kBps      bytes sent per second (kB/s)            compute.googleapis.com
  net_recv_kBps      bytes received per second (kB/s)        compute.googleapis.com
"""
import argparse
import csv
import json
import subprocess
import urllib.parse
import urllib.request
from datetime import datetime
from zoneinfo import ZoneInfo

ET = ZoneInfo("America/New_York")


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout.strip()


def fetch(project, token, flt, aligner, start, end):
    """Return all time series matching flt, aligned to 60-second points."""
    series, page = [], None
    while True:
        params = {
            "filter": flt,
            "interval.startTime": start,
            "interval.endTime": end,
            "aggregation.alignmentPeriod": "60s",
            "aggregation.perSeriesAligner": aligner,
        }
        if page:
            params["pageToken"] = page
        url = (f"https://monitoring.googleapis.com/v3/projects/{project}/timeSeries?"
               + urllib.parse.urlencode(params))
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req) as resp:
            data = json.load(resp)
        series += data.get("timeSeries", [])
        page = data.get("nextPageToken")
        if not page:
            return series


def points(ts):
    for p in ts.get("points", []):
        v = p["value"]
        val = v.get("doubleValue", v.get("int64Value"))
        yield p["interval"]["endTime"], float(val)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="project-f131ec20-0df6-4cfa-bf0")
    ap.add_argument("--vm", default="web-server-hw4")
    ap.add_argument("--zone", default="us-central1-b")
    ap.add_argument("--start", default="2026-10-13T20:10:00Z")   # 16:10 ET
    ap.add_argument("--end", default="2026-10-13T20:35:00Z")     # 16:35 ET
    ap.add_argument("--out", default="metrics.csv")
    a = ap.parse_args()

    token = sh("gcloud", "auth", "print-access-token")
    vm_id = sh("gcloud", "compute", "instances", "describe", a.vm, f"--zone={a.zone}",
               f"--project={a.project}", "--format=value(id)")
    by_name = f'metric.labels.instance_name="{a.vm}"'
    by_id = f'resource.labels.instance_id="{vm_id}"'

    # (output name, filter, aligner, scale, which series to keep)
    queries = [
        ("cpu_percent", f'metric.type="compute.googleapis.com/instance/cpu/utilization" AND {by_name}',
         "ALIGN_MEAN", 100.0, None),
        ("mem_used_mb", f'metric.type="agent.googleapis.com/memory/bytes_used" AND metric.labels.state="used" AND {by_id}',
         "ALIGN_MEAN", 1 / 1e6, None),
        ("mem_used_percent", f'metric.type="agent.googleapis.com/memory/percent_used" AND metric.labels.state="used" AND {by_id}',
         "ALIGN_MEAN", 1.0, None),
        ("server_rss_mb", f'metric.type="agent.googleapis.com/processes/rss_usage" AND {by_id}',
         "ALIGN_MEAN", 1 / 1e6, lambda ts: "server.py" in ts["metric"]["labels"].get("command_line", "")),
        ("net_sent_kBps", f'metric.type="compute.googleapis.com/instance/network/sent_bytes_count" AND {by_name}',
         "ALIGN_RATE", 1 / 1e3, None),
        ("net_recv_kBps", f'metric.type="compute.googleapis.com/instance/network/received_bytes_count" AND {by_name}',
         "ALIGN_RATE", 1 / 1e3, None),
    ]

    rows = []
    for name, flt, aligner, scale, keep in queries:
        try:
            series = fetch(a.project, token, flt, aligner, a.start, a.end)
        except urllib.error.HTTPError as e:
            print(f"{name}: request failed ({e.code}): {e.read().decode()[:200]}")
            continue
        if keep:
            series = [s for s in series if keep(s)]
        # Several series (e.g. one per network interface) are summed per minute.
        per_time = {}
        for s in series:
            for t, v in points(s):
                per_time[t] = per_time.get(t, 0.0) + v * scale
        print(f"{name}: {len(series)} series, {len(per_time)} points")
        for t, v in per_time.items():
            et = datetime.fromisoformat(t.replace("Z", "+00:00")).astimezone(ET)
            rows.append((et.strftime("%H:%M:%S"), name, round(v, 3)))

    rows.sort()
    with open(a.out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["time_et", "metric", "value"])
        w.writerows(rows)
    print(f"wrote {len(rows)} rows to {a.out}")


if __name__ == "__main__":
    main()
