export interface StringReplacement {
  find: string;
  replace: string;
}

export interface ProxyOptions {
  originalHost: string; // e.g., https://example.com
  injectScriptHeader?: string;
  injectScriptFooter?: string;
  stringReplacements?: StringReplacement[];
  // Port is handled by the server listening, not the handler itself
  // targetHost and targetProtocol will be derived from originalHost
} 