# SpamWOW - Email Delivery Platform & Web Proxy Service

## Overview

SpamWOW is a Node.js application designed as an **Email Delivery Platform**. Built with CoffeeScript, Express, Mongoose, and Redis, it provides a robust backend for managing email campaigns, tracking delivery events, handling bounces/complaints via an integrated SMTP server, and managing associated resources like domains and ESP accounts.

Additionally, it includes a **sophisticated web proxy feature** for cloaking and modifying external websites on the fly.

## Features

*   **Email Campaign Management:** Manage email campaigns, lists, and templates.
*   **Domain & ESP Management:** Track sending domains, DNS records (DKIM/SPF potentially managed via scripts), and ESP account credentials.
*   **Event Tracking:** Log email-related events (e.g., sends, opens, clicks - inferred, needs verification).
*   **Integrated SMTP Server:** (`smtp-server/server.coffee`) Receives and processes incoming emails, identifying bounces and complaints.
*   **RESTful API:** Exposes CRUD operations for data models via automatically generated routes (`lib/autoExpose.coffee`).
*   **Website Proxying:** Includes a powerful system for proxying and modifying external websites (see details below).
*   **Configuration:** Uses `.env` files for environment-specific settings (`lib/env.coffee`).
*   **Scripts:** Provides utility scripts (`scripts/`) for setup and data management.
*   **Data Models:** Uses Mongoose (`lib/database.coffee`) for MongoDB object modeling (Campaigns, Domains, Emails, ProxyWebsites, etc.).

## Sophisticated Web Proxy

The platform incorporates a powerful website proxying system designed for cloaking and dynamic content modification:

*   **Process Management:** Each proxy runs as a separate, managed Node.js process (`bin/proxy-website.coffee`), forked from the main application.
    *   Automatic start/stop/restart based on the `ProxyWebsite` model's `isActive` status and configuration changes (`originalHost`, `port`).
    *   Robust process tracking using Redis (`proxy:process:*` keys) and PID management.
    *   Health checks (`checkHealth` method) to monitor the status of running proxies via HTTP endpoints.
    *   Graceful cleanup of resources on stop or removal.
*   **Dynamic Content Manipulation:**
    *   Supports proxying both HTTPS and HTTP target websites.
    *   Rewrites URLs within HTML/CSS/JS content to point to the proxy host, maintaining site integrity under the new domain.
    *   Injects custom JavaScript code into the `<head>` (`injectScriptHeader`) or just before the closing `</body>` (`injectScriptFooter`) tag of HTML pages.
    *   Performs arbitrary string replacements (`stringReplacements`) within text-based web content (HTML, CSS, JS).
    *   Handles various content encodings (gzip, deflate, brotli) for text modification.
    *   Correctly pipes binary content (images, fonts) without modification.
*   **Configuration & Management:**
    *   Managed via the `ProxyWebsite` Mongoose model and its associated REST API endpoints.
    *   Automatic port assignment within a configurable range (`PROXY_PORT_RANGE`) to avoid conflicts.
    *   Static methods (`startAll`, `stopAll`, `listRunning`) for managing all proxy instances.

## Prerequisites

*   **Node.js:** Version specified in `.nvmrc`. Use NVM (`nvm use`) to ensure compatibility.
*   **Yarn:** For package management (`npm install -g yarn`).
*   **MongoDB:** Running instance accessible to the application.
*   **Redis:** Running instance accessible to the application.

## Installation

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd spamwow
    ```
2.  **Switch to the correct Node.js version:**
    ```bash
    nvm use
    ```
3.  **Install dependencies:**
    ```bash
    yarn install
    ```

## Configuration

1.  **Copy the example environment file:**
    ```bash
    cp .env.example .env
    ```
2.  **Edit `.env`:** Update the necessary variables, especially:
    *   `MONGO_URI`: Connection string for your MongoDB instance.
    *   `REDIS_URL`: Connection string for your Redis instance.
    *   `PROXY_PORT_RANGE`: The range of ports to use for proxy websites (e.g., `20000-30000`).
    *   Other service credentials or settings as needed.

## Running the Application

1.  **Start the main web server:**
    ```bash
    yarn start
    # or
    node app.js
    ```
    The server will listen on the port specified by `LOCAL_PORT` in your `.env` file (defaults to 8000).
    When the main application starts, it will also attempt to start all `ProxyWebsite` instances marked as `isActive: true`.

2.  **Managing Proxies:**
    *   Proxies are managed via the `ProxyWebsites` model and its API endpoints.
    *   Creating a new `ProxyWebsite` document with `isActive: true` will automatically attempt to find an available port and start the proxy process upon saving.
    *   Updating `isActive`, `port`, or `originalHost` will trigger a restart/stop of the corresponding proxy process.
    *   Deleting a `ProxyWebsite` document will stop its associated process.

## Scripts

The `scripts/` directory contains helpful command-line scripts:

*   `create-aws-account.coffee`: Creates a sample AWS account entry in the database.
*   `create-proxy-website.coffee`: Clears existing proxy websites and creates example ones.
*   `create-random-events.coffee`: Populates the database with random event data.
*   `create-real-aws-account.coffee`: Creates an AWS account entry using environment variables (likely for testing real credentials).
*   `drop-database.coffee`: **DANGER:** Drops all collections managed by the application's models from the database.

To run a script (example):
```bash
node scripts/create-proxy-website.coffee
```

## Technologies

*   Node.js
*   CoffeeScript 2
*   Express.js
*   Mongoose (MongoDB)
*   Redis
*   Yarn

## Deprecated

The `deprecated/` directory contains older attempts at proxying (MITMProxy, another Node.js proxy) that are no longer in use.
