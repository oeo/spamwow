import * as http from 'http';
import * as https from 'https';
import * as zlib from 'zlib';
import { URL } from 'url'; // Use the modern URL API
import type { ProxyOptions } from './types';

const REQUEST_TIMEOUT = 5000; // ms

/**
 * Creates a request handler function for the Node.js http/https server
 * that proxies requests according to the provided options.
 */
export function createProxyRequestHandler(options: ProxyOptions) {
    const {
        originalHost,
        injectScriptHeader = '',
        injectScriptFooter = '',
        stringReplacements = [],
    } = options;

    const target = new URL(originalHost);
    const targetProtocol = target.protocol; // 'http:' or 'https:'
    const targetHostname = target.hostname;
    const requestModule = targetProtocol === 'https:' ? https : http;

    /**
     * The actual request handler middleware for use with http.createServer
     */
    return async (req: http.IncomingMessage, res: http.ServerResponse) => {
        // Use a flag to prevent multiple responses in case of errors/timeouts
        let responseSent = false;
        const markResponded = () => {
            responseSent = true;
        };

        try {
            const actualHost = req.headers['x-forwarded-host'] || req.headers.host || '';
            const requestProtocol = ((req.headers['x-forwarded-proto'] || '').toString().includes('https') || (req.socket as any).encrypted) ? 'https:' : 'http:';

            // Prepare options for the outgoing request to the target server
            const targetPort = target.port || (targetProtocol === 'https:' ? 443 : 80);
            const targetHostHeader = (targetPort === 80 || targetPort === 443)
                ? targetHostname
                : `${targetHostname}:${targetPort}`;

            const requestOptions: https.RequestOptions = {
                hostname: targetHostname,
                port: targetPort,
                path: req.url,
                method: req.method,
                headers: { ...req.headers }, // Clone incoming headers
                timeout: REQUEST_TIMEOUT,
            };

            // --- Header Manipulation ---
            const headersToModify = requestOptions.headers;
            const headersToDelete = ['host', 'origin', 'referer', 'if-none-match', 'if-modified-since', 'cache-control', 'pragma'];

            // Delete specified headers case-insensitively
            for (const headerKey in headersToModify) {
                if (headersToDelete.includes(headerKey.toLowerCase())) {
                    delete headersToModify[headerKey];
                }
            }

            // Set the correct host header for the target server
            headersToModify['host'] = targetHostHeader; // Use host:port if non-standard port

            // Add/replace X-Forwarded-For and X-Forwarded-Proto if desired (optional)
            // headersToModify['x-forwarded-for'] = req.socket.remoteAddress;

            const proxyReq = requestModule.request(requestOptions, (proxyRes) => {
                if (responseSent) return;

                const contentType = proxyRes.headers['content-type'] || '';
                const contentEncoding = proxyRes.headers['content-encoding']?.toLowerCase();

                // Determine if content is likely text-based and modifiable
                const isTextContent = contentType.includes('text') ||
                                   contentType.includes('json') ||
                                   contentType.includes('xml') ||
                                   contentType.includes('javascript') ||
                                   contentType.includes('application/x-javascript');

                // --- Binary Content Handling ---
                if (!isTextContent) {
                    console.log(`Handling binary content: ${req.url} (${contentType})`);
                    markResponded();
                    res.writeHead(proxyRes.statusCode ?? 500, proxyRes.headers); // Pass original headers

                    // Instead of piping, buffer the response and end
                    const binaryChunks: Buffer[] = [];
                    proxyRes.on('data', chunk => binaryChunks.push(chunk));
                    proxyRes.on('end', () => {
                        res.end(Buffer.concat(binaryChunks));
                    });
                    proxyRes.on('error', (err) => {
                        console.error(`Error reading binary response stream for ${req.url}:`, err);
                        // Ensure response ends even if target stream errors
                        if (!res.writableEnded) {
                            res.end();
                        }
                    });
                    // proxyRes.pipe(res); // Avoid pipe for testing
                    return;
                }

                // --- Text Content Handling ---
                console.log(`Handling text content: ${req.url} (${contentType})`);
                const responseHeaders: http.OutgoingHttpHeaders = {};
                for (const [key, value] of Object.entries(proxyRes.headers)) {
                    // Skip headers related to encoding/length, as we'll modify the body
                    const lowerKey = key.toLowerCase();
                    if (!['content-length', 'content-encoding', 'transfer-encoding'].includes(lowerKey)) {
                        responseHeaders[key] = value;
                    }
                }

                // Add CORS headers (consider making this configurable)
                responseHeaders['Access-Control-Allow-Origin'] = '*';
                responseHeaders['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS';
                responseHeaders['Access-Control-Allow-Headers'] = 'Content-Type, Authorization';

                // Collect response body chunks
                const chunks: Buffer[] = [];
                proxyRes.on('data', (chunk) => chunks.push(chunk));

                proxyRes.on('end', async () => {
                    if (responseSent) return;
                    markResponded();

                    try {
                        let bodyBuffer = Buffer.concat(chunks);

                        // --- Decompression ---
                        try {
                            if (contentEncoding === 'gzip') {
                                bodyBuffer = zlib.gunzipSync(bodyBuffer);
                            } else if (contentEncoding === 'deflate') {
                                bodyBuffer = zlib.inflateSync(bodyBuffer);
                            } else if (contentEncoding === 'br') {
                                bodyBuffer = zlib.brotliDecompressSync(bodyBuffer);
                            }
                            // Note: We *don't* re-compress. Let the final server handle it.
                        } catch (decompressionError) {
                            console.error(`Decompression error for ${req.url}:`, decompressionError);
                            // If decompression fails, send original content with original headers
                            res.writeHead(proxyRes.statusCode ?? 500, proxyRes.headers);
                            res.end(Buffer.concat(chunks)); // Send original buffer
                            return;
                        }

                        let content = bodyBuffer.toString('utf8');

                        // --- Content Modification ---
                        // 1. URL Rewriting
                        if (actualHost) {
                            // Escape the hostname for regex use
                            const escapedHostname = targetHostname.replace(/[.*+?^${}()|[\\\]]/g, '\\$&');
                            // Determine if the original port is non-standard
                            const isNonStandardPort = targetPort !== 80 && targetPort !== 443;
                            // Create the pattern part including the port if non-standard
                            const hostAndPortPattern = isNonStandardPort
                                ? `${escapedHostname}:${targetPort}`
                                : escapedHostname;

                            const newBaseUrlAbsolute = `${requestProtocol}//${actualHost}`;
                            const newBaseUrlRelative = `//${actualHost}`;

                            // Regex patterns to find variations of the original host URL, now including port
                            const patterns: [RegExp, string][] = [
                                // Absolute URLs: http(s)://host:port/path -> $1://proxy/path (preserves original protocol)
                                [new RegExp(`(https?):\\/\\/${hostAndPortPattern}(\\/|\\?|#|$)`, 'gi'), `$1://${actualHost}$2`],
                                // Protocol-relative URLs: //host:port/path -> //proxy/path
                                [new RegExp(`\\/\\/${hostAndPortPattern}(\\/|\\?|#|$)`, 'gi'), `//${actualHost}$1`],
                                // URLs within quotes/parens: "(http(s)?:)?//host:port..." -> "$1//proxy..."
                                [new RegExp(`(["'])(https?:)?\\/\\/${hostAndPortPattern}(\\/|\\?|#|['"])`, 'gi'), `$1$2//${actualHost}$3`],
                            ];

                            for (const [pattern, replacement] of patterns) {
                                content = content.replace(pattern, replacement);
                            }
                        }

                        // 2. String Replacements
                        for (const replacement of stringReplacements) {
                             // Ensure find is treated as a literal string in the regex
                            const findPattern = replacement.find.replace(/[.*+?^${}()|[\\\]]/g, '\\$&');
                            content = content.replace(new RegExp(findPattern, 'g'), replacement.replace);
                        }

                        // 3. Header/Footer Script Injection (HTML only)
                        if (contentType.includes('text/html')) {
                            if (injectScriptHeader && content.includes('<head>')) {
                                content = content.replace(/<head[^>]*>/i, `$&${injectScriptHeader}`); // Inject after <head> tag
                            }
                            if (injectScriptFooter) {
                                if (content.includes('</body>')) {
                                    content = content.replace('</body>', `${injectScriptFooter}</body>`);
                                } else if (content.includes('</html>')) {
                                    content = content.replace('</html>', `${injectScriptFooter}</html>`);
                                } else {
                                    // Fallback: append to the end if no body/html tag found
                                    content += injectScriptFooter;
                                }
                            }
                        }

                        // --- Send Modified Response ---
                        // Set Content-Length for the modified content
                        responseHeaders['Content-Length'] = Buffer.byteLength(content, 'utf8').toString();
                        res.writeHead(proxyRes.statusCode ?? 500, responseHeaders);
                        res.end(content);

                    } catch (processingError) {
                        console.error(`Error processing text response for ${req.url}:`, processingError);
                        if (!res.writableEnded) {
                            res.writeHead(500, { 'Content-Type': 'text/plain' });
                            res.end("Error processing response");
                        }
                    }
                }); // end of proxyRes.on('end')

                proxyRes.on('error', (error) => {
                    console.error(`Proxy response error for ${req.url}:`, error);
                    if (!responseSent && !res.writableEnded) {
                        markResponded();
                        res.writeHead(502, { 'Content-Type': 'text/plain' });
                        res.end('Proxy response error');
                    }
                });

            }); // end of requestModule.request callback

            // --- Error Handling for Outgoing Request ---
            proxyReq.on('error', (error) => {
                console.error(`Proxy request error for ${req.url}:`, error.message);
                if (!responseSent && !res.writableEnded) {
                    markResponded();
                    const statusCode = error.message.includes('timeout') ? 504 : 502;
                    res.writeHead(statusCode, { 'Content-Type': 'text/plain' });
                    res.end(`Proxy request error: ${error.message}`);
                }
            });

            proxyReq.on('timeout', () => {
                 console.error(`Proxy request timeout for ${req.url}`);
                 proxyReq.destroy(new Error('Timeout')); // Explicitly destroy on timeout
            });

            // --- Pipe Request Body (if applicable) ---
            if (['POST', 'PUT', 'PATCH'].includes(req.method ?? '')) {
                req.pipe(proxyReq);
            } else {
                proxyReq.end();
            }

        } catch (err) {
            console.error(`Unhandled error in proxy handler for ${req.url}:`, err);
            if (!responseSent && !res.writableEnded) {
                 markResponded();
                 res.writeHead(500, { 'Content-Type': 'text/plain' });
                 res.end('Internal Server Error');
            }
        }
    }; // end of returned request handler
}

// Note: Websocket upgrade handling is typically done by attaching a listener
// to the 'upgrade' event on the main http.Server instance, *not* within the
// standard request handler. That logic would need to be implemented separately
// where the server is created and would use these ProxyOptions. 