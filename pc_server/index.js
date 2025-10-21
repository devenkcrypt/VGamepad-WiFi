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
            const padNumber = message.pad || 1; // Default to pad 1 if not specified
            playerId = `Player_${Date.now()}_${Math.random()
              .toString(36)
              .substr(2, 9)}`;

            clients.set(clientId, {
              socket,
              playerName,
              playerId,
              padNumber,
              address: socket.remoteAddress,
              connectedAt: new Date(),
            });

            activePlayers.set(playerId, {
              name: playerName,
              padNumber: padNumber,
              lastInput: null,
              inputCount: 0,
            });

            console.log(
              `👤 Player "${playerName}" registered (${playerId}) - Pad ${padNumber}`
            );
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
  const { action, data, pad } = message;
  const padNumber = pad || 1; // Default to pad 1 if not specified

  if (action === "left_joystick") {
    handleLeftJoystick(data, playerName, padNumber);
  } else if (action === "right_joystick") {
    handleRightJoystick(data, playerName, padNumber);
  } else if (action === "button") {
    handleButton(data, playerName, padNumber);
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
      pad: padNumber,
      timestamp: new Date().toISOString(),
    };
    activePlayers.get(playerId).inputCount++;
  }
}

function handleLeftJoystick(data, playerName, padNumber) {
  const { x, y } = data;
  const deadzone = 0.2;

  // Different key mappings for different pads
  const keyMap = getPadKeyMap(padNumber);

  // Left/Right (A/D keys)
  if (x > deadzone) {
    keyDown(keyMap.right); // right
    keyUp(keyMap.left);
  } else if (x < -deadzone) {
    keyDown(keyMap.left); // left
    keyUp(keyMap.right);
  } else {
    keyUp(keyMap.left);
    keyUp(keyMap.right);
  }

  // Forward/Backward (W/S keys)
  // Note: Y is positive downward, negative upward
  if (y < -deadzone) {
    keyDown(keyMap.forward); // forward
    keyUp(keyMap.backward);
  } else if (y > deadzone) {
    keyDown(keyMap.backward); // backward
    keyUp(keyMap.forward);
  } else {
    keyUp(keyMap.forward);
    keyUp(keyMap.backward);
  }
}

function handleRightJoystick(data, playerName, padNumber) {
  const { x, y } = data;
  const deadzone = 0.2;

  // Different key mappings for different pads
  const keyMap = getPadKeyMap(padNumber);

  // Right joystick for camera control (Arrow keys)
  if (x > deadzone) {
    keyDown(keyMap.lookRight); // look right
    keyUp(keyMap.lookLeft);
  } else if (x < -deadzone) {
    keyDown(keyMap.lookLeft); // look left
    keyUp(keyMap.lookRight);
  } else {
    keyUp(keyMap.lookLeft);
    keyUp(keyMap.lookRight);
  }

  // Look up/down
  if (y < -deadzone) {
    keyDown(keyMap.lookUp); // look up
    keyUp(keyMap.lookDown);
  } else if (y > deadzone) {
    keyDown(keyMap.lookDown); // look down
    keyUp(keyMap.lookUp);
  } else {
    keyUp(keyMap.lookUp);
    keyUp(keyMap.lookDown);
  }
}

function handleButton(data, playerName, padNumber) {
  const buttonName = data.name;
  const state = data.state || "tap"; // default is tap if not given

  // Get pad-specific key mapping
  const padKeyMap = getPadButtonMap(padNumber);
  const key = padKeyMap[buttonName];
  if (!key) {
    console.log(
      `❌ [${playerName} - Pad ${padNumber}] Unknown button: ${buttonName}`
    );
    return;
  }

  // Ultra-fast response for gaming
  if (state === "press") {
    // For press, immediate key press
    try {
      robot.keyToggle(key, "down");
      // Immediate release for single tap
      setTimeout(() => {
        robot.keyToggle(key, "up");
      }, 1);
    } catch (e) {
      console.error(`Error pressing ${key}:`, e.message);
    }
    console.log(
      `⬆️ [${playerName} - Pad ${padNumber}] Pressed: ${buttonName} -> ${key}`
    );
  } else if (state === "release") {
    // For release, just log (no action needed)
    console.log(
      `⬇️ [${playerName} - Pad ${padNumber}] Released: ${buttonName} -> ${key}`
    );
  } else {
    // For tap, immediate key press
    try {
      robot.keyToggle(key, "down");
      // Immediate release for single tap
      setTimeout(() => {
        robot.keyToggle(key, "up");
      }, 1);
    } catch (e) {
      console.error(`Error tapping ${key}:`, e.message);
    }
    console.log(
      `🎮 [${playerName} - Pad ${padNumber}] Tapped: ${buttonName} -> ${key}`
    );
  }
}

// Key mapping functions for different controller pads
function getPadKeyMap(padNumber) {
  const keyMaps = {
    1: {
      // Pad 1 - WASD + Arrow keys
      left: "a",
      right: "d",
      forward: "w",
      backward: "s",
      lookLeft: "left",
      lookRight: "right",
      lookUp: "up",
      lookDown: "down",
    },
    2: {
      // Pad 2 - IJKL + Different keys (NO CONFLICT with Pad 1)
      left: "j",
      right: "l",
      forward: "i",
      backward: "k",
      lookLeft: "1",
      lookRight: "2",
      lookUp: "3",
      lookDown: "4",
    },
    3: {
      // Pad 3 - TFGH + Different keys (NO CONFLICT)
      left: "f",
      right: "h",
      forward: "t",
      backward: "g",
      lookLeft: "5",
      lookRight: "6",
      lookUp: "7",
      lookDown: "8",
    },
    4: {
      // Pad 4 - YUIO + Different keys (NO CONFLICT)
      left: "u",
      right: "o",
      forward: "y",
      backward: "i",
      lookLeft: "9",
      lookRight: "0",
      lookUp: "minus",
      lookDown: "equal",
    },
  };

  return keyMaps[padNumber] || keyMaps[1]; // Default to pad 1
}

function getPadButtonMap(padNumber) {
  const buttonMaps = {
    1: {
      // Pad 1 - Default keys (NO CONFLICTS)
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
    },
    2: {
      // Pad 2 - Completely different keys (NO CONFLICTS)
      triangle: "r",
      circle: "v",
      cross: "b",
      square: "n",
      l1: "w",
      r1: "y",
      l2: "t",
      r2: "u",
      start: "f1",
      select: "f2",
      ps: "f3",
      dpad_up: "i",
      dpad_down: "k",
      dpad_left: "j",
      dpad_right: "l",
    },
    3: {
      // Pad 3 - Different keys (NO CONFLICTS)
      triangle: "g",
      circle: "h",
      cross: "j",
      square: "k",
      l1: "7",
      r1: "8",
      l2: "9",
      r2: "0",
      start: "f4",
      select: "f5",
      ps: "f6",
      dpad_up: "7",
      dpad_down: "8",
      dpad_left: "5",
      dpad_right: "6",
    },
    4: {
      // Pad 4 - Different keys (NO CONFLICTS)
      triangle: "l",
      circle: "z",
      cross: "x",
      square: "c",
      l1: "v",
      r1: "b",
      l2: "n",
      r2: "m",
      start: "f7",
      select: "f8",
      ps: "f9",
      dpad_up: "9",
      dpad_down: "0",
      dpad_left: "7",
      dpad_right: "8",
    },
  };

  return buttonMaps[padNumber] || buttonMaps[1]; // Default to pad 1
}

// Key state management to prevent repeated key presses
const keyState = {};

function keyDown(key) {
  if (keyState[key]) return;
  keyState[key] = true;
  try {
    robot.keyToggle(key, "down");
    // Ultra-fast release for gaming
    setTimeout(() => {
      if (keyState[key]) {
        robot.keyToggle(key, "up");
        keyState[key] = false;
      }
    }, 1);
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
    // Ultra-fast tap for gaming
    robot.keyToggle(key, "down");
    setTimeout(() => {
      robot.keyToggle(key, "up");
    }, 1);
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

// Force release all keys for PCSX2 compatibility
function forceReleaseAllKeys() {
  const keysToRelease = [
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "0",
    "f1",
    "f2",
    "f3",
    "f4",
    "f5",
    "f6",
    "f7",
    "f8",
    "f9",
    "f10",
    "f11",
    "f12",
    "enter",
    "backspace",
    "space",
    "tab",
    "up",
    "down",
    "left",
    "right",
  ];

  keysToRelease.forEach((key) => {
    try {
      robot.keyToggle(key, "up");
    } catch (e) {
      // Ignore errors for keys that might not be pressed
    }
  });

  // Clear key state
  Object.keys(keyState).forEach((key) => {
    keyState[key] = false;
  });
}

function broadcastPlayersUpdate() {
  const playersList = Array.from(activePlayers.entries()).map(
    ([playerId, data]) => ({
      playerId,
      name: data.name,
      padNumber: data.padNumber,
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
    console.log(
      `   • ${p.name} (${p.playerId}) - Pad ${p.padNumber} - Inputs: ${p.inputCount}`
    );
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
    console.log(
      `   • ${data.name} (Pad ${data.padNumber}): ${data.inputCount} inputs received`
    );
  });
  console.log("");
}, 30000);

// Force release all keys every 30 seconds to prevent PCSX2 key sticking (less frequent)
setInterval(() => {
  forceReleaseAllKeys();
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
        padNumber: data.padNumber,
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
