const express = require("express");
const ServiceManager = require("./services/ServiceManager");
const QnapWatcher = require("./services/qnap/QnapWatcher");
const RenovateWatcher = require("./services/renovate/RenovateWatcher");
const { registry } = require("./metrics");

const app = express();
const port = process.env.PORT || 3000;

// Initialize Service Manager
const serviceManager = new ServiceManager();

// Register Services
// Pass any necessary config here
const qnapWatcher = new QnapWatcher();
serviceManager.register(qnapWatcher);

const renovateWatcher = new RenovateWatcher();
serviceManager.register(renovateWatcher);

// Start Services
serviceManager.startAll();

// API Endpoints
app.get("/api/qnap", (req, res) => {
  const status = qnapWatcher.getStatus();
  res.json(status);
});

// The homepage reads this from its own origin, so the browser needs CORS to allow it.
// Read-only counts, so only the one origin is allowed.
app.get("/api/renovate", (req, res) => {
  res.set("Access-Control-Allow-Origin", "https://home.moreaulab.ca");
  res.json(renovateWatcher.getStatus());
});

app.get("/metrics", async (req, res) => {
  res.set("Content-Type", registry.contentType);
  res.end(await registry.metrics());
});

app.listen(port, () => {
  console.log(`Service Watcher API listening on port ${port}`);
});

// Handle graceful shutdown
process.on("SIGTERM", async () => {
  console.log("SIGTERM received. Stopping services...");
  await serviceManager.stopAll();
  process.exit(0);
});
