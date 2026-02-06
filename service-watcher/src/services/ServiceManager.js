class ServiceManager {
  constructor() {
    this.services = [];
  }

  register(service) {
    this.services.push(service);
    console.log(`Registered service: ${service.name}`);
  }

  startAll() {
    console.log("Starting all services...");
    this.services.forEach((service) => {
      try {
        service.start();
        console.log(`Started service: ${service.name}`);
      } catch (error) {
        console.error(`Failed to start service ${service.name}:`, error);
      }
    });
  }

  async stopAll() {
    console.log("Stopping all services...");
    const promises = this.services.map((service) => {
      if (typeof service.stop === "function") {
        return service.stop();
      }
      return Promise.resolve();
    });
    await Promise.all(promises);
  }
}

module.exports = ServiceManager;
