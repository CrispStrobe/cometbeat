#!/bin/bash
# Overnight music-DB format enrichment. Safe: nohup-able, resumable jobs,
# timestamped master log. Run: nohup bash bin/overnight.sh >/dev/null 2>&1 &
cd /mnt/volume1/music-db || exit 1
LOG=/mnt/volume1/music-db/logs-overnight.txt
ts(){ date -u +"%Y-%m-%dT%H:%M:%SZ"; }
{
  echo "[$(ts)] ================= OVERNIGHT ENRICH START ================="
  echo "[$(ts)] disk before: $(df -h /mnt/volume1 | tail -1)"
  echo "[$(ts)] --- JOB 1/3: Mutopia PDF + .ly (download) ---"
  python3 bin/job_mutopia.py; echo "[$(ts)] job1 exit=$?"
  echo "[$(ts)] --- JOB 2/3: OpenScore mxl -> MIDI (derive) ---"
  python3 bin/job_mxl2midi.py; echo "[$(ts)] job2 exit=$?"
  echo "[$(ts)] --- JOB 3/3: re-enrich db.json files map ---"
  cp db.json "db.json.bak-$(date -u +%Y%m%d)"
  python3 bin/enrich_files.py; echo "[$(ts)] job3 exit=$?"
  echo "[$(ts)] disk after: $(df -h /mnt/volume1 | tail -1)"
  echo "[$(ts)] ================= OVERNIGHT ENRICH DONE ================="
} >> "$LOG" 2>&1
