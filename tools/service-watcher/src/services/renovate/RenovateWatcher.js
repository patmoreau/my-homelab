// Counts open PRs and Renovate work for the homepage badge. Polls GitHub's API, which
// needs no token for a public repo. Unauthenticated search allows roughly 10 requests a
// minute, so one poll every 10 minutes (three requests) sits far inside that.
const GITHUB_API = "https://api.github.com";
const APPROVAL_LINE = /^ - \[ \] <!-- (?:unschedule|approve)-branch=/gm;

class RenovateWatcher {
  constructor() {
    this.name = "RenovateWatcher";
    this.interval = 10 * 60 * 1000;
    this.timer = null;
    this.repo = process.env.RENOVATE_REPO || "patmoreau/my-homelab";
    this.dashboardIssue = process.env.RENOVATE_DASHBOARD_ISSUE || "1";
    this.counts = { open: null, renovate: null, approvals: null, lastCheck: null };
  }

  start() {
    this.poll();
    this.timer = setInterval(() => this.poll(), this.interval);
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    return Promise.resolve();
  }

  async getJson(path) {
    const res = await fetch(`${GITHUB_API}${path}`, {
      headers: {
        Accept: "application/vnd.github+json",
        "User-Agent": "service-watcher",
      },
    });
    if (!res.ok) throw new Error(`${res.status} from ${path}`);
    return res.json();
  }

  async poll() {
    const search = (query) =>
      this.getJson(`/search/issues?per_page=1&q=${encodeURIComponent(`repo:${this.repo} ${query}`)}`);

    try {
      const [open, renovate, dashboard] = await Promise.all([
        search("is:pr is:open"),
        search("is:pr is:open author:app/renovate"),
        this.getJson(`/repos/${this.repo}/issues/${this.dashboardIssue}`),
      ]);
      this.counts = {
        open: open.total_count,
        renovate: renovate.total_count,
        // Dashboard checkboxes that need a click carry an unschedule-branch or approve-branch
        // marker. The "create all" line has neither, so it stays out of the count.
        approvals: (dashboard.body.match(APPROVAL_LINE) || []).length,
        lastCheck: Date.now(),
      };
    } catch (error) {
      // Keep the last good counts rather than reporting zeros during a rate limit or outage.
      console.error("Renovate poll failed:", error.message);
    }
  }

  getStatus() {
    return { ...this.counts };
  }
}

module.exports = RenovateWatcher;
