import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

class LocalFolderBrowserPage extends StatefulWidget {
  final Function(String path) onDirectorySelected;
  final String? initialPath;

  const LocalFolderBrowserPage({
    super.key,
    required this.onDirectorySelected,
    this.initialPath,
  });

  @override
  State<LocalFolderBrowserPage> createState() => _LocalFolderBrowserPageState();
}

class _LocalFolderBrowserPageState extends State<LocalFolderBrowserPage> {
  late Directory _currentDirectory;
  List<FileSystemEntity> _entities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initPath();
  }

  Future<void> _initPath() async {
    if (widget.initialPath != null && Directory(widget.initialPath!).existsSync()) {
      _currentDirectory = Directory(widget.initialPath!);
    } else {
      // Default to common storage path on Android or root
      _currentDirectory = Directory('/storage/emulated/0');
      if (!_currentDirectory.existsSync()) {
        _currentDirectory = Directory.current;
      }
    }
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() => _isLoading = true);
    try {
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted || await Permission.storage.isGranted) {
        final List<FileSystemEntity> list = _currentDirectory.listSync().where((e) => e is Directory).toList();
        list.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
        setState(() {
          _entities = list;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading directory: $e');
      setState(() => _isLoading = false);
    }
  }

  void _goBack() {
    final parent = _currentDirectory.parent;
    if (parent.path != _currentDirectory.path) {
      setState(() {
        _currentDirectory = parent;
      });
      _loadDirectory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Folder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(_currentDirectory.path, style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          if (_currentDirectory.path != '/' && _currentDirectory.path != 'C:\\')
            ListTile(
              leading: const Icon(Icons.arrow_upward, color: Colors.white24),
              title: const Text('..', style: TextStyle(color: Colors.white70)),
              onTap: _goBack,
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : ListView.builder(
                    itemCount: _entities.length,
                    itemBuilder: (context, index) {
                      final dir = _entities[index] as Directory;
                      return ListTile(
                        leading: const Icon(Icons.folder, color: Colors.amber),
                        title: Text(p.basename(dir.path), style: const TextStyle(fontSize: 14)),
                        onTap: () {
                          setState(() => _currentDirectory = dir);
                          _loadDirectory();
                        },
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)],
            ),
            child: SafeArea(
              top: false,
              child: ElevatedButton(
                onPressed: () => widget.onDirectorySelected(_currentDirectory.path),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Select Current Folder', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
