const { Client } = require('@modelcontextprotocol/sdk/client/index.js');
const { SSEClientTransport } = require('@modelcontextprotocol/sdk/client/sse.js');
const { spawn } = require('child_process');
const net = require('net');

function waitPort(port, host, timeoutMs = 20000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const check = () => {
      const socket = new net.Socket();
      socket.connect(port, host);
      socket.on('connect', () => {
        socket.destroy();
        resolve();
      });
      socket.on('error', () => {
        if (Date.now() - start > timeoutMs) {
          reject(new Error(`Timeout waiting for port ${port}`));
        } else {
          setTimeout(check, 500);
        }
      });
    };
    check();
  });
}

async function runTest() {
  console.log('Starting Godot server with MCP App Demo scene in headless mode...');
  const godotProcess = spawn('godot', [
    '--headless',
    '--path', '.',
    'res://addons/mcp_server/examples/mcp_app_demo.tscn'
  ], { stdio: 'ignore' });

  // Handle cleanup on exit
  const cleanup = () => {
    console.log('Stopping Godot server...');
    godotProcess.kill();
  };
  process.on('exit', cleanup);
  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);

  try {
    console.log('Waiting for Godot server to start on port 9090...');
    await waitPort(9090, '127.0.0.1');
    console.log('Port 9090 is open. Initializing MCP client...');

    const client = new Client(
      { name: 'mcp-app-test-client', version: '1.0.0' },
      { capabilities: { resources: {} } }
    );

    const transport = new SSEClientTransport(new URL('http://127.0.0.1:9090/sse'));
    console.log('Connecting to transport...');
    await client.connect(transport);
    console.log('Connected to server successfully!');

    // 1. Verify resources
    console.log('Listing resources...');
    const resourcesResp = await client.listResources();
    console.log('Resources found:', JSON.stringify(resourcesResp.resources, null, 2));

    const demoPanel = resourcesResp.resources.find(r => r.uri === 'ui://demo/panel');
    if (!demoPanel) {
      throw new Error("FAIL: 'ui://demo/panel' resource not found in list");
    }
    if (demoPanel.mimeType !== 'text/html;profile=mcp-app') {
      throw new Error(`FAIL: Expected mimeType 'text/html;profile=mcp-app', got '${demoPanel.mimeType}'`);
    }
    console.log('✓ Resource list verification passed!');

    // 2. Verify resource contents
    console.log("Reading resource 'ui://demo/panel'...");
    const contentResp = await client.readResource({ uri: 'ui://demo/panel' });
    const content = contentResp.contents[0];
    if (!content || !content.text) {
      throw new Error("FAIL: Resource content is empty or missing 'text' field");
    }
    if (!content.text.includes('Godot Control Center') || !content.text.includes('window.parent.postMessage')) {
      throw new Error("FAIL: Resource content does not match expected UI HTML structure");
    }
    console.log('✓ Resource content verification passed!');

    // 3. Verify tools & metadata
    console.log('Listing tools...');
    const toolsResp = await client.listTools();
    console.log('Tools found:', JSON.stringify(toolsResp.tools, null, 2));

    const spawnTool = toolsResp.tools.find(t => t.name === 'app_demo_spawn');
    if (!spawnTool) {
      throw new Error("FAIL: 'app_demo_spawn' tool not found in list");
    }
    if (!spawnTool._meta || !spawnTool._meta.ui || spawnTool._meta.ui.resourceUri !== 'ui://demo/panel') {
      throw new Error(`FAIL: Tool metadata missing or does not point to 'ui://demo/panel'. Got: ${JSON.stringify(spawnTool._meta)}`);
    }
    console.log('✓ Tool metadata verification passed!');

    // 4. Test tool invocation
    console.log("Calling tool 'app_demo_slowmo' with scale: 0.1...");
    const toolCallResp = await client.callTool({
      name: 'app_demo_slowmo',
      arguments: { scale: 0.1 }
    });
    console.log('Tool invocation response:', JSON.stringify(toolCallResp, null, 2));
    if (toolCallResp.isError) {
      throw new Error('FAIL: Tool returned an error status');
    }
    console.log('✓ Tool invocation verification passed!');

    console.log('\n======================================');
    console.log('🎉 ALL INTEGRATION TESTS PASSED SUCCESSFULLY!');
    console.log('======================================');

    await client.close();
    process.exit(0);
  } catch (err) {
    console.error('\n❌ TEST RUN FAILED:', err);
    process.exit(1);
  }
}

runTest();
