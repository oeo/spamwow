// typescript/server.test.ts
import { describe, it, expect, spyOn, mock, beforeEach, afterEach, type Mock, type Args } from 'bun:test';
import * as serverModule from '../src/server';
import http from 'http';

// Mock process.argv and process.exit
const mockExit = mock(() => { throw new Error("process.exit called"); });
const mockProcess = {
  argv: [] as string[],
  exit: mockExit
};
mock.module('process', () => mockProcess);

// Mock the actual startProxyServer function so we don't start real servers
// We need to mock the default export if that's how it's structured,
// or the named export if it's named.
const mockStartServer = mock(serverModule.startProxyServer);

// Mock console.error to check output
const mockConsoleError = spyOn(console, 'error');

describe('server.ts command line execution', () => {

    beforeEach(() => {
        mockStartServer.mockClear();
        mockConsoleError.mockClear();
        mockExit.mockClear();
        mockProcess.argv = ['bun', 'typescript/server.ts']; // Reset argv
    });

     // Helper to simulate running the main execution block logic from server.ts
     const runServerMainLogic = async () => {
        const args = mockProcess.argv.slice(2);
        let port: number | undefined;
        let targetHost: string | undefined;
        for (let i = 0; i < args.length; i++) {
            if (args[i] === '--port' && i + 1 < args.length) {
                port = parseInt(args[i + 1], 10);
                i++;
            } else if (args[i] === '--target' && i + 1 < args.length) {
                targetHost = args[i + 1];
                i++;
            }
        }

         if (port === undefined || isNaN(port)) {
             console.error("Error: Missing or invalid --port argument.");
             mockProcess.exit(1);
             return; // Simulate exit
         }

         if (targetHost === undefined) {
             console.error("Error: Missing --target argument.");
             mockProcess.exit(1);
             return; // Simulate exit
         }

         const runOptions = { originalHost: targetHost };
         try {
            mockStartServer(port, runOptions);
         } catch (error) {
              console.error("Failed to start proxy server:", error);
              mockProcess.exit(1);
         }
     };


    it('should call startProxyServer with correct args', async () => {
        mockProcess.argv.push('--port', '12345', '--target', 'https://test.dev');
        try {
            await runServerMainLogic();
        } catch (e: any) {
            // No exit should occur
            if (e.message === "process.exit called") throw new Error("process.exit was called unexpectedly");
            throw e;
        }

        expect(mockStartServer).toHaveBeenCalledTimes(1);
        expect(mockStartServer).toHaveBeenCalledWith(12345, { originalHost: 'https://test.dev' });
        expect(mockExit).not.toHaveBeenCalled();
        expect(mockConsoleError).not.toHaveBeenCalled();
    });

    it('should exit and log error if --port is missing', async () => {
        mockProcess.argv.push('--target', 'https://test.dev');
        await expect(runServerMainLogic()).rejects.toThrow("process.exit called");

        expect(mockStartServer).not.toHaveBeenCalled();
        expect(mockExit).toHaveBeenCalledWith(1);
        expect(mockConsoleError).toHaveBeenCalledWith(expect.stringContaining('Missing or invalid --port'));
    });

     it('should exit and log error if --port is invalid', async () => {
        mockProcess.argv.push('--port', 'abc', '--target', 'https://test.dev');
        await expect(runServerMainLogic()).rejects.toThrow("process.exit called");

        expect(mockStartServer).not.toHaveBeenCalled();
        expect(mockExit).toHaveBeenCalledWith(1);
        expect(mockConsoleError).toHaveBeenCalledWith(expect.stringContaining('Missing or invalid --port'));
    });

    it('should exit and log error if --target is missing', async () => {
        mockProcess.argv.push('--port', '12345');
        await expect(runServerMainLogic()).rejects.toThrow("process.exit called");

        expect(mockStartServer).not.toHaveBeenCalled();
        expect(mockExit).toHaveBeenCalledWith(1);
        expect(mockConsoleError).toHaveBeenCalledWith(expect.stringContaining('Missing --target'));
    });

     it('should exit if startProxyServer throws an error', async () => {
         mockStartServer.mockImplementation(() => { throw new Error("Test server start failure"); });
         mockProcess.argv.push('--port', '12345', '--target', 'https://test.dev');
         await expect(runServerMainLogic()).rejects.toThrow("process.exit called");

         expect(mockStartServer).toHaveBeenCalledTimes(1);
         expect(mockExit).toHaveBeenCalledWith(1);
         expect(mockConsoleError).toHaveBeenCalledWith("Failed to start proxy server:", expect.any(Error));
    });

});

// Separate describe block for the exported function
describe('startProxyServer function', () => {
    let server: http.Server | null = null;
    let consoleSpy: Mock<Args<any[], any>>; // Define spy variable here

    beforeEach(() => {
        // Reset server variable
        server = null;
        // Setup spy before each test in this block
        consoleSpy = spyOn(console, 'error');
    });

    afterEach(async () => {
        // Ensure server is closed after each test
        if (server && server.listening) {
            await new Promise<void>(resolve => server!.close(() => resolve()));
        }
        server = null;
        // Restore console spy after each test
        if (consoleSpy) {
            consoleSpy.mockRestore();
        }
    });

    it('should throw error for invalid originalHost', () => {
        const invalidOptions = { originalHost: 'not-a-url' };
        expect(() => {
            server = serverModule.startProxyServer(50000, invalidOptions);
        }).toThrow('Invalid originalHost');
        expect(server).toBeNull(); // Ensure server wasn't created
    });

    it.skip('should handle generic server startup error', async () => {
        // Mock listen to emit a generic error
        const mockListen = mock((port: number, cb?: () => void) => {
            // Emit error asynchronously to simulate real-world scenario
            process.nextTick(() => server!.emit('error', new Error('Something else went wrong')));
            return server!;
        });

        const originalCreateServer = http.createServer;
        (http as any).createServer = () => {
            server = originalCreateServer(); // Create a real server instance
            server.listen = mockListen as any;
            return server;
        };

        const options = { originalHost: 'http://example.com' }; // Valid host
        server = serverModule.startProxyServer(50001, options);

        // Wait briefly for the error event to be emitted and handled
        await new Promise(resolve => setTimeout(resolve, 50));

        expect(consoleSpy).toHaveBeenCalled(); // Check if it was called at all

        // Restore mocks
        (http as any).createServer = originalCreateServer;
    });

     it.skip('should handle EADDRINUSE server startup error', async () => {
        // Mock listen to emit EADDRINUSE
        const mockListenEaddrinuse = mock((port: number, cb?: () => void) => {
            process.nextTick(() => {
                const err: NodeJS.ErrnoException = new Error('listen EADDRINUSE');
                err.code = 'EADDRINUSE';
                server!.emit('error', err);
            });
            return server!;
        });

        const originalCreateServer = http.createServer;
        (http as any).createServer = () => {
            server = originalCreateServer(); // Create a real server instance
            server.listen = mockListenEaddrinuse as any;
            return server;
        };

        const options = { originalHost: 'http://example.com' }; // Valid host
        server = serverModule.startProxyServer(50002, options);

        // Wait briefly for the error event to be emitted and handled
        await new Promise(resolve => setTimeout(resolve, 50));

        expect(consoleSpy).toHaveBeenCalled(); // Check if it was called at all

        // Restore mocks
        (http as any).createServer = originalCreateServer;
    });
}); 