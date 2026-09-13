import 'package:flutter/material.dart';
import '../../database/media_database.dart';

class PairingManagerPage extends StatefulWidget {
  const PairingManagerPage({super.key});

  @override
  State<PairingManagerPage> createState() => _PairingManagerPageState();
}

class _PairingManagerPageState extends State<PairingManagerPage> {
  List<Map<String, dynamic>> _franchises = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPairs();
  }

  Future<void> _loadPairs() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final db = MediaDatabase.instance;
    final all = await db.getAllMediaEntities();
    
    // Group by franchise_id or title
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (var entity in all) {
      final key = entity['franchise_id'] ?? entity['folder_path'] ?? entity['title'];
      groups.putIfAbsent(key, () => []).add(entity);
    }
    
    if (mounted) {
      setState(() {
        _franchises = groups.values.map((group) {
          // Use the first entry as the representative for the card
          final base = group.first;
          return {
            'id': base['id'],
            'title': base['title'],
            'poster_url': base['poster_url'],
            'provider': base['display_provider'],
            'entities': group,
            'franchise_id': base['franchise_id'],
          };
        }).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('Pairing Manager', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : _franchises.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _franchises.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final franchise = _franchises[index];
                    return _buildFranchiseCard(franchise);
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.link_off, size: 64, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          const Text('No active metadata pairings.', style: TextStyle(color: Colors.white38)),
          const SizedBox(height: 8),
          const Text('Pair folders or files from the Browse tab.', style: TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildFranchiseCard(Map<String, dynamic> franchise) {
    final List<Map<String, dynamic>> entities = franchise['entities'];

    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: franchise['poster_url'] != null
                      ? Image.network(franchise['poster_url'], width: 50, height: 75, fit: BoxFit.cover)
                      : Container(width: 50, height: 75, color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white24)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(franchise['title'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('Collection: ${entities.length} items · ${franchise['provider']}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                  tooltip: 'Unpair Entire Franchise',
                  onPressed: () => _confirmUnlinkFranchise(franchise),
                ),
              ],
            ),
            const Divider(height: 24, color: Colors.white10),
            ...entities.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.white24),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e['title'], style: const TextStyle(color: Colors.white70, fontSize: 12))),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: MediaDatabase.instance.getLocalFilesForEntity(e['id']),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return Text('$count files', style: const TextStyle(color: Colors.white24, fontSize: 10));
                    },
                  ),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }

  void _confirmUnlinkFranchise(Map<String, dynamic> franchise) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Unpair Entire Franchise?', style: TextStyle(color: Colors.white)),
        content: Text('This will remove ALL metadata associations for "${franchise['title']}" and its sequels/movies.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await MediaDatabase.instance.deleteMediaEntity(franchise['id']);
              _loadPairs();
            },
            child: const Text('Unpair All', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
