runtime: nodejs24
service: ${GAE_SERVICE}

# Instance class and scaling — values supplied by the deploy workflow (defaults: F2, 0–10)
instance_class: ${GAE_INSTANCE_CLASS}

automatic_scaling:
  min_instances: ${GAE_MIN_INSTANCES}
  max_instances: ${GAE_MAX_INSTANCES}
  target_cpu_utilization: 0.65
  target_throughput_utilization: 0.65

# Entrypoint delegates to start.sh which wraps Node with Doppler (if enabled)
entrypoint: sh start.sh

# Non-secret runtime config — secrets are pulled by Doppler at startup
env_variables:
  NODE_ENV: "production"
  PORT: "8080"
  DOPPLER_PROJECT: "${DOPPLER_PROJECT}"
  DOPPLER_CONFIG: "${DOPPLER_CONFIG}"

# Headers for Cloud Tasks / internal service calls
# DOPPLER_TOKEN is injected at deploy time from GitHub Environment secrets
# Do NOT commit tokens here — this template renders at deploy time
