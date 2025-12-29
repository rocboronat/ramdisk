import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MemDiskApp());
}

enum RamDiskBackend { none, imdisk }

class MemDiskApp extends StatelessWidget {
  const MemDiskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MemDisk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF3D71),
          surface: Color(0xFF1A1A1A),
        ),
        fontFamily: 'Segoe UI',
      ),
      home: const RamDiskScreen(),
    );
  }
}

class RamDiskScreen extends StatefulWidget {
  const RamDiskScreen({super.key});

  @override
  State<RamDiskScreen> createState() => _RamDiskScreenState();
}

class _RamDiskScreenState extends State<RamDiskScreen>
    with SingleTickerProviderStateMixin {
  bool _isRunning = false;
  bool _isLoading = false;
  String _statusMessage = 'Checking for RAM disk driver...';
  String _driveLetter = 'R';
  double _sizeGB = 1.0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  RamDiskBackend _backend = RamDiskBackend.none;
  bool _showInstallDialog = false;
  late TextEditingController _sizeController;
  bool _persistenceEnabled = true;

  /// Get the backup directory path for the current drive letter
  String get _backupPath {
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    return '$userProfile\\.memdisk\\$_driveLetter';
  }

  @override
  void initState() {
    super.initState();
    _sizeController = TextEditingController(text: _sizeGB.toString());
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _detectBackend();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _sizeController.dispose();
    super.dispose();
  }

  Future<void> _detectBackend() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Detecting RAM disk driver...';
    });

    // Check for ImDisk
    try {
      final result = await Process.run('where', ['imdisk']);
      if (result.exitCode == 0) {
        setState(() {
          _backend = RamDiskBackend.imdisk;
          _statusMessage = 'Ready — ImDisk driver detected';
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    // No backend found
    setState(() {
      _backend = RamDiskBackend.none;
      _statusMessage = 'No RAM disk driver found';
      _isLoading = false;
      _showInstallDialog = true;
    });
  }

  /// Check if backup exists for the current drive letter
  Future<bool> _backupExists() async {
    final dir = Directory(_backupPath);
    return await dir.exists();
  }

  /// Restore contents from backup to the RAM disk
  Future<bool> _restoreFromBackup() async {
    if (!_persistenceEnabled) return true;
    
    final backupDir = Directory(_backupPath);
    if (!await backupDir.exists()) {
      return true; // No backup to restore, that's OK
    }

    setState(() {
      _statusMessage = 'Restoring data from backup...';
    });

    try {
      // Use robocopy to restore files (mirrors the backup to the RAM disk)
      final result = await Process.run(
        'robocopy',
        [
          _backupPath,
          '$_driveLetter:\\',
          '/E',      // Copy subdirectories including empty ones
          '/R:1',    // 1 retry
          '/W:1',    // 1 second wait
          '/NJH',    // No job header
          '/NJS',    // No job summary
          '/NDL',    // No directory list
          '/NC',     // No file class
          '/NS',     // No file size
          '/NP',     // No progress
          '/XD', 'System Volume Information', '\$RECYCLE.BIN', // Exclude system dirs
          '/XF', '*.sys', 'pagefile.sys', 'hiberfil.sys',      // Exclude system files
        ],
        runInShell: true,
      );
      
      // Robocopy returns 0-7 for success, 8+ for errors
      return result.exitCode < 8;
    } catch (e) {
      return false;
    }
  }

  /// Save RAM disk contents to backup
  Future<bool> _saveToBackup() async {
    if (!_persistenceEnabled) return true;
    
    setState(() {
      _statusMessage = 'Saving data to backup...';
    });

    try {
      // Ensure backup directory exists
      final backupDir = Directory(_backupPath);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // Use robocopy to save files (mirrors the RAM disk to backup)
      final result = await Process.run(
        'robocopy',
        [
          '$_driveLetter:\\',
          _backupPath,
          '/MIR',    // Mirror mode
          '/R:1',    // 1 retry
          '/W:1',    // 1 second wait
          '/NJH',    // No job header
          '/NJS',    // No job summary
          '/NDL',    // No directory list
          '/NC',     // No file class
          '/NS',     // No file size
          '/NP',     // No progress
          '/XD', 'System Volume Information', '\$RECYCLE.BIN', // Exclude system dirs
          '/XF', '*.sys', 'pagefile.sys', 'hiberfil.sys',      // Exclude system files
        ],
        runInShell: true,
      );
      
      // Robocopy returns 0-7 for success, 8+ for errors
      return result.exitCode < 8;
    } catch (e) {
      return false;
    }
  }

  Future<void> _installImDisk() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Installing ImDisk via winget...';
      _showInstallDialog = false;
    });

    try {
      // Try winget first
      final result = await Process.run(
        'winget',
        ['install', '--id', 'ImDisk.Toolkit', '-e', '--accept-source-agreements', '--accept-package-agreements'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        setState(() {
          _statusMessage = 'ImDisk installed! Please restart the app.';
        });
        // Re-detect after install
        await Future.delayed(const Duration(seconds: 2));
        await _detectBackend();
      } else {
        setState(() {
          _statusMessage = 'Install failed. Try manual installation.';
          _showInstallDialog = true;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Install failed: $e';
        _showInstallDialog = true;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startRamDisk() async {
    if (_backend == RamDiskBackend.none) {
      setState(() {
        _showInstallDialog = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Creating RAM Disk...';
    });

    try {
      final sizeBytes = (_sizeGB * 1024 * 1024 * 1024).round();
      final sizeDisplay = _sizeGB == _sizeGB.roundToDouble() 
          ? '${_sizeGB.toInt()}GB' 
          : '${_sizeGB}GB';
      
      if (_backend == RamDiskBackend.imdisk) {
        // Create RAM disk using ImDisk
        final result = await Process.run(
          'imdisk',
          ['-a', '-s', '$sizeBytes', '-m', '$_driveLetter:', '-o', 'rem'],
          runInShell: true,
        );

        if (result.exitCode == 0) {
          setState(() {
            _statusMessage = 'Formatting RAM Disk...';
          });
          
          // Wait for Windows to recognize the new volume
          await Future.delayed(const Duration(seconds: 1));
          
          // Create a diskpart script file
          final tempDir = Directory.systemTemp;
          final scriptFile = File('${tempDir.path}\\memdisk_format.txt');
          await scriptFile.writeAsString('select volume $_driveLetter\nformat fs=ntfs quick label=RAMDISK\n');
          
          // Run diskpart with the script
          final diskpartResult = await Process.run(
            'diskpart',
            ['/s', scriptFile.path],
            runInShell: true,
          );
          
          // Clean up script file
          try {
            await scriptFile.delete();
          } catch (_) {}
          
          // If diskpart failed, try PowerShell Initialize-Disk + Format-Volume
          if (diskpartResult.exitCode != 0) {
            await Process.run(
              'powershell',
              [
                '-NoProfile',
                '-Command',
                '''
                \$vol = Get-Volume -DriveLetter $_driveLetter -ErrorAction SilentlyContinue
                if (\$vol) {
                  Format-Volume -DriveLetter $_driveLetter -FileSystem NTFS -NewFileSystemLabel RAMDISK -Confirm:\$false -Force
                }
                '''
              ],
              runInShell: true,
            );
          }
          
          // Wait for format to complete
          await Future.delayed(const Duration(seconds: 2));
          
          // Verify the drive is accessible by trying to list it
          bool driveReady = false;
          for (int i = 0; i < 5; i++) {
            try {
              final dir = Directory('$_driveLetter:\\');
              await dir.list().first.timeout(
                const Duration(seconds: 2),
                onTimeout: () => throw TimeoutException('Drive not ready'),
              );
              driveReady = true;
              break;
            } catch (_) {
              // Drive not ready yet, wait and retry
              await Future.delayed(const Duration(milliseconds: 500));
            }
          }
          
          if (!driveReady) {
            // Try one more approach - just check if we can create a temp file
            try {
              final testFile = File('$_driveLetter:\\__memdisk_test__');
              await testFile.writeAsString('test');
              await testFile.delete();
              driveReady = true;
            } catch (_) {
              setState(() {
                _statusMessage = 'Warning: Drive may not be ready';
              });
              await Future.delayed(const Duration(seconds: 1));
            }
          }
          
          // Check if we have a backup to restore
          final hasBackup = await _backupExists();
          
          if (hasBackup && _persistenceEnabled) {
            setState(() {
              _statusMessage = 'Restoring previous data...';
            });
            
            final restored = await _restoreFromBackup();
            if (!restored) {
              // Restoration failed but disk is created, continue anyway
              setState(() {
                _statusMessage = 'Warning: Could not restore backup';
              });
              await Future.delayed(const Duration(seconds: 1));
            }
          }
          
          setState(() {
            _isRunning = true;
            _statusMessage = hasBackup && _persistenceEnabled
                ? 'RAM Disk active on $_driveLetter: ($sizeDisplay) — Data restored'
                : 'RAM Disk active on $_driveLetter: ($sizeDisplay)';
          });
          _pulseController.repeat(reverse: true);
        } else {
          final errorMsg = result.stderr.toString().trim();
          setState(() {
            _statusMessage = errorMsg.isNotEmpty ? errorMsg : 'Failed to create RAM disk';
          });
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _stopRamDisk() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Saving data...';
    });

    try {
      // Save data before unmounting
      if (_persistenceEnabled) {
        final saved = await _saveToBackup();
        if (!saved) {
          // Ask user if they want to continue without saving
          setState(() {
            _statusMessage = 'Warning: Could not save data. Unmounting anyway...';
          });
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      setState(() {
        _statusMessage = 'Unmounting RAM Disk...';
      });

      if (_backend == RamDiskBackend.imdisk) {
        var result = await Process.run(
          'imdisk',
          ['-d', '-m', '$_driveLetter:'],
          runInShell: true,
        );

        if (result.exitCode != 0) {
          // Try force remove
          result = await Process.run(
            'imdisk',
            ['-D', '-m', '$_driveLetter:'],
            runInShell: true,
          );
        }

        if (result.exitCode == 0) {
          _pulseController.stop();
          _pulseController.reset();
          setState(() {
            _isRunning = false;
            _statusMessage = _persistenceEnabled 
                ? 'RAM Disk stopped — Data saved'
                : 'RAM Disk stopped';
          });
        } else {
          setState(() {
            _statusMessage = 'Failed to remove RAM disk';
          });
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _copyCommand(String command) {
    Clipboard.setData(ClipboardData(text: command));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Command copied to clipboard'),
        backgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.9),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.5,
                colors: [
                  Color(0xFF0F1922),
                  Color(0xFF0A0A0F),
                ],
              ),
            ),
          ),
          // Grid pattern overlay
          CustomPaint(
            size: Size.infinite,
            painter: _GridPainter(),
          ),
          // Main content
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF00B8D4)],
                    ).createShader(bounds),
                    child: const Text(
                      'MEMDISK',
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w200,
                        letterSpacing: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'RAM DISK MANAGER',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 6,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  const SizedBox(height: 70),

                  // Main Button
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isRunning ? _pulseAnimation.value : 1.0,
                        child: child,
                      );
                    },
                    child: GestureDetector(
                      onTap: _isLoading || _backend == RamDiskBackend.none
                          ? (_backend == RamDiskBackend.none && !_isLoading
                              ? () => setState(() => _showInstallDialog = true)
                              : null)
                          : (_isRunning ? _stopRamDisk : _startRamDisk),
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: _isRunning
                                ? [
                                    const Color(0xFF00E5FF).withValues(alpha: 0.25),
                                    const Color(0xFF00E5FF).withValues(alpha: 0.02),
                                  ]
                                : _backend == RamDiskBackend.none
                                    ? [
                                        const Color(0xFF1A1A1A),
                                        const Color(0xFF0F0F0F),
                                      ]
                                    : [
                                        const Color(0xFF1E2A30),
                                        const Color(0xFF12181C),
                                      ],
                          ),
                          border: Border.all(
                            color: _isRunning
                                ? const Color(0xFF00E5FF)
                                : _backend == RamDiskBackend.none
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : const Color(0xFF00E5FF).withValues(alpha: 0.3),
                            width: 2,
                          ),
                          boxShadow: _isRunning
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                                    blurRadius: 40,
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                                    blurRadius: 80,
                                    spreadRadius: 10,
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF00E5FF),
                                    ),
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _backend == RamDiskBackend.none
                                          ? Icons.download_rounded
                                          : _isRunning
                                              ? Icons.stop_rounded
                                              : Icons.play_arrow_rounded,
                                      size: 56,
                                      color: _isRunning
                                          ? const Color(0xFF00E5FF)
                                          : _backend == RamDiskBackend.none
                                              ? Colors.white.withValues(alpha: 0.4)
                                              : Colors.white.withValues(alpha: 0.8),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _backend == RamDiskBackend.none
                                          ? 'INSTALL'
                                          : _isRunning
                                              ? 'STOP'
                                              : 'START',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w300,
                                        letterSpacing: 4,
                                        color: _isRunning
                                            ? const Color(0xFF00E5FF)
                                            : _backend == RamDiskBackend.none
                                                ? Colors.white.withValues(alpha: 0.4)
                                                : Colors.white.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 50),

                  // Status
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: _isRunning
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRunning
                                ? const Color(0xFF00E5FF)
                                : _backend != RamDiskBackend.none
                                    ? const Color(0xFF4CAF50)
                                    : Colors.orange.withValues(alpha: 0.7),
                            boxShadow: _isRunning
                                ? [
                                    const BoxShadow(
                                      color: Color(0xFF00E5FF),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 350),
                          child: Text(
                            _statusMessage,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.65),
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Drive letter and size selector
                  if (_backend != RamDiskBackend.none && !_isRunning && !_isLoading)
                    _buildSettings(),
                ],
              ),
            ),
          ),

          // Install dialog overlay
          if (_showInstallDialog) _buildInstallDialog(),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSettingItem(
            'DRIVE',
            DropdownButton<String>(
              value: _driveLetter,
              dropdownColor: const Color(0xFF1A1A1A),
              underline: const SizedBox(),
              isDense: true,
              style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              items: ['R', 'Z', 'Y', 'X', 'W', 'V']
                  .map((letter) => DropdownMenuItem(
                        value: letter,
                        child: Text('$letter:'),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _driveLetter = value;
                  });
                }
              },
            ),
          ),
          const SizedBox(width: 40),
          _buildSettingItem(
            'SIZE (GB)',
            SizedBox(
              width: 70,
              child: TextField(
                controller: _sizeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                onChanged: (value) {
                  final parsed = double.tryParse(value);
                  if (parsed != null && parsed > 0) {
                    setState(() {
                      _sizeGB = parsed;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 40),
          _buildSettingItem(
            'PERSIST',
            Tooltip(
              message: _persistenceEnabled 
                  ? 'Data will be saved when stopped\nBackup: $_backupPath'
                  : 'Data will be lost when stopped',
              child: Switch(
                value: _persistenceEnabled,
                onChanged: (value) {
                  setState(() {
                    _persistenceEnabled = value;
                  });
                },
                activeColor: const Color(0xFF00E5FF),
                activeTrackColor: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                inactiveThumbColor: Colors.white.withValues(alpha: 0.5),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem(String label, Widget child) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 2,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildInstallDialog() {
    return GestureDetector(
      onTap: () => setState(() => _showInstallDialog = false),
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent closing when tapping dialog
              child: Container(
              width: 450,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF12161A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 40,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.memory,
                          color: Color(0xFF00E5FF),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Driver Required',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Install ImDisk Toolkit to create RAM disks',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _showInstallDialog = false),
                        icon: Icon(
                          Icons.close,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  
                  // Option 1: Winget
                  _buildInstallOption(
                    icon: Icons.terminal,
                    title: 'Install via Winget',
                    subtitle: 'Recommended — automatic installation',
                    command: 'winget install ImDisk.Toolkit',
                    onInstall: _installImDisk,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Option 2: Chocolatey
                  _buildInstallOption(
                    icon: Icons.folder_zip,
                    title: 'Install via Chocolatey',
                    subtitle: 'Run in admin PowerShell',
                    command: 'choco install imdisk-toolkit -y',
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Option 3: Manual
                  _buildInstallOption(
                    icon: Icons.download,
                    title: 'Manual Download',
                    subtitle: 'Download from SourceForge',
                    command: 'https://sourceforge.net/projects/imdisk-toolkit/',
                    isUrl: true,
                  ),

                  const SizedBox(height: 24),
                  
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.amber.withValues(alpha: 0.8),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'ImDisk Toolkit is open-source and still maintained via package managers (latest: Feb 2025).',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  
                  // Refresh button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() => _showInstallDialog = false);
                        _detectBackend();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh Detection'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF00E5FF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstallOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String command,
    bool isUrl = false,
    VoidCallback? onInstall,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF00E5FF), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    command,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Consolas',
                      color: isUrl ? const Color(0xFF00E5FF) : Colors.white.withValues(alpha: 0.8),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _copyCommand(command),
                icon: const Icon(Icons.copy, size: 18),
                color: Colors.white.withValues(alpha: 0.5),
                tooltip: 'Copy',
              ),
              if (onInstall != null) ...[
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: onInstall,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Install',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 1;

    const spacing = 40.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
