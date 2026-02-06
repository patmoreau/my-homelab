const { exec } = require("child_process");
const util = require("util");
const execAsync = util.promisify(exec);
const Docker = require("dockerode");

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
    };

    if (this.status.state === "SCRUBBING") {
      if (this.status.percent) response["Progress"] = this.status.percent;
      if (this.status.finishTime) response["FinishIn"] = this.status.finishTime;
    } else {
      response["Message"] = this.status.message;
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

  async checkStatus() {
    console.log(`${new Date().toISOString()} - Checking QNAP status...`);
    try {
      const sshCommand = `ssh -i ${this.sshKeyPath} -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${this.qnapUser}@${this.qnapIp}`;
      const { stdout } = await execAsync(sshCommand);

      // The QNAP script script (on the other side) returns the status string directly
      const output = stdout.trim();
      console.log("QNAP Output:", JSON.stringify(output));

      this.status.lastCheck = Date.now();

      if (output && output !== "IDLE") {
        // Scrubbing is active
        this.status.state = "SCRUBBING"; // or 'PROGRESS'
        this.status.message = output;

        // Parse percent and finish time
        // Example: [=>.]  resync = 99.0% (3859085496/3897063424) finish=8.5min speed=73795K/sec
        const percentMatch = output.match(/resync\s*=\s*([\d.]+)%/);
        const finishMatch = output.match(/finish\s*=\s*([\d.]+)min/);

        if (percentMatch) {
          this.status.percent = percentMatch[1] + "%";
        } else {
          this.status.percent = "Unknown";
        }

        if (finishMatch) {
          this.status.finishTime = this.formatFinishTime(finishMatch[1]);
        } else {
          this.status.finishTime = "Unknown";
        }

        console.log(
          `Scrubbing active: ${this.status.percent} done, finish in ${this.status.finishTime}`,
        );
        await this.pauseTargets();
      } else {
        // Idle or empty (assume idle)
        const wasScrubbing = this.status.state === "SCRUBBING";
        this.status.state = "IDLE";
        this.status.message = "System is idle";
        this.status.percent = null;
        this.status.finishTime = null;

        if (wasScrubbing) {
          console.log("Scrubbing finished.");
          await this.resumeTargets();
        }
      }
    } catch (error) {
      console.error("Error checking QNAP status:", error.message);
      this.status.message = `Error: ${error.message}`;
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
