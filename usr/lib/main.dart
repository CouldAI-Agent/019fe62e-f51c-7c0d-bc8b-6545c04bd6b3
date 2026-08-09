import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const InfiniteRunnerApp());
}

class InfiniteRunnerApp extends StatelessWidget {
  const InfiniteRunnerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infinite Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      initialRoute: '/',
      routes: {
        '/': (context) => const GameScreen(),
      },
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  _GameScreenState createState() => _GameScreenState();
}

enum GameState { menu, playing, gameOver }

enum Biome {
  city, village, jungle, desert, snowyMountains,
  beach, highway, nightCity, ancientRuins, futuristicCity
}

class GameObject {
  double z; // Distance from camera
  int lane; // -1, 0, 1
  int type; // 0: coin, 1: barrier, 2: gap, 3: magnet, 4: shield, 5: speed, 6: multiplier

  GameObject({required this.z, required this.lane, required this.type});
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  GameState _gameState = GameState.menu;

  // Player state
  int _lane = 0; // -1: left, 0: center, 1: right
  double _jumpY = 0.0;
  double _jumpVelocity = 0.0;
  bool _isSliding = false;
  double _slideDuration = 0.0;
  bool _hasShield = false;
  bool _hasMagnet = false;
  int _multiplier = 1;
  double _speedBoost = 1.0;

  // Game stats
  double _speed = 20.0;
  double _distance = 0.0;
  int _score = 0;
  int _coins = 0;
  int _highScore = 0;

  // World state
  List<GameObject> _objects = [];
  Biome _currentBiome = Biome.city;
  double _biomeTransition = 0.0;
  double _fov = 90.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _startGame() {
    setState(() {
      _gameState = GameState.playing;
      _lane = 0;
      _jumpY = 0;
      _jumpVelocity = 0;
      _isSliding = false;
      _speed = 30.0;
      _distance = 0;
      _score = 0;
      _coins = 0;
      _objects.clear();
      _currentBiome = Biome.city;
      _hasShield = false;
      _hasMagnet = false;
      _multiplier = 1;
      _speedBoost = 1.0;
    });
    _generateObjects(100, 1000);
    _ticker.start();
  }

  void _gameOver() {
    _ticker.stop();
    if (_score > _highScore) _highScore = _score;
    setState(() {
      _gameState = GameState.gameOver;
    });
  }

  void _generateObjects(double startZ, double endZ) {
    Random rand = Random();
    for (double z = startZ; z < endZ; z += 50.0 + rand.nextDouble() * 100.0) {
      int type = rand.nextInt(10);
      int lane = rand.nextInt(3) - 1;
      
      if (type < 4) {
        // Coin
        _objects.add(GameObject(z: z, lane: lane, type: 0));
        // Add a line of coins
        for (int i=1; i<5; i++) {
          _objects.add(GameObject(z: z + i*15, lane: lane, type: 0));
        }
      } else if (type < 7) {
        // Barrier
        _objects.add(GameObject(z: z, lane: lane, type: 1));
      } else if (type < 8) {
        // Gap
        _objects.add(GameObject(z: z, lane: lane, type: 2));
      } else {
        // Powerups (rare)
        if (rand.nextDouble() < 0.2) {
          _objects.add(GameObject(z: z, lane: lane, type: 3 + rand.nextInt(4)));
        }
      }
    }
  }

  void _onTick(Duration elapsed) {
    setState(() {
      double dt = 0.016; // Approx 60fps
      _distance += _speed * _speedBoost * dt;
      _score = (_distance).floor() + (_coins * 10);
      
      // Speed increases over distance
      _speed = 30.0 + (_distance / 500.0).clamp(0.0, 50.0);

      // Change biome every 1000 units
      int nextBiomeIdx = ((_distance / 1000.0).floor()) % Biome.values.length;
      if (Biome.values[nextBiomeIdx] != _currentBiome) {
        _currentBiome = Biome.values[nextBiomeIdx];
      }

      // Player jump physics
      if (_jumpY > 0 || _jumpVelocity != 0) {
        _jumpY += _jumpVelocity * dt * 50;
        _jumpVelocity -= 9.8 * dt * 10; // Gravity
        if (_jumpY <= 0) {
          _jumpY = 0;
          _jumpVelocity = 0;
        }
      }

      // Slide duration
      if (_isSliding) {
        _slideDuration -= dt;
        if (_slideDuration <= 0) {
          _isSliding = false;
        }
      }

      // Object logic and collision
      for (int i = _objects.length - 1; i >= 0; i--) {
        GameObject obj = _objects[i];
        
        // Magnet effect
        if (_hasMagnet && obj.type == 0 && obj.z - _distance < 100) {
          if (obj.lane < _lane) obj.lane++;
          else if (obj.lane > _lane) obj.lane--;
        }

        if (obj.z < _distance) {
          // Missed or passed
          _objects.removeAt(i);
        } else if (obj.z < _distance + 10) {
          // Collision zone
          if (obj.lane == _lane) {
            if (obj.type == 0) {
              // Collect coin
              _coins += _multiplier;
              _objects.removeAt(i);
            } else if (obj.type == 1) {
              // Barrier - jump or slide depending on barrier type (simplified: hit barrier if not high enough)
              if (_jumpY < 10) {
                if (_hasShield) {
                  _hasShield = false;
                  _objects.removeAt(i);
                } else {
                  _gameOver();
                }
              }
            } else if (obj.type == 2) {
              // Gap - must be jumping
              if (_jumpY < 5) {
                _gameOver();
              }
            } else {
              // Powerups
              _applyPowerup(obj.type);
              _objects.removeAt(i);
            }
          }
        }
      }

      // Generate new objects as we move
      if (_objects.isEmpty || _objects.last.z < _distance + 1000) {
        _generateObjects(_distance + 1000, _distance + 2000);
      }
    });
  }

  void _applyPowerup(int type) {
    if (type == 3) _hasMagnet = true;
    if (type == 4) _hasShield = true;
    if (type == 5) _speedBoost = 1.5;
    if (type == 6) _multiplier = 2;
    // Reset powerups after 10s via Future (simplified)
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          if (type == 3) _hasMagnet = false;
          if (type == 5) _speedBoost = 1.0;
          if (type == 6) _multiplier = 1;
        });
      }
    });
  }

  void _handleSwipe(DragEndDetails details) {
    if (_gameState != GameState.playing) return;
    
    double dx = details.velocity.pixelsPerSecond.dx;
    double dy = details.velocity.pixelsPerSecond.dy;

    if (dx.abs() > dy.abs()) {
      // Horizontal
      if (dx > 0 && _lane < 1) {
        setState(() => _lane++);
      } else if (dx < 0 && _lane > -1) {
        setState(() => _lane--);
      }
    } else {
      // Vertical
      if (dy < 0 && _jumpY == 0) {
        // Jump
        setState(() {
          _jumpVelocity = 25.0;
          _isSliding = false;
        });
      } else if (dy > 0 && _jumpY == 0) {
        // Slide
        setState(() {
          _isSliding = true;
          _slideDuration = 1.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanEnd: _handleSwipe,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Game rendering
            CustomPaint(
              painter: GameRenderer(
                distance: _distance,
                lane: _lane,
                jumpY: _jumpY,
                objects: _objects,
                biome: _currentBiome,
                isSliding: _isSliding,
                hasShield: _hasShield,
              ),
            ),
            
            // HUD
            if (_gameState == GameState.playing)
              Positioned(
                top: 50,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Score: $_score\nDistance: ${_distance.floor()}m', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                    Text('Coins: $_coins', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amber, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                  ],
                ),
              ),
              
            // Powerup indicators
            if (_gameState == GameState.playing)
              Positioned(
                top: 100,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_hasShield) const Icon(Icons.shield, color: Colors.blue, size: 30),
                    if (_hasMagnet) const Icon(Icons.magnet, color: Colors.red, size: 30),
                    if (_multiplier > 1) const Text('x2', style: TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold)),
                    if (_speedBoost > 1) const Icon(Icons.speed, color: Colors.orange, size: 30),
                  ],
                ),
              ),

            // Menu
            if (_gameState == GameState.menu)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('INFINITE RUNNER', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _startGame,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
                      child: const Text('START GAME', style: TextStyle(fontSize: 24)),
                    ),
                  ],
                ),
              ),

            // Game Over
            if (_gameState == GameState.gameOver)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('GAME OVER', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.red)),
                      const SizedBox(height: 20),
                      Text('Score: $_score', style: const TextStyle(fontSize: 24, color: Colors.white)),
                      Text('High Score: $_highScore', style: const TextStyle(fontSize: 24, color: Colors.white)),
                      const SizedBox(height: 40),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => setState(() => _gameState = GameState.menu),
                            icon: const Icon(Icons.home),
                            label: const Text('Home'),
                          ),
                          const SizedBox(width: 20),
                          ElevatedButton.icon(
                            onPressed: _startGame,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Restart'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GameRenderer extends CustomPainter {
  final double distance;
  final int lane;
  final double jumpY;
  final List<GameObject> objects;
  final Biome biome;
  final bool isSliding;
  final bool hasShield;

  GameRenderer({
    required this.distance,
    required this.lane,
    required this.jumpY,
    required this.objects,
    required this.biome,
    required this.isSliding,
    required this.hasShield,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Colors based on biome
    Color skyColor, groundColor, roadColor, fogColor;
    
    switch (biome) {
      case Biome.city:
        skyColor = Colors.lightBlue[200]!; groundColor = Colors.grey[700]!; roadColor = Colors.grey[900]!; fogColor = Colors.white54; break;
      case Biome.desert:
        skyColor = Colors.orange[200]!; groundColor = Colors.orange[400]!; roadColor = Colors.orange[800]!; fogColor = Colors.orange[200]!; break;
      case Biome.jungle:
        skyColor = Colors.blue[300]!; groundColor = Colors.green[800]!; roadColor = Colors.brown[700]!; fogColor = Colors.green[100]!; break;
      case Biome.snowyMountains:
        skyColor = Colors.grey[400]!; groundColor = Colors.white; roadColor = Colors.blueGrey[200]!; fogColor = Colors.white; break;
      case Biome.nightCity:
        skyColor = Colors.black87; groundColor = Colors.blueGrey[900]!; roadColor = Colors.black; fogColor = Colors.deepPurple[900]!; break;
      case Biome.futuristicCity:
        skyColor = Colors.deepPurple; groundColor = Colors.purple[900]!; roadColor = Colors.cyan[900]!; fogColor = Colors.cyanAccent; break;
      default:
        skyColor = Colors.lightBlue; groundColor = Colors.green; roadColor = Colors.grey; fogColor = Colors.white30; break;
    }

    // Sky
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height / 2), Paint()..color = skyColor);
    
    // Sun / Moon / Scenery
    if (biome == Biome.nightCity || biome == Biome.futuristicCity) {
      canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.2), 40, Paint()..color = Colors.white70);
    } else {
      canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.2), 50, Paint()..color = Colors.yellow);
    }

    // Ground
    canvas.drawRect(Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2), Paint()..color = groundColor);

    double horizon = size.height / 2;
    double fov = 300.0; // Field of view depth factor

    // Function to project 3D coordinate to 2D screen
    Offset project(double x, double y, double z) {
      double scale = fov / (fov + z);
      double sx = (size.width / 2) + (x * scale);
      double sy = horizon + (y * scale);
      return Offset(sx, sy);
    }

    // Draw road
    Path roadPath = Path();
    double roadWidth = 200.0;
    Offset bl = project(-roadWidth, 100, 0);
    Offset br = project(roadWidth, 100, 0);
    Offset tl = project(-roadWidth, 100, 1000);
    Offset tr = project(roadWidth, 100, 1000);
    
    roadPath.moveTo(bl.dx, bl.dy);
    roadPath.lineTo(br.dx, br.dy);
    roadPath.lineTo(tr.dx, tr.dy);
    roadPath.lineTo(tl.dx, tl.dy);
    roadPath.close();
    canvas.drawPath(roadPath, Paint()..color = roadColor);

    // Draw grid/stripes on ground to show movement
    Paint stripePaint = Paint()..color = Colors.white;
    for (int i = 0; i < 20; i++) {
      double z = ((i * 50.0) - (distance % 50.0));
      if (z > 0 && z < 1000) {
        Offset sbl = project(-roadWidth, 100, z);
        Offset sbr = project(roadWidth, 100, z);
        double thickness = (fov / (fov + z)) * 10;
        canvas.drawRect(Rect.fromLTRB(sbl.dx, sbl.dy, sbr.dx, sbl.dy + thickness), stripePaint);
      }
    }

    // Sort objects back to front
    List<GameObject> sortedObjects = List.from(objects);
    sortedObjects.sort((a, b) => b.z.compareTo(a.z));

    for (var obj in sortedObjects) {
      double relZ = obj.z - distance;
      if (relZ > 0 && relZ < 1000) {
        double x = obj.lane * 130.0;
        double y = 100.0; // Base ground level
        
        Offset p = project(x, y, relZ);
        double scale = fov / (fov + relZ);

        if (obj.type == 0) {
          // Coin
          canvas.drawCircle(Offset(p.dx, p.dy - (20 * scale)), 15 * scale, Paint()..color = Colors.amber);
        } else if (obj.type == 1) {
          // Barrier
          canvas.drawRect(Rect.fromCenter(center: Offset(p.dx, p.dy - (40 * scale)), width: 100 * scale, height: 80 * scale), Paint()..color = Colors.redAccent);
        } else if (obj.type == 2) {
          // Gap
          canvas.drawRect(Rect.fromCenter(center: Offset(p.dx, p.dy), width: 130 * scale, height: 50 * scale), Paint()..color = skyColor);
        } else if (obj.type == 3) {
          // Magnet
          canvas.drawCircle(Offset(p.dx, p.dy - (20 * scale)), 15 * scale, Paint()..color = Colors.red);
        } else if (obj.type == 4) {
          // Shield
          canvas.drawCircle(Offset(p.dx, p.dy - (20 * scale)), 15 * scale, Paint()..color = Colors.blue);
        }
      }
    }

    // Draw Player
    double playerX = lane * 130.0;
    double playerY = 100.0 - jumpY;
    Offset playerP = project(playerX, playerY, 50.0); // Player is slightly ahead of camera
    double pScale = fov / (fov + 50.0);
    
    Paint playerPaint = Paint()..color = Colors.greenAccent;
    double pWidth = 40 * pScale;
    double pHeight = isSliding ? 40 * pScale : 80 * pScale;
    
    Rect playerRect = Rect.fromCenter(center: Offset(playerP.dx, playerP.dy - (pHeight / 2)), width: pWidth, height: pHeight);
    canvas.drawRect(playerRect, playerPaint);

    if (hasShield) {
      canvas.drawCircle(playerRect.center, pHeight * 0.8, Paint()..color = Colors.blue.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 4);
    }

    // Fog overlay based on biome
    canvas.drawRect(Rect.fromLTWH(0, horizon - 50, size.width, 100), Paint()..color = fogColor.withOpacity(0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20));
  }
}
