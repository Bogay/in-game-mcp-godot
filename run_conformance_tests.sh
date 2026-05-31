#!/bin/bash

# Define cleanup function to kill Godot process on exit
cleanup() {
    if [ -n "$GODOT_PID" ]; then
        echo "Stopping Godot server (PID: $GODOT_PID)..."
        kill "$GODOT_PID" 2>/dev/null
        wait "$GODOT_PID" 2>/dev/null
    fi
}
trap cleanup EXIT

echo "Starting Godot server in headless mode..."
flatpak run org.godotengine.Godot --headless --path . &
GODOT_PID=$!

# Wait for server to start up (listening on port 9090)
echo "Waiting for port 9090 to open..."
TIMEOUT=20
while ! (echo > /dev/tcp/127.0.0.1/9090) >/dev/null 2>&1; do
    sleep 0.5
    TIMEOUT=$((TIMEOUT-1))
    if [ $TIMEOUT -le 0 ]; then
        echo "Error: Timed out waiting for Godot server to start."
        exit 1
    fi
done

echo "Godot server started successfully on port 9090."
echo "Running Model Context Protocol conformance tests..."

# Run the @modelcontextprotocol/conformance server tests
npx -y @modelcontextprotocol/conformance server --url http://127.0.0.1:9090/sse
TEST_EXIT_CODE=$?

echo "Tests completed with exit code: $TEST_EXIT_CODE"
exit $TEST_EXIT_CODE
