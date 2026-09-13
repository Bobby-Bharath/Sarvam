import 'package:flutter/material.dart';
import '../../engine/plugins/plugin_registry.dart';

class PluginSettingsPage extends StatefulWidget {
  const PluginSettingsPage({super.key});

  @override
  State<PluginSettingsPage> createState() => _PluginSettingsPageState();
}

class _PluginSettingsPageState extends State<PluginSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final plugins = PluginRegistry.instance.availablePlugins;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('Metadata & Sync Plugins', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: plugins.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final plugin = plugins[index];
          final isEnabled = PluginRegistry.instance.isEnabled(plugin.id);
          final isPrimary = PluginRegistry.instance.isPrimary(plugin.id);

          return Card(
            color: Colors.white.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: isPrimary ? const BorderSide(color: Colors.redAccent, width: 1) : BorderSide.none),
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isEnabled ? Colors.redAccent.withValues(alpha: 0.1) : Colors.white10,
                    child: Icon(Icons.extension, color: isEnabled ? Colors.redAccent : Colors.white24),
                  ),
                  title: Text(plugin.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(isPrimary ? 'Primary Provider' : 'Secondary Provider', style: TextStyle(color: isPrimary ? Colors.redAccent : Colors.white38, fontSize: 11)),
                  trailing: Switch(
                    value: isEnabled,
                    onChanged: (v) async {
                      await PluginRegistry.instance.togglePlugin(plugin.id, v);
                      setState(() {});
                    },
                  ),
                ),
                if (isEnabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(isPrimary ? Icons.star : Icons.star_border, size: 16),
                            label: const Text('Set Primary', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isPrimary ? Colors.redAccent : Colors.white70,
                              side: BorderSide(color: isPrimary ? Colors.redAccent : Colors.white10),
                            ),
                            onPressed: isPrimary ? null : () async {
                              await PluginRegistry.instance.setPrimary(plugin.id);
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white10,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              // TODO: Auth Flow
                            },
                            child: const Text('Configure', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
