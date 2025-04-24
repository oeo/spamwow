# SpamWOW - Web Application & Proxy Service

## Overview

SpamWOW is a Node.js application built with CoffeeScript, Express, Mongoose, and Redis. It provides a RESTful API for managing various entities like campaigns, domains, emails, and AWS accounts. A key feature is its ability to proxy external websites, allowing for dynamic content manipulation (script injection, string replacement) and management of these proxy instances.

## Features

*   **RESTful API:** Exposes CRUD operations for various data models via automatically generated routes (`lib/autoExpose.coffee`).
*   **Website Proxying:** Forks separate Node.js processes (`bin/proxy-website.coffee`) to proxy target websites.
    *   Supports HTTPS/HTTP targets.
    *   Handles URL rewriting to the proxy's host.
    *   Injects custom scripts into `<head>` or before `</body>`.
    *   Performs custom string replacements on text-based content.
    *   Manages proxy process lifecycle (start, stop, restart, health checks).
    *   Automatic port assignment within a configurable range.
    *   Uses Redis for tracking running proxy processes.
*   **Data Models:** Uses Mongoose (`lib/database.coffee`) for MongoDB object modeling, including:
    *   `AwsAccounts`
    *   `Campaigns`
    *   `Domains`
    *   `EmailDns`
    *   `Emails`
    *   `EspAccounts`
    *   `Events`
    *   `ProxyWebsites`
*   **SMTP Server:** Includes a basic SMTP server (`smtp-server/server.coffee`) likely for receiving and processing emails (e.g., bounces, complaints).
*   **Configuration:** Uses `.env` files for environment-specific settings (`lib/env.coffee`).
*   **Scripts:** Provides utility scripts (`scripts/`) for tasks like database setup, creating test data, and managing proxy websites.

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
