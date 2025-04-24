import * as http from 'http';
import { createProxyRequestHandler } from './proxyHandler';
import type { ProxyOptions } from './types';
import { URL } from 'url';

/**
 * Creates and starts an HTTP proxy server.
 * @param port The port number to listen on.
 * @param options Configuration for the proxy handler.
 * @returns The created http.Server instance.
 */
function startProxyServer(port: number, options: ProxyOptions): http.Server {
    if (!options.originalHost || !options.originalHost.startsWith('http')) {
        console.error("Error: 'originalHost' in proxyOptions must be a valid URL starting with http:// or https://");
        throw new Error("Invalid originalHost"); // Throw error instead of exiting
    }

    console.log(`Creating proxy handler for target: ${options.originalHost}`);
    const requestHandler = createProxyRequestHandler(options);

    console.log(`Attempting to start proxy server on port ${port}...`);
    const server = http.createServer(requestHandler);

    server.on('listening', () => {
        const target = new URL(options.originalHost);
        const targetPort = target.port || (target.protocol === 'https:' ? 443 : 80);
        console.log(`✅ Proxy server listening on http://localhost:${port}`);
        console.log(`   Proxying requests to: ${target.hostname}:${targetPort} (from ${options.originalHost})`);
    });

    server.on('error', (error: NodeJS.ErrnoException) => {
        if (error.code === 'EADDRINUSE') {
            console.error(`❌ Error: Port ${port} is already in use.`);
        } else {
            console.error(`❌ Server error: ${error.message}`);
        }
        // Don't exit here, let the caller handle errors if needed
        // process.exit(1);
    });

    // --- Optional: Add WebSocket Proxying ---
    // server.on('upgrade', (req, socket, head) => { ... });

    server.listen(port);
    return server; // Return the server instance
}


// --- Command-Line Execution Logic ---
if (require.main === module) {
    console.log("Running proxy server directly...");

    // Basic command-line argument parsing
    // Example usage: bun run typescript/server.ts --port 20000 --target https://example.com
    const args = process.argv.slice(2); // Bun.argv includes bun and script path

    let port: number | undefined;
    let targetHost: string | undefined;
    // TODO: Add parsing for other options like script injection/replacements if needed

    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--port' && i + 1 < args.length) {
            port = parseInt(args[i + 1], 10);
            i++; // Skip the value
        } else if (args[i] === '--target' && i + 1 < args.length) {
            targetHost = args[i + 1];
            i++; // Skip the value
        }
    }

    if (port === undefined || isNaN(port)) {
        console.error("Error: Missing or invalid --port argument.");
        console.error("Usage: bun run typescript/server.ts --port <number> --target <url>");
        process.exit(1);
    }

    if (targetHost === undefined) {
        console.error("Error: Missing --target argument.");
        console.error("Usage: bun run typescript/server.ts --port <number> --target <url>");
        process.exit(1);
    }

    const runOptions: ProxyOptions = {
        originalHost: targetHost
        // Add other parsed options here
    };

    try {
        const runningServer = startProxyServer(port, runOptions);
        // Optional: Add signal handling for graceful shutdown if needed
        // process.on('SIGINT', () => { ... });
        // process.on('SIGTERM', () => { ... });
    } catch (error) {
        console.error("Failed to start proxy server:", error);
        process.exit(1);
    }
}

// Export the start function so it can be imported and used programmatically elsewhere
export { startProxyServer, ProxyOptions }; // Re-export ProxyOptions for convenience
