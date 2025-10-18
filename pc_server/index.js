// index.js - TCP Socket Server with Multiplayer Support
const net = require("net");
const robot = require("robotjs");

const PORT = 4040;
const clients = new Map(); // Store all connected clients
const activePlayers = new Map(); // Track player states

const server = net.createServer((socket) => {
  const clientId = `${socket.remoteAddress}:${socket.remotePort}`;
  console.log(`✅ Client connected: ${clientId}`);

  let playerName = "Unknown";
  let playerId = null;
  let buffer = "";

  socket.on("data", (data) => {
    try {
      buffer += data.toString();

      // Process complete JSON messages (separated by newlines)
      const lines = buffer.split("\n");
      buffer = lines.pop(); // Keep incomplete line in buffer

      lines.forEach((line) => {
        if (line.trim()) {
          const message = JSON.parse(line);

          // Handle player connection
          if (message.type === "connect" && message.name) {
            playerName = message.name;
            playerId = `Player_${Date.now()}_${Math.random()
              .toString(36)
              .substr(2, 9)}`;

            clients.set(clientId, {
              socket,
              playerName,
              playerId,
              address: socket.remoteAddress,
              connectedAt: new Date(),
            });

            activePlayers.set(playerId, {
              name: playerName,
              lastInput: null,
              inputCount: 0,
            });

            console.log(`👤 Player "${playerName}" registered (${playerId})`);
            broadcastPlayersUpdate();
            return;
          }

          // Handle controller input
          if (message.action && playerId) {
            handleInput(message, playerName, playerId);
          }
        }
      });
    } catch (e) {
      console.error("Parse error:", e.message);
    }
  });

  socket.on("error", (err) => {
    console.error(`❌ Socket error for ${playerName}:`, err.message);
  });

  socket.on("close", () => {
    console.log(`📌 Client disconnected: ${playerName} (${playerId})`);
    clients.delete(clientId);
    if (playerId) {
      activePlayers.delete(playerId);
    }
    releaseAllKeys();
    broadcastPlayersUpdate();
  });
});

function handleInput(message, playerName, playerId) {
  const { action, data } = message;

  if (action === "left_joystick") {
    handleLeftJoystick(data, playerName);
  } else if (action === "right_joystick") {
    handleRightJoystick(data, playerName);
  } else if (action === "button") {
    handleButton(data, playerName);
  } else if (action === "keepalive") {
    // Keep-alive message - just ignore it
    return;
  } else if (action === "disconnect") {
    console.log(`👋 ${playerName} disconnecting gracefully`);
    return;
  }

  // Update player's last input
  if (activePlayers.has(playerId)) {
    activePlayers.get(playerId).lastInput = {
      action,
      data,
      timestamp: new Date().toISOString(),
    };
    activePlayers.get(playerId).inputCount++;
  }
}

function handleLeftJoystick(data, playerName) {
  const { x, y } = data;
  const deadzone = 0.2;

  // Left/Right (A/D keys)
  if (x > deadzone) {
    keyDown("d"); // right
    keyUp("a");
  } else if (x < -deadzone) {
    keyDown("a"); // left
    keyUp("d");
  } else {
    keyUp("a");
    keyUp("d");
  }

  // Forward/Backward (W/S keys)
  // Note: Y is positive downward, negative upward
  if (y < -deadzone) {
    keyDown("w"); // forward
    keyUp("s");
  } else if (y > deadzone) {
    keyDown("s"); // backward
    keyUp("w");
  } else {
    keyUp("w");
    keyUp("s");
  }
}

function handleRightJoystick(data, playerName) {
  const { x, y } = data;
  const deadzone = 0.2;

  // Right joystick for camera control (Arrow keys)
  if (x > deadzone) {
    keyDown("right"); // look right
    keyUp("left");
  } else if (x < -deadzone) {
    keyDown("left"); // look left
    keyUp("right");
  } else {
    keyUp("left");
    keyUp("right");
  }

  // Look up/down
  if (y < -deadzone) {
    keyDown("up"); // look up
    keyUp("down");
  } else if (y > deadzone) {
    keyDown("down"); // look down
    keyUp("up");
  } else {
    keyUp("up");
    keyUp("down");
  }
}

function handleButton(data, playerName) {
  const buttonName = data.name;
  const state = data.state || "tap"; // default is tap if not given

  // Mapping of buttons to keys
  const keyMap = {
    triangle: "e",
    circle: "c",
    cross: "z",
    square: "x",
    l1: "q",
    r1: "t",
    l2: "m",
    r2: "n",
    start: "enter",
    select: "backspace",
    ps: "p",
    dpad_up: "up",
    dpad_down: "down",
    dpad_left: "left",
    dpad_right: "right",
  };

  const key = keyMap[buttonName];
  if (!key) return;

  // Handle press / release / tap logic
  if (state === "press") {
    keyDown(key);
    console.log(`⬆️ [${playerName}] Holding: ${buttonName}`);
  } else if (state === "release") {
    keyUp(key);
    console.log(`⬇️ [${playerName}] Released: ${buttonName}`);
  } else {
    tapKey(key); // single quick tap (default)
    console.log(`🎮 [${playerName}] Tapped: ${buttonName}`);
  }
}

// Key state management to prevent repeated key presses
const keyState = {};

function keyDown(key) {
  if (keyState[key]) return;
  keyState[key] = true;
  try {
    robot.keyToggle(key, "down");
  } catch (e) {
    console.error(`Error pressing ${key}:`, e.message);
  }
}

function keyUp(key) {
  if (!keyState[key]) return;
  keyState[key] = false;
  try {
    robot.keyToggle(key, "up");
  } catch (e) {
    console.error(`Error releasing ${key}:`, e.message);
  }
}

function tapKey(key) {
  try {
    robot.keyTap(key);
  } catch (e) {
    console.error(`Error tapping ${key}:`, e.message);
  }
}

function releaseAllKeys() {
  Object.keys(keyState).forEach((key) => {
    if (keyState[key]) {
      keyUp(key);
    }
  });
}

function broadcastPlayersUpdate() {
  const playersList = Array.from(activePlayers.entries()).map(
    ([playerId, data]) => ({
      playerId,
      name: data.name,
      inputCount: data.inputCount,
      lastInput: data.lastInput,
    })
  );

  const update = {
    type: "players_update",
    totalPlayers: activePlayers.size,
    players: playersList,
    timestamp: new Date().toISOString(),
  };

  console.log(`\n👥 ACTIVE PLAYERS: ${activePlayers.size}`);
  playersList.forEach((p) => {
    console.log(`   • ${p.name} (${p.playerId}) - Inputs: ${p.inputCount}`);
  });
  console.log("");

  // Send update to all connected clients
  clients.forEach((clientData) => {
    try {
      clientData.socket.write(JSON.stringify(update) + "\n");
    } catch (e) {
      console.error(`Failed to send update: ${e.message}`);
    }
  });
}

// Display server stats every 30 seconds
setInterval(() => {
  console.log(`\n📊 SERVER STATS:`);
  console.log(`   • Connected Clients: ${clients.size}`);
  console.log(`   • Active Players: ${activePlayers.size}`);

  activePlayers.forEach((data, playerId) => {
    console.log(`   • ${data.name}: ${data.inputCount} inputs received`);
  });
  console.log("");
}, 30000);

server.listen(PORT, "0.0.0.0", () => {
  console.log("🎮 WiFi Gamepad TCP Server (Multiplayer)");
  console.log(`📡 Listening on port ${PORT}`);
  console.log(`🌐 Connect from Flutter app using this device's IP address`);
  console.log(`👥 Supports multiple simultaneous players`);
  console.log("---\n");
});

server.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    console.error(`❌ Port ${PORT} is already in use!`);
    process.exit(1);
  } else {
    console.error("❌ Server error:", err);
  }
});

const http = require("http");

// HTTP server port (different from TCP)
const HTTP_PORT = 8080;

const httpServer = http.createServer((req, res) => {
  if (req.url === "/") {
    // Simple status page
    const players = Array.from(activePlayers.entries()).map(
      ([playerId, data]) => ({
        playerId,
        name: data.name,
        inputCount: data.inputCount,
        lastInput: data.lastInput,
      })
    );

    const status = {
      server: "WiFi Gamepad TCP Server",
      tcpPort: PORT,
      totalPlayers: activePlayers.size,
      players,
      timestamp: new Date().toISOString(),
    };

    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(status, null, 2));
  } else {
    res.writeHead(404);
    res.end("Not found");
  }
});

httpServer.listen(HTTP_PORT, "0.0.0.0", () => {
  console.log(`🌐 HTTP Status Server running on http://0.0.0.0:${HTTP_PORT}`);
  console.log(`💻 Access this from Chrome or any browser`);
});
