const { exec } = require("child_process");
const util = require("util");
const execAsync = util.promisify(exec);
const Docker = require("dockerode");
const { updateMetrics } = require("../../metrics");

class QnapWatcher {
  constructor() {
    this.name = "QnapWatcher";
    this.interval = 60 * 1000; // 60 seconds (1 minute)
    this.timer = null;
    this.status = {
      state: "IDLE",
      lastCheck: null,
      message: "Initializing",
      percent: null,
      finishTime: null,
    };

    // Environment variables
    this.qnapUser = process.env.QNAP_USER;
    this.qnapIp = process.env.QNAP_IP;
    this.sshKeyPath = process.env.SSH_KEY_PATH;

    // Targets to pause/unpause
    this.targets = (process.env.TARGETS || "")
      .split(" ")
      .filter((t) => t.length > 0);

    this.docker = new Docker({ socketPath: "/var/run/docker.sock" });
  }

  start() {
    this.checkStatus(); // Initial check
    this.timer = setInterval(() => this.checkStatus(), this.interval);
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    return Promise.resolve();
  }

  getStatus() {
    const response = {
      Status: this.status.state,
      LastCheck: this.status.lastCheck
        ? new Date(this.status.lastCheck).toLocaleTimeString()
        : "Never",
      Message: this.status.message,
    };

    const activeStates = [
      "SCRUBBING",
      "CHECKING",
      "RESYNCING",
      "REPAIRING",
      "RECOVERING",
      "RESHAPING",
    ];
    if (activeStates.includes(this.status.state)) {
      if (this.status.percent) response["Progress"] = this.status.percent;
      if (this.status.finishTime) response["FinishIn"] = this.status.finishTime;
    }

    return response;
  }

  formatFinishTime(minutesStr) {
    const minutes = parseFloat(minutesStr);
    if (isNaN(minutes)) return minutesStr + "min";

    if (minutes < 60) {
      return `${minutes}min`;
    }

    const hrs = Math.floor(minutes / 60);
    const mins = Math.round(minutes % 60);
    return `${hrs}h ${mins}m`;
  }

  // Maps /proc/mdstat operation keywords to state names and descriptions
  resolveOperation(keyword) {
    const operations = {
      check: {
        state: "CHECKING",
        message: "RAID consistency check in progress",
        pauseTargets: false,
      },
      resync: {
        state: "RESYNCING",
        message: "RAID resync in progress",
        pauseTargets: true,
      },
      repair: {
        state: "REPAIRING",
        message: "RAID repair in progress",
        pauseTargets: true,
      },
      recovery: {
        state: "RECOVERING",
        message: "RAID recovery in progress (drive rebuilding)",
        pauseTargets: true,
      },
      reshape: {
        state: "RESHAPING",
        message: "RAID reshape in progress (expansion/migration)",
        pauseTargets: true,
      },
    };
    return (
      operations[keyword] || {
        state: "ACTIVE",
        message: `RAID operation: ${keyword}`,
        pauseTargets: true,
      }
    );
  }

  resolveError(errorMessage) {
    if (errorMessage.includes("Connection refused")) {
      return {
        state: "UNREACHABLE",
        message: "QNAP is booting or SSH is unavailable",
      };
    }
    if (
      errorMessage.includes("timed out") ||
      errorMessage.includes("No route") ||
      errorMessage.includes("Network is unreachable")
    ) {
      return { state: "OFFLINE", message: "QNAP is offline or unreachable" };
    }
    if (
      errorMessage.includes("Connection reset") ||
      errorMessage.includes("Broken pipe")
    ) {
      return {
        state: "UNREACHABLE",
        message: "QNAP connection dropped (possible reboot)",
      };
    }
    if (
      errorMessage.includes("Name does not resolve") ||
      errorMessage.includes("Could not resolve")
    ) {
      return { state: "DNS_ERROR", message: "Cannot resolve QNAP hostname" };
    }
    if (
      errorMessage.includes("Permission denied") ||
      errorMessage.includes("Authentication failed")
    ) {
      return { state: "AUTH_ERROR", message: "SSH authentication failed" };
    }
    return { state: "ERROR", message: errorMessage };
  }

  async checkStatus() {
    console.log(`${new Date().toISOString()} - Checking QNAP status...`);
    try {
      const sshCommand = `ssh -i ${this.sshKeyPath} -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${this.qnapUser}@${this.qnapIp}`;
      const { stdout } = await execAsync(sshCommand);

      // The QNAP script (on the other side) returns the status string directly
      const output = stdout.trim();
      console.log("QNAP Output:", JSON.stringify(output));

      this.status.lastCheck = Date.now();

      // Match any known md RAID operation keyword
      // Example: [==>..] recovery = 12.5% (1234567/9876543) finish=45.2min speed=120000K/sec
      const operationMatch = output.match(
        /(check|resync|repair|recovery|reshape)\s*=\s*([\d.]+)%/
      );
      const finishMatch = output.match(/finish\s*=\s*([\d.]+)min/);

      if (output && output !== "IDLE" && operationMatch) {
        const operation = this.resolveOperation(operationMatch[1]);
        const wasActive = this.status.state !== "IDLE";

        this.status.state = operation.state;
        this.status.message = operation.message;
        this.status.percent = operationMatch[2] + "%";
        this.status.finishTime = finishMatch
          ? this.formatFinishTime(finishMatch[1])
          : "Unknown";

        console.log(
          `${operation.state}: ${this.status.percent} done, finish in ${this.status.finishTime}`
        );
        updateMetrics(this.status.state, operationMatch[2]);

        if (operation.pauseTargets) {
          await this.pauseTargets();
        }
      } else {
        // Idle or unrecognised output — treat as idle
        const wasActive = [
          "CHECKING",
          "RESYNCING",
          "REPAIRING",
          "RECOVERING",
          "RESHAPING",
        ].includes(this.status.state);

        this.status.state = "IDLE";
        this.status.message = "System is idle";
        this.status.percent = null;
        this.status.finishTime = null;
        updateMetrics("IDLE", null);

        if (wasActive) {
          console.log("RAID operation finished, resuming targets.");
          await this.resumeTargets();
        }
      }
    } catch (error) {
      console.error("Error checking QNAP status:", error.message);
      this.status.lastCheck = Date.now();
      const resolved = this.resolveError(error.message);
      this.status.state = resolved.state;
      this.status.message = resolved.message;
      this.status.percent = null;
      this.status.finishTime = null;
      updateMetrics(resolved.state, null);
    }
  }

  async pauseTargets() {
    if (this.targets.length === 0) return;

    console.log(`Pausing targets: ${this.targets.join(", ")}`);
    for (const targetName of this.targets) {
      try {
        const container = this.docker.getContainer(targetName);
        const info = await container.inspect();
        if (info.State.Running && !info.State.Paused) {
          await container.pause();
          console.log(`Paused ${targetName}`);
        } else {
          console.log(`${targetName} is not running or already paused.`);
        }
      } catch (err) {
        console.error(`Failed to pause ${targetName}:`, err.message);
      }
    }
  }

  async resumeTargets() {
    if (this.targets.length === 0) return;

    console.log(`Resuming targets: ${this.targets.join(", ")}`);
    for (const targetName of this.targets) {
      try {
        const container = this.docker.getContainer(targetName);
        const info = await container.inspect();
        if (info.State.Paused) {
          await container.unpause();
          console.log(`Unpaused ${targetName}`);
        } else {
          console.log(`${targetName} is not paused.`);
        }
      } catch (err) {
        console.error(`Failed to resume ${targetName}:`, err.message);
      }
    }
  }
}

module.exports = QnapWatcher;
