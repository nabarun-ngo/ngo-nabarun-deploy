#!/usr/bin/env bash
#
# Runs one operation for .github/workflows/ops-gcp-ops.yml.
#
# Required environment:
#   OPERATION       download-logs | restart-service | view-versions |
#                   cleanup-versions | cleanup-gcs | cleanup-registry
#   GCP_PROJECT_ID  Target project (environment secret).
#   TARGET_ENV      Environment name, used in artifact names.
#   DRY_RUN         "true" skips every destructive call.
#
# Per-operation environment:
#   SERVICE_NAME    GAE service for restart-service.
#   LOG_FILTER / LOG_SEVERITY / LAST_HOURS / LOG_FORMAT   download-logs.
#   KEEP_VERSIONS   Newest versions retained by cleanup-versions.
#   STALE_DAYS      Age cutoff in days for cleanup-gcs; newer files are kept.
#
# Writes result_summary and (when a report is produced) artifact_name to
# $GITHUB_OUTPUT. Report files are left in the working directory for upload.

set -euo pipefail

ARTIFACT_NAME=""
RESULT_SUMMARY=""

case "$OPERATION" in
  download-logs)
    echo "Fetching Cloud Logging entries..."

    START_TIME=$(date -u -d "${LAST_HOURS} hours ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
      || date -u -v-"${LAST_HOURS}H" '+%Y-%m-%dT%H:%M:%SZ')

    FULL_FILTER="${LOG_FILTER} AND severity>=${LOG_SEVERITY} AND timestamp>=\"${START_TIME}\""

    case "$LOG_FORMAT" in
      json)
        FORMAT_FLAG="json"
        OUT_FILE="cloud-logs.json"
        ;;
      csv)
        FORMAT_FLAG="csv"
        OUT_FILE="cloud-logs.csv"
        ;;
      *)
        FORMAT_FLAG="text"
        OUT_FILE="cloud-logs.txt"
        ;;
    esac

    gcloud logging read "$FULL_FILTER" \
      --project="$GCP_PROJECT_ID" \
      --format="$FORMAT_FLAG" \
      --freshness="${LAST_HOURS}h" \
      > "$OUT_FILE" 2>&1

    ENTRY_COUNT=$(wc -l < "$OUT_FILE" | xargs)
    ARTIFACT_NAME="cloud-logs-${TARGET_ENV}-${GITHUB_RUN_ID}"

    RESULT_SUMMARY="Downloaded $ENTRY_COUNT lines of logs | Filter: $LOG_FILTER | Severity: $LOG_SEVERITY | Window: last ${LAST_HOURS}h"
    echo "result_summary=$RESULT_SUMMARY" >> "$GITHUB_OUTPUT"
    echo "artifact_name=$ARTIFACT_NAME" >> "$GITHUB_OUTPUT"
    ;;

  restart-service)
    echo "Restarting GAE service: $SERVICE_NAME..."

    # List instances with their actual version — format: VERSION<TAB>INSTANCE_ID
    INSTANCES=$(gcloud app instances list \
      --service="$SERVICE_NAME" \
      --project="$GCP_PROJECT_ID" \
      --format='value(version,id)' 2>/dev/null || true)

    BEFORE_COUNT=$(printf '%s\n' "$INSTANCES" | grep -c '[^[:space:]]' || true)
    BEFORE_COUNT=${BEFORE_COUNT:-0}

    if [[ -z "$INSTANCES" ]]; then
      echo "No instances to stop (service may auto-scale to zero)"
    else
      while IFS=$'\t' read -r VERSION INSTANCE_ID; do
        if [[ -z "$INSTANCE_ID" ]]; then continue; fi
        echo "Deleting instance $INSTANCE_ID (version: $VERSION)..."
        gcloud app instances delete "$INSTANCE_ID" \
          --service="$SERVICE_NAME" \
          --version="$VERSION" \
          --project="$GCP_PROJECT_ID" \
          --quiet 2>/dev/null || true
      done <<< "$INSTANCES"
    fi

    sleep 10

    AFTER_COUNT=$(gcloud app instances list \
      --service="$SERVICE_NAME" \
      --project="$GCP_PROJECT_ID" \
      --format='value(id)' 2>/dev/null | wc -l | xargs)

    RESULT_SUMMARY="Service: $SERVICE_NAME | Pre-restart instances: $BEFORE_COUNT | Post-restart instances: $AFTER_COUNT"
    echo "result_summary=$RESULT_SUMMARY" >> "$GITHUB_OUTPUT"
    ;;

  view-versions)
    echo "Listing GAE versions..."

    gcloud app versions list \
      --project="$GCP_PROJECT_ID" \
      --format='table(service,id,traffic_split,last_deployed_time.date(tz=UTC),serving_status)' \
      > versions-report.txt 2>&1

    cat versions-report.txt
    ARTIFACT_NAME="versions-report-${TARGET_ENV}-${GITHUB_RUN_ID}"
    RESULT_SUMMARY="Version list generated — see artifact for details"
    echo "result_summary=$RESULT_SUMMARY" >> "$GITHUB_OUTPUT"
    echo "artifact_name=$ARTIFACT_NAME" >> "$GITHUB_OUTPUT"
    ;;

  cleanup-versions)
    echo "Cleaning up old GAE versions without traffic (keep newest: $KEEP_VERSIONS)..."

    SERVICES=$(gcloud app services list \
      --project="$GCP_PROJECT_ID" \
      --format='value(id)' 2>/dev/null)

    TOTAL_DELETED=0
    {
      echo "# GAE Version Cleanup Report"
      echo "Keep: $KEEP_VERSIONS versions | Dry run: $DRY_RUN"
      echo ""
    } > versions-cleanup.txt

    while IFS= read -r SVC; do
      [[ -z "$SVC" ]] && continue

      # traffic_split is the field that identifies the live version;
      # TRAFFIC_SPLIT/SERVING_STATUS are table column headings, not projection
      # keys, and resolve to nothing.
      VERSIONS=$(gcloud app versions list \
        --service="$SVC" \
        --project="$GCP_PROJECT_ID" \
        --format='value(id,traffic_split)' \
        --sort-by='~creationTime' 2>/dev/null)

      # Keep anything serving traffic and the newest KEEP_VERSIONS.
      POSITION=0
      KEEP_COUNT=0
      DELETABLE=()
      while IFS=$'\t' read -r VID SPLIT; do
        if [[ -z "$VID" ]]; then continue; fi
        (( ++POSITION ))
        SPLIT="${SPLIT//[[:space:]]/}"

        if [[ ! "$SPLIT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          echo "::warning::Could not read the traffic split for ${SVC}/${VID}; keeping it."
          (( ++KEEP_COUNT ))
        elif [[ ! "$SPLIT" =~ ^0(\.0+)?$ ]]; then
          (( ++KEEP_COUNT ))
        elif (( POSITION <= KEEP_VERSIONS )); then
          (( ++KEEP_COUNT ))
        else
          DELETABLE+=("$VID")
        fi
      done <<< "$VERSIONS"

      echo "Service $SVC: keeping $KEEP_COUNT, deleting ${#DELETABLE[@]}" | tee -a versions-cleanup.txt

      if [[ ${#DELETABLE[@]} -gt 0 && "$DRY_RUN" == "false" ]]; then
        gcloud app versions delete "${DELETABLE[@]}" \
          --service="$SVC" \
          --project="$GCP_PROJECT_ID" \
          --quiet || true
        TOTAL_DELETED=$(( TOTAL_DELETED + ${#DELETABLE[@]} ))
      fi
    done <<< "$SERVICES"

    ARTIFACT_NAME="versions-cleanup-${TARGET_ENV}-${GITHUB_RUN_ID}"
    RESULT_SUMMARY="Deleted $TOTAL_DELETED version(s) across all services | Dry run: $DRY_RUN"
    echo "result_summary=$RESULT_SUMMARY" >> "$GITHUB_OUTPUT"
    echo "artifact_name=$ARTIFACT_NAME" >> "$GITHUB_OUTPUT"
    ;;

  cleanup-gcs)
    echo "Cleaning stale GCS staging files..."
    STAGING_BUCKET="staging.${GCP_PROJECT_ID}.appspot.com"

    # Age cutoff matching scripts/gcp-cleanup-gcs.sh: the staging blobs of an
    # in-flight deploy must survive an interactive cleanup.
    CUTOFF_DATE=$(date -u -d "${STALE_DAYS} days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
      || date -u -v-"${STALE_DAYS}d" '+%Y-%m-%dT%H:%M:%SZ')

    FILES=$(gsutil ls -l "gs://${STAGING_BUCKET}/**" 2>/dev/null \
      | awk -v cutoff="$CUTOFF_DATE" 'NF==3 && $2 < cutoff {print $2, $3}' \
      | sort -k1 | head -100 || echo "")

    COUNT=0
    {
      echo "# GCS Staging Cleanup"
      echo "Bucket: gs://${STAGING_BUCKET}"
      echo "Older than: ${STALE_DAYS}d (created before ${CUTOFF_DATE})"
      echo ""
    } > gcs-cleanup.txt

    while read -r _ FILEPATH; do
      if [[ -z "$FILEPATH" ]]; then continue; fi
      echo "$FILEPATH" >> gcs-cleanup.txt
      if [[ "$DRY_RUN" == "false" ]]; then
        gsutil rm "$FILEPATH" 2>/dev/null || true
      fi
      (( ++COUNT ))
    done < <(printf '%s\n' "$FILES")

    ARTIFACT_NAME="gcs-cleanup-${TARGET_ENV}-${GITHUB_RUN_ID}"
    RESULT_SUMMARY="Processed $COUNT file(s) older than ${STALE_DAYS}d in gs://$STAGING_BUCKET | Dry run: $DRY_RUN"
    echo "result_summary=$RESULT_SUMMARY" >> "$GITHUB_OUTPUT"
    echo "artifact_name=$ARTIFACT_NAME" >> "$GITHUB_OUTPUT"
    ;;

  cleanup-registry)
    echo "Pruning untagged Artifact Registry images..."

    REPOS=$(gcloud artifacts repositories list \
      --project="$GCP_PROJECT_ID" \
      --format='value(name)' 2>/dev/null || echo "")

    {
      echo "# Artifact Registry Cleanup"
      echo "Dry run: $DRY_RUN"
      echo ""
    } > ar-cleanup.txt

    TOTAL=0
    while IFS= read -r REPO; do
      [[ -z "$REPO" ]] && continue
      UNTAGGED=$(gcloud artifacts docker images list "$REPO" \
        --project="$GCP_PROJECT_ID" \
        --filter="tags=''" \
        --format='value(IMAGE)' 2>/dev/null | head -50 || echo "")

      COUNT=$(printf '%s\n' "$UNTAGGED" | grep -c '[^[:space:]]' || true)
      COUNT=${COUNT:-0}
      echo "Repo: $REPO — $COUNT untagged images" | tee -a ar-cleanup.txt

      if [[ -n "$UNTAGGED" && "$DRY_RUN" == "false" ]]; then
        echo "$UNTAGGED" | while read -r img; do
          if [[ -n "$img" ]]; then
            gcloud artifacts docker images delete "$img" \
              --project="$GCP_PROJECT_ID" \
              --delete-tags \
              --quiet 2>/dev/null || true
          fi
        done
        TOTAL=$(( TOTAL + COUNT ))
      fi
    done <<< "$REPOS"

    ARTIFACT_NAME="ar-cleanup-${TARGET_ENV}-${GITHUB_RUN_ID}"
    RESULT_SUMMARY="Deleted $TOTAL untagged image(s) | Dry run: $DRY_RUN"
    echo "result_summary=$RESULT_SUMMARY" >> "$GITHUB_OUTPUT"
    echo "artifact_name=$ARTIFACT_NAME" >> "$GITHUB_OUTPUT"
    ;;
esac
