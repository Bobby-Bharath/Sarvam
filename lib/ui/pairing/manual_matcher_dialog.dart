import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../engine/plugins/plugin_registry.dart';
import '../../engine/plugins/models/plugin_models.dart';
import 'interactive_mapping_page.dart';
import '../../engine/metadata/filename_tokenizer.dart';

class ManualMatcherDialog {
  static void show(BuildContext context, {AssetPathEntity? folder, AssetEntity? video, VoidCallback? onComplete}) async {
    final String initialQuery = folder?.name ?? video?.title ?? '';
    final token = FilenameTokenizer.parse(initialQuery);
    final TextEditingController searchController = TextEditingController(text: token.cleanTitle);
    List<MediaSearchResult> results = [];
    bool isSearching = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(folder != null ? 'Pair Folder' : 'Pair Video', style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search Providers...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, color: Colors.redAccent),
                      onPressed: () async {
                        setDialogState(() => isSearching = true);
                        final list = await PluginRegistry.instance.searchUnified(searchController.text);
                        setDialogState(() {
                          results = list;
                          isSearching = false;
                        });
                      },
                    ),
                  ),
                  onSubmitted: (v) async {
                    setDialogState(() => isSearching = true);
                    final list = await PluginRegistry.instance.searchUnified(v);
                    setDialogState(() {
                      results = list;
                      isSearching = false;
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (isSearching)
                  const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(color: Colors.redAccent),
                  )
                else if (results.isEmpty && searchController.text.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text('No results found.', style: TextStyle(color: Colors.white38)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final res = results[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: res.posterUrl != null 
                              ? Image.network(res.posterUrl!, width: 40, height: 60, fit: BoxFit.cover)
                              : Container(width: 40, height: 60, color: Colors.white10, child: const Icon(Icons.movie)),
                          ),
                          title: Text(res.title, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${res.year ?? "Unknown Year"} · ${res.totalEpisodes ?? "?"} Eps (${res.providerId})', style: const TextStyle(fontSize: 11, color: Colors.white38)),
                          onTap: () async {
                            Navigator.pop(context);
                            
                            List<AssetEntity> files = [];
                            String? folderPath;
                            if (folder != null) {
                              files = await folder.getAssetListRange(start: 0, end: 1000);
                              if (files.isNotEmpty) {
                                 final firstFile = await files.first.originFile;
                                 folderPath = firstFile?.parent.path;
                              }
                            } else if (video != null) {
                              files = [video];
                            }

                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => InteractiveMappingPage(
                                    files: files,
                                    media: res,
                                    folderId: folder?.id,
                                    folderPath: folderPath,
                                  ),
                                ),
                              ).then((_) => onComplete?.call());
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ],
        ),
      ),
    );
  }
}
