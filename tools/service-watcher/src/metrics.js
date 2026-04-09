const client = require("prom-client");

const registry = new client.Registry();
client.collectDefaultMetrics({ register: registry });

// 1 when RAID operation is active (RESYNCING, RECOVERING, etc.), 0 when idle
const qnapRaidActive = new client.Gauge({
  name: "qnap_raid_active",
  help: "1 if a RAID operation is currently in progress",
  registers: [registry],
});

// Progress percentage of the current RAID operation (NaN when idle)
const qnapRaidProgressPercent = new client.Gauge({
  name: "qnap_raid_progress_percent",
  help: "RAID operation progress percentage (0-100)",
  registers: [registry],
});

// 1 if the QNAP is reachable via SSH, 0 if not
const qnapReachable = new client.Gauge({
  name: "qnap_reachable",
  help: "1 if QNAP is reachable via SSH, 0 otherwise",
  registers: [registry],
});

// Info-style metric exposing the current state as a label
const qnapStateInfo = new client.Gauge({
  name: "qnap_state_info",
  help: "Current QNAP watcher state (value is always 1, read the state label)",
  labelNames: ["state"],
  registers: [registry],
});

const ACTIVE_STATES = new Set([
  "CHECKING",
  "RESYNCING",
  "REPAIRING",
  "RECOVERING",
  "RESHAPING",
]);
const REACHABLE_STATES = new Set([
  "IDLE",
  "CHECKING",
  "RESYNCING",
  "REPAIRING",
  "RECOVERING",
  "RESHAPING",
]);

let currentStateLabel = null;

function updateMetrics(state, percentStr) {
  // Update info gauge — reset previous label first
  if (currentStateLabel) {
    qnapStateInfo.remove(currentStateLabel);
  }
  qnapStateInfo.set({ state }, 1);
  currentStateLabel = state;

  qnapRaidActive.set(ACTIVE_STATES.has(state) ? 1 : 0);
  qnapReachable.set(REACHABLE_STATES.has(state) ? 1 : 0);

  if (percentStr) {
    const pct = parseFloat(percentStr);
    qnapRaidProgressPercent.set(isNaN(pct) ? 0 : pct);
  } else {
    qnapRaidProgressPercent.set(0);
  }
}

module.exports = { registry, updateMetrics };
