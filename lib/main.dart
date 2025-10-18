import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WiFi Gamepad',
      theme: ThemeData.dark(useMaterial3: true),
      home: const ConnectionPage(),
    );
  }
}

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isConnecting = false;

  @override
  void dispose() {
    _ipController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    final playerName = _nameController.text.trim();

    if (ip.isEmpty || playerName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enter IP and Player Name")),
        );
      }
      return;
    }

    setState(() => _isConnecting = true);

    Socket? socket;

    try {
      socket = await Socket.connect(
        ip,
        4040,
        timeout: const Duration(seconds: 5),
      );

      socket.write(jsonEncode({'type': 'connect', 'name': playerName}));
      socket.write('\n');
      await socket.flush();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Connected to $ip as $playerName")),
        );

        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                JoystickPage(socket: socket!, playerName: playerName),
          ),
        );

        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } on SocketException catch (e) {
      socket?.destroy();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "❌ Connection failed: ${e.message}\n\nMake sure:\n• Server is running\n• IP address is correct\n• Port 4040 is open",
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      socket?.destroy();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ Error: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "🎮 WiFi Gamepad Controller",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _ipController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: "Enter Server IP (e.g., 192.168.1.6)",
                  filled: true,
                  fillColor: Colors.white12,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: "Enter Player Name",
                  filled: true,
                  fillColor: Colors.white12,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _isConnecting ? null : _connect,
                icon: const Icon(Icons.wifi),
                label: Text(_isConnecting ? "Connecting..." : "Connect"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class JoystickPage extends StatefulWidget {
  final Socket socket;
  final String playerName;

  const JoystickPage({
    super.key,
    required this.socket,
    required this.playerName,
  });

  @override
  State<JoystickPage> createState() => _JoystickPageState();
}

class _JoystickPageState extends State<JoystickPage> {
  Offset _leftJoystickPosition = Offset.zero;
  Offset _rightJoystickPosition = Offset.zero;
  bool _isConnected = true;
  StreamSubscription? _socketSubscription;
  Timer? _keepAliveTimer;

  @override
  void initState() {
    super.initState();
    _setupSocket();
    _startKeepAlive();
  }

  void _setupSocket() {
    widget.socket.setOption(SocketOption.tcpNoDelay, true);

    _socketSubscription = widget.socket.listen(
      (data) {
        try {
          print('Received: ${utf8.decode(data)}');
        } catch (e) {
          print('Error decoding data: $e');
        }
      },
      onError: (error) {
        print('Socket error: $error');
        _handleDisconnect();
      },
      onDone: () {
        print('Socket closed by server');
        _handleDisconnect();
      },
      cancelOnError: false,
    );
  }

  void _startKeepAlive() {
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_isConnected) {
        try {
          _sendData('keepalive', {});
        } catch (e) {
          print('Keep-alive failed: $e');
          timer.cancel();
        }
      }
    });
  }

  void _handleDisconnect() {
    if (!mounted || !_isConnected) return;

    setState(() => _isConnected = false);
    _keepAliveTimer?.cancel();
    _socketSubscription?.cancel();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("❌ Disconnected from server"),
        duration: Duration(seconds: 2),
      ),
    );

    Navigator.of(context).pop();
  }

  void _sendData(String action, [Map<String, dynamic>? data]) {
    if (!_isConnected) return;

    try {
      final payload = jsonEncode({
        'player': widget.playerName,
        'action': action,
        'data': data ?? {},
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      widget.socket.write('$payload\n');
    } catch (e) {
      print('Error sending data: $e');
      _handleDisconnect();
    }
  }

  void _sendPressRelease(String buttonName, bool isPressed) {
    _sendData('button', {
      'name': buttonName,
      'state': isPressed ? 'pressed' : 'released',
    });
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    _socketSubscription?.cancel();

    try {
      widget.socket.write(jsonEncode({'action': 'disconnect'}));
      widget.socket.write('\n');
      widget.socket.flush();
    } catch (e) {
      print('Error on disconnect: $e');
    }

    widget.socket.destroy();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = constraints.maxWidth;
              final screenHeight = constraints.maxHeight;

              // More responsive sizing
              final joystickSize = (screenHeight * 0.32).clamp(100.0, 150.0);
              final buttonSize = (screenHeight * 0.10).clamp(45.0, 65.0);
              final smallButtonSize = buttonSize * 0.90;

              return Column(
                children: [
                  // Top Bar
                  SizedBox(height: screenHeight * 0.05, child: _buildTopBar()),
                  // Main Controller
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: _buildControllerLayout(
                        screenWidth: screenWidth,
                        screenHeight: screenHeight,
                        joystickSize: joystickSize,
                        buttonSize: buttonSize,
                        smallButtonSize: smallButtonSize,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ), // Reduced padding
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 20),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                  boxShadow: [
                    BoxShadow(
                      color: _isConnected
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _isConnected ? 'CONNECTED' : 'DISCONNECTED',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20), // Reduced right space
        ],
      ),
    );
  }

  Widget _buildControllerLayout({
    required double screenWidth,
    required double screenHeight,
    required double joystickSize,
    required double buttonSize,
    required double smallButtonSize,
  }) {
    final sideWidth = screenWidth * 0.30;
    final actionAreaSize = screenHeight * 0.38;
    final actionButtonSize = actionAreaSize * 0.38;

    return SizedBox(
      width: screenWidth,
      height: screenHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT SECTION
          SizedBox(
            width: sideWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // L2 and L1 buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildShoulderButton(
                      'L2',
                      sideWidth * 0.40,
                      screenHeight * 0.13,
                    ),
                    _buildShoulderButton(
                      'L1',
                      sideWidth * 0.40,
                      screenHeight * 0.13,
                    ),
                  ],
                ),
                // D-Pad (use actionButtonSize for button size)
                _buildDPad(screenHeight * 0.19, actionButtonSize),
                // Left Joystick
                _buildJoystick(
                  position: _leftJoystickPosition,
                  size: screenHeight * 0.28, // Increased size for left analog
                  onUpdate: (offset) {
                    setState(() => _leftJoystickPosition = offset);
                    const analogRadius = 0.28 / 2.5; // match new size
                    final x = offset.dx / (screenHeight * analogRadius);
                    final y = offset.dy / (screenHeight * analogRadius);
                    _sendData('left_joystick', {'x': x, 'y': y});
                  },
                  onEnd: () {
                    setState(() => _leftJoystickPosition = Offset.zero);
                    _sendData('left_joystick', {'x': 0, 'y': 0});
                  },
                  label: 'L',
                ),
              ],
            ),
          ),

          // CENTER SECTION
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // SELECT, PS, START buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildOptionButton('SELECT', () {
                      _sendData('button', {'name': 'select'});
                    }, screenWidth * 0.095),
                    SizedBox(width: screenWidth * 0.02),
                    _buildPSButton(screenHeight * 0.10),
                    SizedBox(width: screenWidth * 0.02),
                    _buildOptionButton('START', () {
                      _sendData('button', {'name': 'start'});
                    }, screenWidth * 0.095),
                  ],
                ),
                SizedBox(height: screenHeight * 0.15),
                // Right Joystick (moved to center, below buttons)
                _buildJoystick(
                  position: _rightJoystickPosition,
                  size: screenHeight * 0.29,
                  onUpdate: (offset) {
                    setState(() => _rightJoystickPosition = offset);
                    final x = offset.dx / ((screenHeight * 0.19) / 2.5);
                    final y = offset.dy / ((screenHeight * 0.19) / 2.5);
                    _sendData('right_joystick', {'x': x, 'y': y});
                  },
                  onEnd: () {
                    setState(() => _rightJoystickPosition = Offset.zero);
                    _sendData('right_joystick', {'x': 0, 'y': 0});
                  },
                  label: 'R',
                ),
              ],
            ),
          ),

          // RIGHT SECTION
          SizedBox(
            width: sideWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // R1 and R2 buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildShoulderButton(
                      'R1',
                      sideWidth * 0.38,
                      screenHeight * 0.13,
                    ),
                    _buildShoulderButton(
                      'R2',
                      sideWidth * 0.38,
                      screenHeight * 0.13,
                    ),
                  ],
                ),
                // Action Buttons (cross layout, perfectly centered)
                _buildActionButtons(actionAreaSize, actionButtonSize),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // D-Pad Builder (extra spacing between buttons)
  Widget _buildDPad(double areaSize, double buttonSize) {
    final dpadAreaSize = areaSize * 1.7; // Increase area for more spacing
    final dpadButtonSize = buttonSize * 0.8; // Make buttons smaller
    final center = dpadAreaSize / 2 - dpadButtonSize / 2;
    return SizedBox(
      width: dpadAreaSize,
      height: dpadAreaSize,
      child: Stack(
        children: [
          // UP
          Positioned(
            left: center,
            top: 0,
            child: _buildDPadButton(
              icon: Icons.arrow_upward,
              size: dpadButtonSize,
              onPressed: () => _sendData('button', {'name': 'dpad_up'}),
            ),
          ),
          // RIGHT
          Positioned(
            right: 0,
            top: center,
            child: _buildDPadButton(
              icon: Icons.arrow_forward,
              size: dpadButtonSize,
              onPressed: () => _sendData('button', {'name': 'dpad_right'}),
            ),
          ),
          // DOWN
          Positioned(
            left: center,
            bottom: 0,
            child: _buildDPadButton(
              icon: Icons.arrow_downward,
              size: dpadButtonSize,
              onPressed: () => _sendData('button', {'name': 'dpad_down'}),
            ),
          ),
          // LEFT
          Positioned(
            left: 0,
            top: center,
            child: _buildDPadButton(
              icon: Icons.arrow_back,
              size: dpadButtonSize,
              onPressed: () => _sendData('button', {'name': 'dpad_left'}),
            ),
          ),
          // CENTER
          // Positioned(
          //   left: center,
          //   top: center,
          //   child: Container(
          //     width: dpadButtonSize * 0.1,
          //     height: dpadButtonSize * 0.1,
          //     decoration: BoxDecoration(
          //       shape: BoxShape.circle,
          //       color: Colors.grey.withOpacity(0.3),
          //       border: Border.all(
          //         color: Colors.white.withOpacity(0.2),
          //         width: 1,
          //       ),
          //     ),
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _buildDPadButton({
    required IconData icon,
    required double size,
    required VoidCallback onPressed,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isPressed = false;

        return GestureDetector(
          onTapDown: _isConnected
              ? (_) {
                  setState(() => isPressed = true);
                  onPressed();
                  HapticFeedback.mediumImpact();
                }
              : null,
          onTapUp: (_) => setState(() => isPressed = false),
          onTapCancel: () => setState(() => isPressed = false),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: isPressed
                    ? [
                        Colors.cyan.withOpacity(0.4),
                        Colors.cyan.withOpacity(0.2),
                      ]
                    : [const Color(0xFF2a2a3e), const Color(0xFF1a1a2e)],
              ),
              border: Border.all(
                color: isPressed ? Colors.cyan : Colors.cyan.withOpacity(0.5),
                width: isPressed ? 2 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isPressed
                      ? Colors.cyan.withOpacity(0.5)
                      : Colors.black.withOpacity(0.5),
                  blurRadius: isPressed ? 8 : 4,
                  spreadRadius: isPressed ? 1 : 0,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.grey.withOpacity(isPressed ? 1.0 : 0.7),
              size: size * 0.45,
            ),
          ),
        );
      },
    );
  }

  // Action Buttons Builder (perfect cross, responsive)
  Widget _buildActionButtons(double areaSize, double buttonSize) {
    final center = areaSize / 2 - buttonSize / 2;
    return SizedBox(
      width: areaSize,
      height: areaSize,
      child: Stack(
        children: [
          // TRIANGLE (Top)
          Positioned(
            left: center,
            top: 0,
            child: _buildActionButton(
              symbol: '△',
              color: Colors.greenAccent,
              name: 'triangle',
              size: buttonSize,
            ),
          ),
          // CIRCLE (Right)
          Positioned(
            right: 0,
            top: center,
            child: _buildActionButton(
              symbol: '', // Remove 'O' text
              color: Colors.redAccent,
              name: 'circle',
              size: buttonSize,
              icon: Icons.circle_outlined, // Use Material icon for circle
            ),
          ),
          // X (Bottom)
          Positioned(
            left: center,
            bottom: 0,
            child: _buildActionButton(
              symbol: '✕',
              color: Colors.blueAccent,
              name: 'cross',
              size: buttonSize,
            ),
          ),
          // SQUARE (Left)
          Positioned(
            left: 0,
            top: center,
            child: _buildActionButton(
              symbol: '□',
              color: Colors.pinkAccent,
              name: 'square',
              size: buttonSize,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String symbol,
    required Color color,
    required String name,
    required double size,
    IconData? icon, // Optional icon parameter
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isPressed = false;

        return GestureDetector(
          onTapDown: _isConnected
              ? (_) {
                  setState(() => isPressed = true);
                  _sendPressRelease(name, true);
                  HapticFeedback.lightImpact();
                }
              : null,
          onTapUp: (_) {
            setState(() => isPressed = false);
            _sendPressRelease(name, false);
          },
          onTapCancel: () => setState(() => isPressed = false),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: isPressed
                    ? [color.withOpacity(0.6), color.withOpacity(0.3)]
                    : [const Color(0xFF2a2a3e), const Color(0xFF1a1a2e)],
              ),
              border: Border.all(
                color: isPressed ? color : color.withOpacity(0.6),
                width: isPressed ? 2.5 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isPressed
                      ? color.withOpacity(0.7)
                      : Colors.black.withOpacity(0.4),
                  blurRadius: isPressed ? 12 : 6,
                  spreadRadius: isPressed ? 2 : 0,
                ),
              ],
            ),
            child: Center(
              child: icon != null
                  ? Icon(icon, color: color, size: size * 0.40)
                  : Text(
                      symbol,
                      style: TextStyle(
                        color: color,
                        fontSize: size * 0.40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildJoystick({
    required Offset position,
    required double size,
    required Function(Offset) onUpdate,
    required VoidCallback onEnd,
    required String label,
  }) {
    final radius = size / 2.5;

    return GestureDetector(
      onPanUpdate: (details) {
        if (!_isConnected) return;
        final newPosition = Offset(
          (position.dx + details.delta.dx).clamp(-radius, radius),
          (position.dy + details.delta.dy).clamp(-radius, radius),
        );
        onUpdate(newPosition);
      },
      onPanEnd: (_) {
        if (!_isConnected) return;
        onEnd();
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [const Color(0xFF1a2a4a), const Color(0xFF0a1a3a)],
          ),
          border: Border.all(
            color: Colors.cyanAccent.withOpacity(0.4),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.3),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size * 0.7,
              height: size * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            Transform.translate(
              offset: position,
              child: Container(
                width: size * 0.35,
                height: size * 0.35,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.cyanAccent.withOpacity(0.8),
                      Colors.blueAccent.withOpacity(0.6),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.8),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShoulderButton(String label, double width, double height) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isPressed = false;

        return GestureDetector(
          onTapDown: _isConnected
              ? (_) {
                  setState(() => isPressed = true);
                  _sendPressRelease(label.toLowerCase(), true);
                  HapticFeedback.mediumImpact();
                }
              : null,
          onTapUp: (_) {
            setState(() => isPressed = false);
            _sendPressRelease(label.toLowerCase(), false);
          },

          onTapCancel: () => setState(() => isPressed = false),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: isPressed
                    ? [
                        Colors.cyanAccent.withOpacity(0.4),
                        Colors.cyanAccent.withOpacity(0.2),
                      ]
                    : [const Color(0xFF2a2a3e), const Color(0xFF1a1a2e)],
              ),
              border: Border.all(
                color: isPressed
                    ? Colors.cyanAccent
                    : Colors.cyanAccent.withOpacity(0.5),
                width: isPressed ? 2 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isPressed
                      ? Colors.cyanAccent.withOpacity(0.5)
                      : Colors.black.withOpacity(0.5),
                  blurRadius: isPressed ? 10 : 5,
                  spreadRadius: isPressed ? 1 : 0,
                ),
              ],
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isPressed ? Colors.cyanAccent : Colors.white70,
                  fontSize: height * 0.32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSmallButton(String label, double size) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isPressed = false;

        return GestureDetector(
          onTapDown: _isConnected
              ? (_) {
                  setState(() => isPressed = true);
                  _sendData('button', {'name': label.toLowerCase()});
                  HapticFeedback.mediumImpact();
                }
              : null,
          onTapUp: (_) => setState(() => isPressed = false),
          onTapCancel: () => setState(() => isPressed = false),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                colors: isPressed
                    ? [
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.1),
                      ]
                    : [const Color(0xFF2a2a3e), const Color(0xFF1a1a2e)],
              ),
              border: Border.all(
                color: isPressed ? Colors.white : Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(isPressed ? 1.0 : 0.6),
                  fontSize: size * 0.26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionButton(
    String label,
    VoidCallback onPressed,
    double width,
  ) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isPressed = false;

        return GestureDetector(
          onTapDown: _isConnected
              ? (_) {
                  setState(() => isPressed = true);
                  onPressed();
                  HapticFeedback.selectionClick();
                }
              : null,
          onTapUp: (_) => setState(() => isPressed = false),
          onTapCancel: () => setState(() => isPressed = false),
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                colors: isPressed
                    ? [
                        Colors.white.withOpacity(0.15),
                        Colors.white.withOpacity(0.05),
                      ]
                    : [Colors.white.withOpacity(0.05), Colors.transparent],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(isPressed ? 0.4 : 0.2),
                width: 1,
              ),
              boxShadow: [
                if (isPressed)
                  BoxShadow(
                    color: Colors.white.withOpacity(0.2),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(isPressed ? 0.9 : 0.6),
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPSButton(double size) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isPressed = false;

        return GestureDetector(
          onTapDown: _isConnected
              ? (_) {
                  setState(() => isPressed = true);
                  _sendData('button', {'name': 'ps'});
                  HapticFeedback.heavyImpact();
                }
              : null,
          onTapUp: (_) => setState(() => isPressed = false),
          onTapCancel: () => setState(() => isPressed = false),
          child: Container(
            width: size * 0.75,
            height: size * 0.75,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: isPressed
                    ? [
                        Colors.blueAccent.withOpacity(0.6),
                        Colors.blueAccent.withOpacity(0.3),
                      ]
                    : [const Color(0xFF2a2a3e), const Color(0xFF1a1a2e)],
              ),
              border: Border.all(
                color: isPressed
                    ? Colors.blueAccent
                    : Colors.blueAccent.withOpacity(0.5),
                width: isPressed ? 2 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isPressed
                      ? Colors.blueAccent.withOpacity(0.6)
                      : Colors.black.withOpacity(0.5),
                  blurRadius: isPressed ? 12 : 6,
                  spreadRadius: isPressed ? 2 : 0,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.videogame_asset,
                color: isPressed
                    ? Colors.blueAccent
                    : Colors.blueAccent.withOpacity(0.7),
                size: size * 0.30,
              ),
            ),
          ),
        );
      },
    );
  }
}
